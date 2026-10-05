#!/usr/bin/env node
// Download a protected baseline into a NEW directory outside the original
// workspace. Verify every actual object byte against its captured SHA-256.
// Never restore in place, extract phone data, or modify production/cloud data.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const uri = process.argv[2] || '';
const destination = process.argv[3] && path.resolve(process.argv[3]);
const hashIndex = process.argv.indexOf('--manifest-sha256');
const expectedManifestHash = hashIndex >= 0 ? process.argv[hashIndex + 1] : null;
const match = /^gs:\/\/(prox-42bef-rollback-us-central1)\/(pre-growth-20261005_094316\/full-local-baseline-[A-Za-z0-9]+)\/cloud-upload-manifest\.json$/.exec(uri);
if (!match || !destination || fs.existsSync(destination) || expectedManifestHash && !/^[0-9a-f]{64}$/.test(expectedManifestHash)) {
  console.error('Usage: node download_growth_rollback.cjs PRIVATE_MANIFEST_GS_URI NEW_OUTSIDE_WORKSPACE_DIRECTORY [--manifest-sha256 HASH]');
  process.exit(1);
}
const bucket = match[1], prefix = match[2];
process.env.DEBUG = '';
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm', 'node_modules', 'firebase-tools', 'lib');
require(path.join(cli, 'logger')).logger.silent = true;
const auth = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
let token;
let completed = 0;
const objectUrl = (object, generation) => `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(object)}?alt=media${generation ? '&generation=' + encodeURIComponent(generation) : ''}`;
function outside(child, parent) {
  if (process.platform === 'win32') {child = child.toLowerCase(); parent = parent.toLowerCase();}
  return child !== parent && !child.startsWith(parent + path.sep);
}
function safeRelative(relative) {
  if (typeof relative !== 'string' || !relative || relative.includes('\\') || relative.includes(':') ||
      relative.startsWith('/') || relative.split('/').some(part => !part || part === '.' || part === '..')) {
    throw Object.assign(new Error(), {code: 'unsafe-manifest-path'});
  }
  return relative;
}
async function getObject(object, generation) {
  const response = await fetch(objectUrl(object, generation), {headers: {Authorization: `Bearer ${token}`}, signal: AbortSignal.timeout(300000)});
  if (!response.ok) throw Object.assign(new Error(), {code: `download-http-${response.status}`});
  return response;
}
async function main() {
  const options = {project: 'prox-42bef', ...auth.getGlobalDefaultAccount()};
  await requireAuth(options);
  token = (await auth.getAccessToken(options.tokens.refresh_token, options.authScopes)).access_token;
  const response = await getObject(prefix + '/cloud-upload-manifest.json');
  const manifestBytes = Buffer.from(await response.arrayBuffer());
  const manifestHash = crypto.createHash('sha256').update(manifestBytes).digest('hex');
  if (expectedManifestHash && expectedManifestHash !== manifestHash) throw Object.assign(new Error(), {code: 'manifest-sha256-mismatch'});
  const manifest = JSON.parse(manifestBytes);
  if (manifest.verified !== true || manifest.bucket !== bucket || manifest.prefix !== prefix ||
      !manifest.source || !manifest.files || Object.keys(manifest.files).length !== manifest.fileCount ||
      manifest.fileCount > 5000 || manifest.size > 4 * 1024 ** 3) throw Object.assign(new Error(), {code: 'manifest-ownership-or-size-mismatch'});
  const originalWorkspace = path.resolve(JSON.parse((await (await getObject(prefix + '/manifest.json', manifest.files['manifest.json']?.generation)).text())).workspace);
  if (!outside(destination, originalWorkspace) || !outside(destination, path.resolve(__dirname, '../..'))) {
    throw Object.assign(new Error(), {code: 'destination-must-be-outside-active-and-original-workspace'});
  }
  const queue = Object.entries(manifest.files).map(([relative, file]) => {
    safeRelative(relative);
    if (file.object !== prefix + '/' + relative || !/^\d+$/.test(String(file.generation)) ||
        !/^[0-9a-f]{64}$/.test(file.sha256) || !Number.isSafeInteger(file.size) || file.size < 0) {
      throw Object.assign(new Error(), {code: 'invalid-file-manifest'});
    }
    return {relative, ...file};
  });
  if (queue.reduce((n, file) => n + file.size, 0) !== manifest.size) throw Object.assign(new Error(), {code: 'manifest-total-size-mismatch'});
  fs.mkdirSync(destination, {recursive: true, mode: 0o700});
  // The uploaded manifest is separate from its own frozen baseline membership.
  fs.writeFileSync(path.join(destination, 'cloud-upload-manifest.json'), manifestBytes, {mode: 0o600});
  const verified = [];
  await Promise.all(Array.from({length: 3}, async () => {
    while (queue.length) {
      const file = queue.shift();
      const target = path.join(destination, ...file.relative.split('/'));
      if (outside(target, destination)) throw Object.assign(new Error(), {code: 'unsafe-download-target'});
      fs.mkdirSync(path.dirname(target), {recursive: true, mode: 0o700});
      const handle = await fs.promises.open(target, 'wx', 0o600);
      const hash = crypto.createHash('sha256');
      let size = 0;
      try {
        const remote = await getObject(file.object, file.generation);
        for await (const chunk of remote.body) {
          size += chunk.length;
          if (size > file.size) throw Object.assign(new Error(), {code: 'download-size-exceeded'});
          hash.update(chunk);
          let written = 0;
          while (written < chunk.length) {
            const result = await handle.write(chunk, written, chunk.length - written);
            if (!result.bytesWritten) throw Object.assign(new Error(), {code: 'file-write-failed'});
            written += result.bytesWritten;
          }
        }
      } finally {await handle.close();}
      if (size !== file.size || hash.digest('hex') !== file.sha256) throw Object.assign(new Error(), {code: 'actual-object-byte-verification-failed'});
      verified.push({relative: file.relative, generation: file.generation, size, sha256: file.sha256});
      completed++;
      if (completed % 20 === 0) console.log(JSON.stringify({downloadedAndVerified: completed, total: manifest.fileCount}));
    }
  }));
  fs.writeFileSync(path.join(destination, 'cloud-download-verification.json'), JSON.stringify({verified: true,
    verifiedAtUtc: new Date().toISOString(), manifestUri: uri, manifestSha256: manifestHash,
    fileCount: verified.length, size: manifest.size, actualSha256Verified: true, files: verified}, null, 2) + '\n', {mode: 0o600});
  console.log(JSON.stringify({verified: true, fileCount: verified.length, size: manifest.size, actualSha256Verified: true, destination}));
}
main().catch(error => {console.error(JSON.stringify({verified: false, completed, code: String(error.code || 'unknown').slice(0, 60)})); process.exitCode = 1;});
