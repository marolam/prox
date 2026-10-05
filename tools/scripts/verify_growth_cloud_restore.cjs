#!/usr/bin/env node
// Restore proof in a newly created, deny-all named database. This script never
// imports into or deletes the production/default database. Only its own unique
// drill database can be cleaned up, after successful verification.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const project = 'prox-42bef';
const baseline = process.argv[2] && path.resolve(process.argv[2]);
const destination = process.argv[3] && path.resolve(process.argv[3]);
if (!baseline || !destination || fs.existsSync(destination) || !process.argv.includes('--execute')) {
  console.error('Usage: node verify_growth_cloud_restore.cjs CLOUD_DATA_MANIFEST NEW_PRIVATE_REPORT_DIRECTORY --execute');
  process.exit(1);
}
const backup = JSON.parse(fs.readFileSync(baseline, 'utf8'));
if (!backup.exportVerified || !backup.exportUri?.startsWith('gs://prox-42bef-rollback-us-central1/pre-growth-') || !backup.exportUri.endsWith('/firestore')) {
  console.error('Refusing an unverified or unexpected export location.');
  process.exit(1);
}
const resumeIndex = process.argv.indexOf('--resume-database');
const resumed = resumeIndex >= 0 ? JSON.parse(fs.readFileSync(path.resolve(process.argv[resumeIndex + 1]), 'utf8')) : null;
const reportIndex = process.argv.indexOf('--resume-report');
const priorReport = reportIndex >= 0 ? path.resolve(process.argv[reportIndex + 1]) : null;
const id = resumed ? resumed.name?.split('/').pop() : 'prox-rollback-drill-20261005-' + Date.now().toString(36);
if (!/^prox-rollback-drill-20261005-[a-z0-9]+$/.test(id) || id === '(default)') throw new Error('Unsafe drill database identifier');
const resource = `projects/${project}/databases/${id}`;
process.env.DEBUG = '';
const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm', 'node_modules', 'firebase-tools', 'lib');
require(path.join(cli, 'logger')).logger.silent = true;
const auth = require(path.join(cli, 'auth'));
const {requireAuth} = require(path.join(cli, 'requireAuth'));
const {Client} = require(path.join(cli, 'apiv2'));
const rules = require(path.join(cli, 'gcp/rules'));
const firestore = new Client({urlPrefix: 'https://firestore.googleapis.com', apiVersion: 'v1'});
const rulesApi = new Client({urlPrefix: 'https://firebaserules.googleapis.com', apiVersion: 'v1'});
const opts = {skipLog: {body: true, resBody: true, queryParams: true}, timeout: 30000};
let stage = 'authentication';
let owned = false;
let ownerUid;
let pollingToken;
const files = {};
const hash = content => crypto.createHash('sha256').update(content).digest('hex');
function save(name, value) {
  const bytes = Buffer.from(JSON.stringify(value, null, 2) + '\n');
  fs.writeFileSync(path.join(destination, name), bytes, {mode: 0o600});
  files[name] = {size: bytes.length, sha256: hash(bytes)};
}
async function waitOperation(operation) {
  let current = operation;
  for (let attempt = 0; attempt < 180; attempt++) {
    if (current.done) {
      if (current.error) throw Object.assign(new Error(), {code: current.error.code, privateDetails: current});
      return current;
    }
    await new Promise(resolve => setTimeout(resolve, 3000));
    try {
      const response = await fetch('https://firestore.googleapis.com/v1/' + operation.name, {
        headers: {Authorization: `Bearer ${pollingToken}`}, signal: AbortSignal.timeout(30000),
      });
      if (!response.ok) throw Object.assign(new Error(), {status: response.status});
      current = await response.json();
    }
    catch (error) {
      if (![429, 500, 502, 503, 504].includes(Number(error.status || error.context?.response?.statusCode))) throw error;
    }
  }
  throw Object.assign(new Error(), {code: 'operation-still-running'});
}
async function requestJson(origin, name, method = 'GET', body) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetch(origin + name, {method, headers: {Authorization: `Bearer ${pollingToken}`, 'Content-Type': 'application/json'},
        ...(body ? {body: JSON.stringify(body)} : {}), signal: AbortSignal.timeout(60000)});
      if (!response.ok) throw Object.assign(new Error(), {status: response.status});
      return await response.json();
    } catch (error) {
      if (attempt === 2 || (error.status && ![429, 500, 502, 503, 504].includes(error.status))) throw error;
    }
  }
}
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])]));
  return value;
}
async function allDocuments(database, readTime) {
  const response = await requestJson('https://firestore.googleapis.com/v1', `/${database}/documents:runQuery`, 'POST', {structuredQuery: {from: [{allDescendants: true}]},
    ...(readTime ? {readTime} : {})});
  const docs = Array.isArray(response) ? response.map(item => item.document).filter(Boolean) : [];
  return docs.map(doc => ({path: doc.name.split('/documents/')[1], sha256: hash(Buffer.from(JSON.stringify(stable(doc.fields || {}))))})).sort((a, b) => a.path.localeCompare(b.path));
}
async function main() {
  fs.mkdirSync(destination, {recursive: true, mode: 0o700});
  await requireAuth({project, ...auth.getGlobalDefaultAccount()});
  const account = auth.getGlobalDefaultAccount();
  pollingToken = (await auth.getAccessToken(account.tokens.refresh_token, [])).access_token;
  stage = 'check-new-database';
  const databases = (await requestJson('https://firestore.googleapis.com/v1', `/projects/${project}/databases`)).databases || [];
  const existing = databases.find(database => database.name === resource);
  if (resumed && (!existing || resumed.name !== resource || existing.uid !== resumed.uid)) throw Object.assign(new Error(), {code: 'resumed-database-ownership-mismatch'});
  if (!resumed && existing) throw Object.assign(new Error(), {code: 'drill-database-already-exists'});
  const productionRelease = await requestJson('https://firebaserules.googleapis.com/v1', `/projects/${project}/releases/cloud.firestore`);
  save('production-rules-before.json', productionRelease);
  stage = 'create-isolated-database';
  if (!resumed) {
    const create = (await firestore.post(`/projects/${project}/databases`, {locationId: 'us-central1', type: 'FIRESTORE_NATIVE',
      databaseEdition: 'STANDARD', deleteProtectionState: 'DELETE_PROTECTION_DISABLED'}, {...opts, queryParams: {databaseId: id}})).body;
    owned = true;
    save('database-create.json', await waitOperation(create));
  } else {
    owned = true;
    save('database-resume.json', {name: resource, uid: resumed.uid});
  }
  const database = await requestJson('https://firestore.googleapis.com/v1', '/' + resource);
  ownerUid = database.uid;
  save('owned-drill-database.json', database);
  stage = 'deny-all-client-access';
  const deny = "rules_version = '2';\nservice cloud.firestore { match /databases/{database}/documents { match /{document=**} { allow read, write: if false; } } }\n";
  const ruleset = await rules.createRuleset(project, [{name: 'firestore.rules', content: deny}], `firestore.googleapis.com/projects/12575732319/databases/${id}`);
  const releaseName = await rules.updateOrCreateRelease(project, ruleset, `cloud.firestore/${id}`);
  const release = await requestJson('https://firebaserules.googleapis.com/v1', '/' + releaseName);
  const deployed = await rules.getRulesetContent(release.rulesetName);
  if (deployed.length !== 1 || deployed[0].content !== deny) throw Object.assign(new Error(), {code: 'deny-all-rules-readback-failed'});
  save('drill-deny-all-rules.json', {release, files: deployed});
  const anonymous = await fetch(`https://firestore.googleapis.com/v1/${resource}/documents/users?pageSize=1`, {signal: AbortSignal.timeout(30000)});
  if (anonymous.status !== 403) throw Object.assign(new Error(), {code: 'anonymous-access-not-denied'});
  save('anonymous-access-check.json', {status: anonymous.status, denied: true});
  stage = 'import-into-owned-drill-only';
  console.log(JSON.stringify({drillDatabase: id, clientAccessDenied: true, importStarted: true}));
  let importCompleted;
  const previousImport = priorReport && path.join(priorReport, 'import-completed.json');
  if (previousImport && fs.existsSync(previousImport)) {
    importCompleted = JSON.parse(fs.readFileSync(previousImport, 'utf8'));
    if (!importCompleted.done || importCompleted.error || !importCompleted.name?.startsWith(resource + '/operations/') || importCompleted.metadata?.inputUriPrefix !== backup.exportUri) {
      throw Object.assign(new Error(), {code: 'unexpected-prior-import'});
    }
  } else {
    const imported = (await firestore.post('/' + resource + ':importDocuments', {inputUriPrefix: backup.exportUri}, opts)).body;
    importCompleted = await waitOperation(imported);
  }
  save('import-completed.json', importCompleted);
  stage = 'verify-restored-content';
  const restored = await allDocuments(resource);
  save('restored-document-fingerprints.json', restored);
  const exportMetadata = JSON.parse(fs.readFileSync(path.join(path.dirname(baseline), 'export-completed.json'), 'utf8'));
  const exportCount = Number(exportMetadata.metadata?.progressDocuments?.completedWork || 0);
  const importCount = Number(importCompleted.metadata?.progressDocuments?.completedWork || 0);
  if (!restored.length || restored.length !== exportCount || (importCount && importCount !== exportCount)) throw Object.assign(new Error(), {code: 'restored-count-does-not-match-export'});
  const live = await allDocuments(`projects/${project}/databases/(default)`, backup.snapshotTime);
  save('source-document-fingerprints.json', live);
  const sourceByPath = new Map(live.map(doc => [doc.path, doc.sha256]));
  const differences = restored.filter(doc => sourceByPath.get(doc.path) !== doc.sha256);
  const exactSnapshotMatch = !!backup.snapshotTime && live.length === restored.length && !differences.length;
  if (backup.snapshotTime && !exactSnapshotMatch) throw Object.assign(new Error(), {code: 'restored-snapshot-content-does-not-match-source'});
  const productionReleaseAfter = await requestJson('https://firebaserules.googleapis.com/v1', `/projects/${project}/releases/cloud.firestore`);
  if (productionReleaseAfter.rulesetName !== productionRelease.rulesetName) throw Object.assign(new Error(), {code: 'production-rules-changed-during-drill'});
  save('production-rules-after.json', productionReleaseAfter);
  stage = 'delete-only-owned-drill-database';
  const ownedDatabase = await requestJson('https://firestore.googleapis.com/v1', '/' + resource);
  if (!owned || !ownerUid || ownedDatabase.uid !== ownerUid || ownedDatabase.name !== resource || !id.startsWith('prox-rollback-drill-20261005-') || resource.endsWith('/(default)')) {
    throw Object.assign(new Error(), {code: 'refusing-database-cleanup-without-exact-ownership'});
  }
  const deleted = await requestJson('https://firestore.googleapis.com/v1', '/' + resource, 'DELETE');
  save('owned-database-delete.json', await waitOperation(deleted));
  const remaining = (await requestJson('https://firestore.googleapis.com/v1', `/projects/${project}/databases`)).databases || [];
  if (remaining.some(database => database.name === resource)) throw Object.assign(new Error(), {code: 'drill-cleanup-readback-failed'});
  const report = {project, drillDatabase: id, checkedAtUtc: new Date().toISOString(), exportUri: backup.exportUri,
    snapshotTime: backup.snapshotTime, expectedExportDocuments: exportCount, importedDocuments: importCount, restoredDocuments: restored.length,
    sourceDocumentsCompared: live.length, changedDocumentsComparedToSource: differences.length, exactSnapshotContentVerified: exactSnapshotMatch,
    denyAllRulesVerified: true, anonymousAccessDeniedVerified: true, productionRulesUnchanged: true,
    ownedDrillDatabaseDeletedVerified: true, productionImportOrDeletionPerformed: false, files};
  save('restore-drill-manifest.json', report);
  console.log(JSON.stringify({...report, files: undefined}));
}
main().catch(error => {
  if (fs.existsSync(destination)) save('failure-private.json', {stage, status: error.status || error.code || 'unknown',
    message: error.message || '', privateDetails: error.privateDetails || error.context || null, ownedDrillDatabase: owned ? resource : null});
  console.error(JSON.stringify({stage, failed: true, status: error.status || error.code || 'unknown', ownedDrillDatabaseRetained: owned ? id : null}));
  process.exitCode = 1;
});
