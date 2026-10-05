#!/usr/bin/env node
// Defaults to read-only inspection. --execute performs ONLY protective backups
// and enables Firestore PITR; it never imports, deletes, changes app documents,
// changes application functions/rules/policy, or grants public access.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const project = 'prox-42bef';
const sourceBucket = 'prox-42bef.firebasestorage.app';
const backupBucket = 'prox-42bef-rollback-us-central1';
const destination = process.argv[2] && path.resolve(process.argv[2]);
const execute = process.argv.includes('--execute');
const exportOnly = process.argv.includes('--export-only');
const resumeIndex = process.argv.indexOf('--resume-operation');
const resumeOperation = resumeIndex >= 0 ? process.argv[resumeIndex + 1] : null;
if (!destination || fs.existsSync(destination)) {
  console.error('Usage: node protect_growth_cloud_data.cjs NEW_PRIVATE_REPORT_DIRECTORY [--execute]');
  process.exit(1);
}
process.env.DEBUG = '';
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm', 'node_modules', 'firebase-tools', 'lib');
require(path.join(cli, 'logger')).logger.silent = true;
const auth = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const storage = new Client({urlPrefix: 'https://storage.googleapis.com', apiVersion: 'storage/v1'});
const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1'});
const monitoring = new Client({urlPrefix: 'https://monitoring.googleapis.com', apiVersion: 'v3'});
const skipLog = {body: true, resBody: true, queryParams: true};
const opts = {skipLog, timeout: 30000};
const files = {};
let stage = 'authentication';
let pollingToken;
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function save(name, value) {
  const bytes = Buffer.from(JSON.stringify(value, null, 2) + '\n');
  fs.writeFileSync(path.join(destination, name), bytes, {mode: 0o600});
  files[name] = {size: bytes.length, sha256: hash(bytes)};
}
async function objects(bucket, prefix) {
  const items = [];
  let pageToken;
  do {
    const response = await storage.get(`/b/${encodeURIComponent(bucket)}/o`, {...opts,
      queryParams: {maxResults: '1000', ...(prefix ? {prefix} : {}), ...(pageToken ? {pageToken} : {})}});
    items.push(...(response.body.items || []));
    pageToken = response.body.nextPageToken;
  } while (pageToken);
  return items;
}
async function waitOperation(operation) {
  let current = operation;
  for (let attempt = 0; attempt < 180; attempt++) {
    if (current.done) {
      if (current.error) throw Object.assign(new Error(), {code: current.error.code, privateDetails: current});
      return current;
    }
    save('operation-progress.json', current);
    await new Promise(resolve => setTimeout(resolve, 3000));
    try {
      // Native fetch avoids a CLI transport keep-alive failure seen when polling
      // Firestore long-running operation URLs. OAuth remains entirely in memory.
      const response = await fetch('https://firestore.googleapis.com/v1/' + operation.name, {
        headers: {Authorization: `Bearer ${pollingToken}`}, signal: AbortSignal.timeout(30000),
      });
      if (!response.ok) throw Object.assign(new Error(), {status: response.status});
      current = await response.json();
    } catch (error) {
      const status = error.status || error.context?.response?.statusCode;
      if (![429, 500, 502, 503, 504].includes(Number(status))) throw error;
      // A transient polling failure does not mean the long-running job failed.
    }
  }
  throw Object.assign(new Error(), {code: 'operation-still-running', privateDetails: current});
}
async function main() {
  fs.mkdirSync(destination, {recursive: true, mode: 0o700});
  await requireAuth({project, ...auth.getGlobalDefaultAccount()});
  const account = auth.getGlobalDefaultAccount();
  pollingToken = (await auth.getAccessToken(account.tokens.refresh_token, [])).access_token;
  stage = 'inspect-database-size-and-storage';
  const dbName = `/projects/${project}/databases/(default)`;
  const database = (await firestore.get(dbName, opts)).body;
  save('database-before.json', database);
  const sourceMetadata = (await storage.get(`/b/${encodeURIComponent(sourceBucket)}`, opts)).body;
  save('source-bucket.json', sourceMetadata);
  const originalObjects = await objects(sourceBucket);
  save('storage-before.json', originalObjects);
  const storageBytes = originalObjects.reduce((sum, object) => sum + Number(object.size || 0), 0);
  let databaseBytes = null;
  try {
    const metrics = (await monitoring.get(`/projects/${project}/timeSeries`, {...opts, queryParams: {
      filter: 'metric.type="firestore.googleapis.com/storage/data_and_index_storage_bytes"',
      'interval.startTime': new Date(Date.now() - 24 * 3600000).toISOString(),
      'interval.endTime': new Date().toISOString(),
      'aggregation.alignmentPeriod': '3600s', 'aggregation.perSeriesAligner': 'ALIGN_MAX',
    }})).body;
    save('database-storage-metric.json', metrics);
    const series = (metrics.timeSeries || []).filter(item => !item.resource?.labels?.database_id || item.resource.labels.database_id === '(default)');
    const values = series.flatMap(item => (item.points || []).map(point => Number(point.value?.int64Value ?? point.value?.doubleValue ?? 0)));
    if (values.length) databaseBytes = Math.max(...values);
  } catch (error) {
    save('database-storage-metric-error.json', {status: error.status || error.code || 'unknown'});
  }
  const inspection = {project, databaseRegion: database.locationId, databaseBytes, storageObjectCount: originalObjects.length,
    storageBytes, storageRegion: sourceMetadata.location, execute, backupBucket,
    inspectedAtUtc: new Date().toISOString()};
  save('inspection.json', inspection);
  console.log(JSON.stringify(inspection));
  if (!execute) return;
  // Hard bounds stop an unexpectedly large copy before any protective mutation.
  if (database.locationId !== 'us-central1' || databaseBytes === null || databaseBytes > 10 * 1024 ** 3 || storageBytes > 10 * 1024 ** 3 || originalObjects.length > 20000) {
    throw Object.assign(new Error(), {code: 'cost-or-region-bound-requires-review'});
  }
  stage = 'prepare-private-bucket';
  let bucket;
  try {
    bucket = (await storage.get(`/b/${backupBucket}`, opts)).body;
  } catch (error) {
    if (error.status !== 404 && error.context?.response?.statusCode !== 404) throw error;
    bucket = (await storage.post('/b', {name: backupBucket, location: 'US-CENTRAL1', storageClass: 'STANDARD',
      iamConfiguration: {uniformBucketLevelAccess: {enabled: true}, publicAccessPrevention: 'enforced'},
      labels: {purpose: 'prox-rollback', checkpoint: 'pre-growth-20261005'}}, {...opts, queryParams: {project}})).body;
  }
  if (String(bucket.location).toUpperCase() !== 'US-CENTRAL1' || !bucket.iamConfiguration?.uniformBucketLevelAccess?.enabled || bucket.iamConfiguration?.publicAccessPrevention !== 'enforced') {
    throw Object.assign(new Error(), {code: 'backup-bucket-must-be-private-uniform-same-region'});
  }
  const iam = (await storage.get(`/b/${backupBucket}/iam`, opts)).body;
  if ((iam.bindings || []).some(binding => (binding.members || []).some(member => ['allUsers', 'allAuthenticatedUsers'].includes(member)))) {
    throw Object.assign(new Error(), {code: 'unexpected-public-bucket-binding'});
  }
  save('backup-bucket.json', bucket);
  save('backup-bucket-iam.json', iam);
  stage = 'enable-pitr';
  if (database.pointInTimeRecoveryEnablement !== 'POINT_IN_TIME_RECOVERY_ENABLED') {
    const operation = (await firestore.patch(dbName, {name: database.name, pointInTimeRecoveryEnablement: 'POINT_IN_TIME_RECOVERY_ENABLED'},
      {...opts, queryParams: {updateMask: 'pointInTimeRecoveryEnablement'}})).body;
    save('pitr-enable-operation.json', operation);
    if (operation.name && !operation.name.includes('/databases/(default)/operations/')) throw Object.assign(new Error(), {code: 'unexpected-pitr-operation'});
    if (operation.name) save('pitr-enable-completed.json', await waitOperation(operation));
  }
  const protectedDatabase = (await firestore.get(dbName, opts)).body;
  save('database-after-pitr.json', protectedDatabase);
  if (protectedDatabase.pointInTimeRecoveryEnablement !== 'POINT_IN_TIME_RECOVERY_ENABLED') throw Object.assign(new Error(), {code: 'pitr-readback-failed'});
  const checkpoint = 'pre-growth-' + new Date().toISOString().replace(/[-:.]/g, '').replace('Z', '');
  const exportPrefix = `${checkpoint}/firestore`;
  stage = 'start-firestore-export';
  let exportOperation;
  let snapshotTime = null;
  if (resumeOperation) {
    exportOperation = JSON.parse(fs.readFileSync(path.resolve(resumeOperation), 'utf8'));
    if (!exportOperation.name?.startsWith(`projects/${project}/databases/(default)/operations/`)) throw Object.assign(new Error(), {code: 'unexpected-resumed-operation'});
    snapshotTime = exportOperation.metadata?.snapshotTime || null;
  } else {
    const candidate = new Date(Math.floor((Date.now() - 60000) / 60000) * 60000);
    if (candidate.getTime() < Date.parse(protectedDatabase.earliestVersionTime)) throw Object.assign(new Error(), {code: 'pitr-snapshot-time-not-yet-available'});
    snapshotTime = candidate.toISOString();
    exportOperation = (await firestore.post(dbName + ':exportDocuments', {outputUriPrefix: `gs://${backupBucket}/${exportPrefix}`, snapshotTime}, opts)).body;
  }
  save('export-started.json', exportOperation);
  console.log(JSON.stringify({exportStarted: true, operation: exportOperation.name, backupBucket, prefix: exportPrefix}));
  stage = 'wait-firestore-export';
  const completed = await waitOperation(exportOperation);
  save('export-completed.json', completed);
  const actualExportUri = completed.response?.outputUriPrefix || exportOperation.metadata?.outputUriPrefix || `gs://${backupBucket}/${exportPrefix}`;
  const actualPrefix = actualExportUri.replace(`gs://${backupBucket}/`, '').replace(/\/$/, '');
  if (actualExportUri === actualPrefix) throw Object.assign(new Error(), {code: 'unexpected-export-bucket'});
  const exportObjects = await objects(backupBucket, actualPrefix + '/');
  save('export-objects.json', exportObjects);
  if (!exportObjects.length || !exportObjects.some(item => item.name.endsWith('.overall_export_metadata'))) throw Object.assign(new Error(), {code: 'missing-export-metadata'});
  if (exportObjects.some(item => !item.crc32c || !item.generation || !item.size)) throw Object.assign(new Error(), {code: 'missing-export-object-checksum'});
  stage = 'copy-app-storage';
  const copies = [];
  for (const object of exportOnly ? [] : originalObjects) {
    const name = `${checkpoint}/storage/${sourceBucket}/${object.name}`;
    let rewriteToken;
    let copy;
    do {
      copy = (await storage.post(`/b/${encodeURIComponent(sourceBucket)}/o/${encodeURIComponent(object.name)}/rewriteTo/b/${backupBucket}/o/${encodeURIComponent(name)}`,
        {metadata: {proxRollbackSourceGeneration: object.generation}}, {...opts, queryParams: {
          sourceGeneration: object.generation, ifSourceGenerationMatch: object.generation, ifGenerationMatch: '0', ...(rewriteToken ? {rewriteToken} : {}),
        }})).body;
      rewriteToken = copy.rewriteToken;
    } while (!copy.done);
    if (copy.resource?.crc32c !== object.crc32c || copy.resource?.size !== object.size || (object.md5Hash && copy.resource?.md5Hash !== object.md5Hash)) {
      throw Object.assign(new Error(), {code: 'storage-copy-integrity-mismatch'});
    }
    copies.push({source: {name: object.name, generation: object.generation, size: object.size, crc32c: object.crc32c, md5Hash: object.md5Hash},
      backup: {name: copy.resource.name, generation: copy.resource.generation, size: copy.resource.size, crc32c: copy.resource.crc32c, md5Hash: copy.resource.md5Hash}});
  }
  save('storage-copies.json', copies);
  const finalObjects = await objects(sourceBucket);
  save('storage-after.json', finalObjects);
  const changed = originalObjects.filter(item => !finalObjects.some(current => current.name === item.name && current.generation === item.generation));
  const summary = {...inspection, executedAtUtc: new Date().toISOString(), backupBucketPrivateVerified: true,
    pointInTimeRecoveryEnabledVerified: true, versionRetentionPeriod: protectedDatabase.versionRetentionPeriod,
    earliestVersionTime: protectedDatabase.earliestVersionTime,
    exportVerified: true, exportOperation: completed.name, exportUri: actualExportUri, snapshotTime,
    exportObjectCount: exportObjects.length, exportBytes: exportObjects.reduce((sum, object) => sum + Number(object.size || 0), 0),
    storageObjectsCopiedAndChecksumVerified: copies.length, originalStorageObjectsChangedDuringCapture: changed.length,
    storageCopySkipped: exportOnly,
    productionRestorePerformed: false, files};
  save('cloud-data-manifest.json', summary);
  console.log(JSON.stringify({...summary, files: undefined}));
}
main().catch(error => {
  const report = {stage, failed: true, status: error.status || error.context?.response?.statusCode || error.code || 'unknown',
    message: error.message || '', privateDetails: error.privateDetails || error.context || null};
  if (fs.existsSync(destination)) save('failure-private.json', report);
  // Raw API messages are only preserved privately, never emitted to the console.
  console.error(JSON.stringify({stage, failed: true, status: report.status}));
  process.exitCode = 1;
});
