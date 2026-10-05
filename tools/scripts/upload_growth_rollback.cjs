#!/usr/bin/env node
// Protective, private, immutable off-device backup. Never changes app data,
// deployed functions, rules, production policy, source objects, or public IAM.
// No OAuth tokens, upload-session URLs, or private payloads are logged.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {CRC32C} = require('../../functions/node_modules/@google-cloud/storage');
const project = 'prox-42bef';
const bucket = 'prox-42bef-rollback-us-central1';
const source = process.argv[2] && path.resolve(process.argv[2]);
const destination = process.argv[3] && path.resolve(process.argv[3]);
const execute = process.argv.includes('--execute');
const resume = process.argv.includes('--resume');
if (!source || !destination || !fs.existsSync(source) || !execute ||
    destination === source || destination.startsWith(source + path.sep) ||
    fs.existsSync(destination) && !resume) {
  console.error('Usage: node upload_growth_rollback.cjs PRIVATE_BASELINE NEW_PRIVATE_REPORT_DIRECTORY --execute [--resume]');
  process.exit(1);
}
process.env.DEBUG = '';
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm', 'node_modules', 'firebase-tools', 'lib');
require(path.join(cli, 'logger')).logger.silent = true;
const auth = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
let token;
let completed = 0;
let total = 0;
let stage = 'authentication';
const sha = b => crypto.createHash('sha256').update(b).digest('hex');
const save = (name, value) => fs.writeFileSync(path.join(destination, name), JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
const objectUrl = name => `https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(name)}`;
async function request(url, options = {}) {
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetch(url, {...options,
        headers: {Authorization: `Bearer ${token}`, ...options.headers}, signal: AbortSignal.timeout(90000)});
      if ([429, 500, 502, 503, 504].includes(response.status) && attempt < 3) {
        await response.arrayBuffer();
        await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
        continue;
      }
      return response;
    } catch (error) {
      if (attempt === 3) throw Object.assign(new Error(), {code: 'network-request-failed'});
      await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
    }
  }
}
async function jsonRequest(url, options = {}) {
  const response = await request(url, options);
  if (!response.ok) throw Object.assign(new Error(), {code: `http-${response.status}`});
  return response.json();
}
function walk(root) {
  return fs.readdirSync(root, {withFileTypes: true}).flatMap(entry => {
    const absolute = path.join(root, entry.name);
    if (entry.isSymbolicLink()) throw Object.assign(new Error(), {code: 'source-symlink-refused'});
    return entry.isDirectory() ? walk(absolute) : [absolute];
  });
}
async function digestFile(file) {
  const before = fs.statSync(file);
  const hash = crypto.createHash('sha256');
  const md5 = crypto.createHash('md5');
  const crc = new CRC32C();
  for await (const bytes of fs.createReadStream(file)) {
    hash.update(bytes); md5.update(bytes); crc.update(bytes);
  }
  const after = fs.statSync(file);
  if (before.size !== after.size || before.mtimeMs !== after.mtimeMs) throw Object.assign(new Error(), {code: 'source-changed-during-hash'});
  return {size: before.size, sha256: hash.digest('hex'), md5: md5.digest('base64'), crc32c: crc.toString(), mtimeMs: before.mtimeMs};
}
function checkMetadata(metadata, digest) {
  if (Number(metadata.size) !== digest.size || metadata.crc32c !== digest.crc32c ||
      metadata.md5Hash !== digest.md5 || metadata.metadata?.['rollback-sha256'] !== digest.sha256 || !metadata.generation) {
    throw Object.assign(new Error(), {code: 'remote-checksum-verification-failed'});
  }
}
async function upload(file, name, digest) {
  // Immutable names and ifGenerationMatch=0 prevent clobbering any backup.
  const prior = await request(objectUrl(name));
  if (prior.ok) {
    const metadata = await prior.json(); checkMetadata(metadata, digest); return metadata;
  }
  if (prior.status !== 404) throw Object.assign(new Error(), {code: `object-preflight-http-${prior.status}`});
  await prior.arrayBuffer();
  const metadata = {name, contentType: 'application/octet-stream', crc32c: digest.crc32c,
    metadata: {'rollback-sha256': digest.sha256, 'rollback-baseline': '20261005_pre_growth_094316'}};
  const init = await request(`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o?uploadType=resumable&ifGenerationMatch=0`, {
    method: 'POST', headers: {'Content-Type': 'application/json', 'X-Upload-Content-Type': 'application/octet-stream',
      'X-Upload-Content-Length': String(digest.size)}, body: JSON.stringify(metadata),
  });
  if (!init.ok) throw Object.assign(new Error(), {code: `upload-init-http-${init.status}`});
  const session = init.headers.get('location');
  if (!session || !session.startsWith('https://storage.googleapis.com/')) throw Object.assign(new Error(), {code: 'unexpected-upload-session-host'});
  await init.arrayBuffer();
  const handle = await fs.promises.open(file, 'r');
  let finalMetadata;
  try {
    let offset = 0;
    do {
      const end = Math.min(offset + 8 * 1024 * 1024, digest.size);
      const bytes = Buffer.alloc(end - offset);
      if (bytes.length) {
        const read = await handle.read(bytes, 0, bytes.length, offset);
        if (read.bytesRead !== bytes.length) throw Object.assign(new Error(), {code: 'source-truncated-during-upload'});
      }
      const response = await request(session, {method: 'PUT', headers: {'Content-Type': 'application/octet-stream',
        'Content-Length': String(bytes.length), 'Content-Range': digest.size ? `bytes ${offset}-${end - 1}/${digest.size}` : 'bytes */0'}, body: bytes});
      if (response.status === 308) {
        const received = /bytes=0-(\d+)/.exec(response.headers.get('range') || '');
        await response.arrayBuffer();
        if (!received || Number(received[1]) + 1 !== end) throw Object.assign(new Error(), {code: 'upload-range-verification-failed'});
      } else if (response.ok) {
        finalMetadata = await response.json();
      } else throw Object.assign(new Error(), {code: `upload-chunk-http-${response.status}`});
      offset = end;
    } while (offset < digest.size);
  } finally { await handle.close(); }
  const after = fs.statSync(file);
  if (after.size !== digest.size || after.mtimeMs !== digest.mtimeMs) throw Object.assign(new Error(), {code: 'source-changed-during-upload'});
  if (!finalMetadata) throw Object.assign(new Error(), {code: 'upload-not-finalized'});
  checkMetadata(finalMetadata, digest);
  const readback = await jsonRequest(objectUrl(name) + '?generation=' + finalMetadata.generation);
  checkMetadata(readback, digest);
  return readback;
}
async function main() {
  fs.mkdirSync(destination, {recursive: true, mode: 0o700});
  const opts = {project, ...auth.getGlobalDefaultAccount()};
  await requireAuth(opts);
  token = (await auth.getAccessToken(opts.tokens.refresh_token, opts.authScopes)).access_token;
  stage = 'verify-private-bucket';
  let bucketMetadata = await jsonRequest(`https://storage.googleapis.com/storage/v1/b/${bucket}`);
  const iam = await jsonRequest(`https://storage.googleapis.com/storage/v1/b/${bucket}/iam`);
  if (bucketMetadata.iamConfiguration?.publicAccessPrevention !== 'enforced' ||
      !bucketMetadata.iamConfiguration?.uniformBucketLevelAccess?.enabled || bucketMetadata.location !== 'US-CENTRAL1' ||
      (iam.bindings || []).some(binding => (binding.members || []).some(member => ['allUsers', 'allAuthenticatedUsers'].includes(member)))) {
    throw Object.assign(new Error(), {code: 'bucket-privacy-verification-failed'});
  }
  // Unlocked retention remains administratively reversible. Never lock it.
  // Unique names prevent intentional replacement; versioning and retention also
  // protect against accidental deletion/replacement outside this uploader.
  if (!bucketMetadata.versioning?.enabled || Number(bucketMetadata.retentionPolicy?.retentionPeriod || 0) < 30 * 86400) {
    bucketMetadata = await jsonRequest(`https://storage.googleapis.com/storage/v1/b/${bucket}?ifMetagenerationMatch=${bucketMetadata.metageneration}`, {
      method: 'PATCH', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({versioning: {enabled: true}, retentionPolicy: {
        retentionPeriod: String(Math.max(30 * 86400, Number(bucketMetadata.retentionPolicy?.retentionPeriod || 0))),
      }}),
    });
  }
  const protectedBucket = await jsonRequest(`https://storage.googleapis.com/storage/v1/b/${bucket}`);
  if (!protectedBucket.versioning?.enabled || Number(protectedBucket.retentionPolicy?.retentionPeriod || 0) < 30 * 86400 ||
      protectedBucket.retentionPolicy?.isLocked === true) throw Object.assign(new Error(), {code: 'reversible-retention-verification-failed'});
  save('bucket.json', protectedBucket); save('bucket-iam.json', iam);
  const inputPath = path.join(destination, 'upload-input.json');
  let input;
  if (resume) {
    input = JSON.parse(fs.readFileSync(inputPath));
    if (input.source !== source || input.bucket !== bucket || !/^pre-growth-20261005_094316\/full-local-baseline-/.test(input.prefix)) throw Object.assign(new Error(), {code: 'resume-ownership-mismatch'});
  } else {
    const paths = walk(source).map(file => ({relative: path.relative(source, file).split(path.sep).join('/'), size: fs.statSync(file).size}));
    if (paths.length > 5000 || paths.reduce((n, file) => n + file.size, 0) > 4 * 1024 ** 3) throw Object.assign(new Error(), {code: 'backup-cost-bound-exceeded'});
    input = {source, bucket, prefix: `pre-growth-20261005_094316/full-local-baseline-${new Date().toISOString().replace(/[-:.]/g, '')}`,
      capturedAtUtc: new Date().toISOString(), paths};
    save('upload-input.json', input);
  }
  total = input.paths.length;
  stage = 'upload-verify-immutable-objects';
  const queue = input.paths.slice().sort((a, b) => b.size - a.size);
  const verified = {};
  const workers = Array.from({length: 3}, async () => {
    while (queue.length) {
      const entry = queue.shift();
      const file = path.join(source, ...entry.relative.split('/'));
      const digest = await digestFile(file);
      if (digest.size !== entry.size) throw Object.assign(new Error(), {code: 'frozen-input-size-changed'});
      const object = `${input.prefix}/${entry.relative}`;
      const metadata = await upload(file, object, digest);
      verified[entry.relative] = {...digest, object, generation: metadata.generation, metageneration: metadata.metageneration,
        verifiedAtUtc: new Date().toISOString()};
      completed++;
      save('upload-progress.json', {bucket, prefix: input.prefix, completed, total, files: verified});
      if (completed % 20 === 0 || digest.size > 16 * 1024 * 1024) console.log(JSON.stringify({uploadedAndVerified: completed, total}));
    }
  });
  await Promise.all(workers);
  stage = 'verify-full-remote-inventory';
  const remote = [];
  let pageToken;
  do {
    const query = new URLSearchParams({prefix: input.prefix + '/', maxResults: '1000', ...(pageToken ? {pageToken} : {})});
    const page = await jsonRequest(`https://storage.googleapis.com/storage/v1/b/${bucket}/o?${query}`);
    remote.push(...(page.items || [])); pageToken = page.nextPageToken;
  } while (pageToken);
  if (remote.length !== total) throw Object.assign(new Error(), {code: 'remote-inventory-count-mismatch'});
  for (const entry of Object.values(verified)) {
    const metadata = remote.find(item => item.name === entry.object);
    if (!metadata || metadata.generation !== entry.generation) throw Object.assign(new Error(), {code: 'remote-generation-mismatch'});
    checkMetadata(metadata, entry);
  }
  const manifest = {verified: true, bucket, prefix: input.prefix, source, capturedAtUtc: input.capturedAtUtc,
    completedAtUtc: new Date().toISOString(), fileCount: total, size: input.paths.reduce((n, f) => n + f.size, 0),
    publicAccessPreventionEnforced: true, uniformBucketAccess: true, publicIamBindings: false,
    objectVersioningEnabled: true, retentionPeriodSeconds: Number(protectedBucket.retentionPolicy.retentionPeriod), retentionPolicyLocked: false,
    generationsVerified: true, crc32cVerified: true, md5Verified: true, sha256MetadataVerified: true,
    files: verified};
  save('cloud-upload-manifest.json', manifest);
  const manifestFile = path.join(destination, 'cloud-upload-manifest.json');
  const manifestDigest = await digestFile(manifestFile);
  const manifestObject = `${input.prefix}/cloud-upload-manifest.json`;
  const manifestMetadata = await upload(manifestFile, manifestObject, manifestDigest);
  save('manifest-object.json', {bucket, object: manifestObject, generation: manifestMetadata.generation, ...manifestDigest});
  console.log(JSON.stringify({verified: true, fileCount: total, size: manifest.size, privateManifest: manifestFile,
    manifestObject: `gs://${bucket}/${manifestObject}`, generationsVerified: true, crc32cVerified: true}));
}
main().catch(error => {
  if (fs.existsSync(destination)) save('upload-failure.json', {stage, completed, total, code: String(error.code || 'unknown').slice(0, 60)});
  console.error(JSON.stringify({verified: false, stage, completed, total, code: String(error.code || 'unknown').slice(0, 60)}));
  process.exitCode = 1;
});
