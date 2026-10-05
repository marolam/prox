#!/usr/bin/env node
// Read-only production capture. Never deploys, changes policy, reads Secret
// Manager payloads, or writes application data. The gen1 generateDownloadUrl
// POST only issues a download link for an existing immutable function version.
// Output files may contain private
// runtime configuration; store them beside the private rollback archive.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const project = process.argv[2];
const destination = process.argv[3] && path.resolve(process.argv[3]);
if (project !== 'prox-42bef' || !destination) {
  console.error('Usage: node capture_growth_backend_rollback.cjs prox-42bef NEW_PRIVATE_OUTPUT_DIRECTORY');
  process.exit(1);
}
if (fs.existsSync(destination)) {
  console.error('Refusing to overwrite an existing backend baseline directory.');
  process.exit(1);
}

process.env.DEBUG = '';
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm', 'node_modules', 'firebase-tools', 'lib');
const {logger} = require(path.join(cli, 'logger'));
logger.silent = true;
const auth = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const rules = require(path.join(cli, 'gcp/rules'));
const remoteconfig = require(path.join(cli, 'remoteconfig/get'));
const functionsV1 = require(path.join(cli, 'gcp/cloudfunctions'));
const functionsV2 = require(path.join(cli, 'gcp/cloudfunctionsv2'));
const {FirestoreApi} = require(path.join(cli, 'firestore/api'));
const firestoreApi = new FirestoreApi();
const files = {};
const checks = {};
const hash = content => crypto.createHash('sha256').update(content).digest('hex');
function save(name, value) {
  const content = Buffer.isBuffer(value) ? value : Buffer.from(JSON.stringify(value, null, 2) + '\n');
  fs.mkdirSync(path.dirname(path.join(destination, name)), {recursive: true});
  fs.writeFileSync(path.join(destination, name), content, {mode: 0o600});
  files[name] = {size: content.length, sha256: hash(content)};
}
function errorCode(error) {
  return String(error.status || error.statusCode || error.context?.response?.statusCode || error.code || 'unknown').slice(0, 40);
}
async function capture(name, callback) {
  try {
    const value = await callback();
    save(name + '.json', value);
    checks[name] = {captured: true};
    return value;
  } catch (error) {
    checks[name] = {captured: false, errorCode: errorCode(error)};
    return null;
  }
}

async function downloadSource(source, token) {
  if (!source?.bucket || !source?.object) throw Object.assign(new Error(), {code: 'no-source-reference'});
  const url = new URL(`https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(source.bucket)}/o/${encodeURIComponent(source.object)}`);
  url.searchParams.set('alt', 'media');
  if (source.generation) url.searchParams.set('generation', String(source.generation));
  const response = await fetch(url, {headers: {Authorization: `Bearer ${token}`}, signal: AbortSignal.timeout(60000)});
  if (!response.ok) throw Object.assign(new Error(), {status: response.status});
  return Buffer.from(await response.arrayBuffer());
}

async function main() {
  fs.mkdirSync(destination, {recursive: true, mode: 0o700});
  const options = {project, ...auth.getGlobalDefaultAccount()};
  await requireAuth(options);
  const accountToken = await auth.getAccessToken(options.tokens.refresh_token, options.authScopes);
  const token = accountToken.access_token;
  const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1'});
  const functions = new Client({urlPrefix: 'https://cloudfunctions.googleapis.com', apiVersion: 'v1'});
  const skipLog = {body: true, resBody: true, queryParams: true};
  const [releases, config, v1, v2, database] = await Promise.all([
    capture('rules-releases', () => rules.listAllReleases(project)),
    capture('remote-config', () => remoteconfig.getTemplate(project)),
    capture('functions-v1', () => functionsV1.listAllFunctions(project)),
    capture('functions-v2', () => functionsV2.listAllFunctions(project)),
    capture('firestore-database', () => firestoreApi.getDatabase(project, '(default)')),
    capture('firestore-indexes', () => firestoreApi.listIndexes(project)),
    capture('firestore-field-overrides', () => firestoreApi.listFieldOverrides(project)),
    capture('firestore-backup-schedules', async () => (await firestore.get(`/projects/${project}/databases/(default)/backupSchedules`, {skipLog, timeout: 30000})).body),
  ]);
  if (database?.locationId) {
    await capture('firestore-backups', async () => (await firestore.get(`/projects/${project}/locations/${database.locationId}/backups`, {skipLog, timeout: 30000})).body);
  }
  for (const release of releases || []) {
    if (!release.name?.includes('/releases/cloud.firestore') && !release.name?.includes('/releases/firebase.storage')) continue;
    const name = release.name.slice(release.name.lastIndexOf('/') + 1).replace(/[^a-zA-Z0-9_.-]/g, '_');
    await capture(`rules-${name}`, async () => ({release, files: await rules.getRulesetContent(release.rulesetName)}));
  }
  const allFunctions = [...(v1?.functions || []), ...(v2?.functions || [])];
  const sourceInventory = [];
  const downloaded = new Map();
  for (const fn of allFunctions) {
    let source = fn.buildConfig?.sourceProvenance?.resolvedStorageSource || fn.buildConfig?.source?.storageSource;
    if (!source && fn.sourceArchiveUrl?.startsWith('gs://')) {
      const parts = fn.sourceArchiveUrl.slice(5).split('/');
      source = {bucket: parts.shift(), object: parts.join('/')};
    }
    if (!source && fn.versionId) {
      try {
        const result = await functions.post(`/${fn.name}:generateDownloadUrl`, {versionId: fn.versionId}, {skipLog, timeout: 30000});
        const response = await fetch(result.body.downloadUrl, {signal: AbortSignal.timeout(60000)});
        if (!response.ok) throw Object.assign(new Error(), {status: response.status});
        const content = Buffer.from(await response.arrayBuffer());
        const name = `function-sources/${hash(Buffer.from(fn.name + ':' + fn.versionId)).slice(0, 20)}.zip`;
        save(name, content);
        sourceInventory.push({function: fn.name, versionId: fn.versionId, captured: true, file: name, sha256: hash(content), size: content.length});
      } catch (error) {
        sourceInventory.push({function: fn.name, versionId: fn.versionId, captured: false, errorCode: errorCode(error)});
      }
      continue;
    }
    const key = source ? JSON.stringify(source) : null;
    let entry = key && downloaded.get(key);
    if (!entry) {
      entry = {source: source || null, captured: false};
      if (key) {
        try {
          const content = await downloadSource(source, token);
          const name = `function-sources/${hash(Buffer.from(key)).slice(0, 20)}.zip`;
          save(name, content);
          entry = {source, captured: true, file: name, sha256: hash(content), size: content.length};
        } catch (error) {
          entry.errorCode = errorCode(error);
        }
        downloaded.set(key, entry);
      } else {
        entry.errorCode = 'no-source-reference';
      }
    }
    sourceInventory.push({function: fn.name, ...entry});
  }
  const functionsV2Client = new Client({urlPrefix: 'https://cloudfunctions.googleapis.com', apiVersion: 'v2'});
  await Promise.all(allFunctions.map(async fn => {
    const name = fn.name.split('/').pop();
    await capture(`function-iam/${name}`, async () => (await (fn.versionId ? functions : functionsV2Client).get(`/${fn.name}:getIamPolicy`, {skipLog, timeout: 30000})).body);
  }));
  save('function-source-inventory.json', sourceInventory);
  const summary = {
    project, capturedAtUtc: new Date().toISOString(), checks,
    functionCount: allFunctions.length,
    functionsWithSourceArchive: sourceInventory.filter(item => item.captured).length,
    distinctSourceArchives: new Set(sourceInventory.filter(item => item.captured).map(item => item.file)).size,
    remoteConfigVersion: config?.version?.versionNumber || null,
    pointInTimeRecovery: database?.pointInTimeRecoveryEnablement || null,
    dataExportCaptured: false,
    secretPayloadsRead: false,
    deploymentPerformed: false,
    productionRestoreDrillPerformed: false,
    files,
  };
  save('backend-manifest.json', summary);
  console.log(JSON.stringify({...summary, files: undefined}));
}

main().catch(error => {
  console.error(JSON.stringify({captured: false, errorCode: errorCode(error), deploymentPerformed: false}));
  process.exitCode = 1;
});
