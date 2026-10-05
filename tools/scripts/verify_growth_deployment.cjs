#!/usr/bin/env node
'use strict';
// Read-only release verification. Application/control-plane requests are GETs.
// OAuth renewal is delegated to the installed Firebase CLI. Neither tokens,
// environment values, rule bodies, API bodies, nor personal data are printed.
// Keep the proof directory private; it contains operational names and hashes.
process.env.DEBUG = '';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const SELECTED = Object.freeze([
  'getGrowthStatus', 'joinTesterCohort', 'createGrowthInvite', 'acceptGrowthReferral',
  'syncGrowthProgress', 'recordGrowthSession', 'submitGrowthSupport', 'replyToSupportTicket',
  'updateSupportTicket', 'getGrowthOps', 'reviewGrowthReward', 'reviewTesterApplication',
  'updateGrowthConfig', 'onGrowthAuthCreate', 'onGrowthProfile', 'onGrowthChatMessage',
  'onGrowthMeetupReceipt', 'recomputeGrowthDailyMetrics', 'onLegacyFeedbackSupport',
  'onLegacyBugReportSupport', 'onLegacySupportTicket', 'backfillLegacySupport',
  'createReferralSingleUseToken', 'referralApkDownload', 'finalizeReferralSingleUseToken',
  'deleteMyAccount', 'onAuthDelete', 'claimVerifiedReward', 'linkReferralCode',
  'onBackgroundPresence', 'onBackgroundMatchAlert', 'getBackgroundOpportunity',
  'listBackgroundOpportunities', 'onMeetupCompletedAccounting', 'syncCompletedMeetup',
  'onBusinessAutomationWritten', 'runBusinessFollowupAutomation', 'configureBusinessAutomation',
  'recomputeDashboardMetrics', 'setBusinessModeActive', 'onMeetupStatusNotification',
  'onPartyNetworkInsightRequest', 'onKeywordReportCreated',
]);
const CALLABLES = new Set([
  'getGrowthStatus', 'joinTesterCohort', 'createGrowthInvite', 'acceptGrowthReferral',
  'syncGrowthProgress', 'recordGrowthSession', 'submitGrowthSupport', 'replyToSupportTicket',
  'updateSupportTicket', 'getGrowthOps', 'reviewGrowthReward', 'reviewTesterApplication',
  'updateGrowthConfig', 'backfillLegacySupport', 'deleteMyAccount', 'claimVerifiedReward',
  'linkReferralCode', 'getBackgroundOpportunity', 'listBackgroundOpportunities',
  'configureBusinessAutomation', 'setBusinessModeActive',
]);
const PUBLIC_HTTP = new Set([...CALLABLES, 'createReferralSingleUseToken',
  'referralApkDownload', 'finalizeReferralSingleUseToken']);
const PROJECT = 'prox-42bef';
const BUCKET = 'prox-42bef.firebasestorage.app';
const ROOT = path.resolve(__dirname, '../..');
const BASELINE = path.join(ROOT, 'artifacts/rollback/20261005_pre_growth_094316/backend');
const ORIGINS = Object.freeze({
  functions: 'https://cloudfunctions.googleapis.com',
  run: 'https://run.googleapis.com',
  firestore: 'https://firestore.googleapis.com',
  rules: 'https://firebaserules.googleapis.com',
  remoteConfig: 'https://firebaseremoteconfig.googleapis.com',
});
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])]));
  }
  return value;
}
const fingerprint = value => hash(JSON.stringify(stable(value)));
function additionalTargets(value) {
  const entries = Array.isArray(value) ? value : value?.functions;
  if (!Array.isArray(entries) || entries.length > 50) {
    throw Object.assign(new Error(), {code: 'invalid-additional-targets'});
  }
  return entries.map(entry => {
    const result = typeof entry === 'string' ? {name: entry} : entry;
    if (!result || typeof result !== 'object' || typeof result.name !== 'string' ||
        !/^[A-Za-z_][A-Za-z0-9_]{0,62}$/.test(result.name || '') ||
        (result.callable !== undefined && typeof result.callable !== 'boolean') ||
        (result.publicEndpoint !== undefined && typeof result.publicEndpoint !== 'boolean')) {
      throw Object.assign(new Error(), {code: 'invalid-additional-target'});
    }
    return {name: result.name, ...(result.callable !== undefined ? {callable: result.callable} : {}),
      ...(result.publicEndpoint !== undefined ? {publicEndpoint: result.publicEndpoint} : {})};
  });
}
const errorCode = error => String(error?.status || error?.statusCode ||
  error?.context?.response?.statusCode || error?.code || 'unknown').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 60);
function semanticTemplate(template) {
  const result = {...template};
  // version is API publication metadata, including publishing identity/time;
  // every other field, value, condition, and condition order is compared.
  delete result.version;
  return result;
}
function groupOf(name) {
  return name?.split('/collectionGroups/')[1]?.split('/')[0] || '';
}
function compositeSpec(index) {
  const fields = (index.fields || []).map(field => ({...field}));
  // Firestore appends this tie breaker to declarations that omit it.
  const last = fields[fields.length - 1];
  if (last?.fieldPath === '__name__' && fields.length > 1) {
    const preceding = [...fields.slice(0, -1)].reverse().find(field => field.order);
    if (last.order === (preceding?.order || 'ASCENDING')) fields.pop();
  }
  return {collectionGroup: index.collectionGroup || groupOf(index.name),
    queryScope: index.queryScope || 'COLLECTION', fields,
    ...(index.apiScope && index.apiScope !== 'ANY_API' ? {apiScope: index.apiScope} : {}),
    ...(index.density && index.density !== 'SPARSE_ALL' ? {density: index.density} : {}),
    ...(index.multikey === true ? {multikey: true} : {}),
    ...(index.unique === true ? {unique: true} : {})};
}
function fieldIndexSpec(index) {
  const field = index.fields?.[0] || index;
  return {queryScope: index.queryScope || 'COLLECTION',
    ...(field.order ? {order: field.order} : {}),
    ...(field.arrayConfig ? {arrayConfig: field.arrayConfig} : {}),
    ...(index.apiScope && index.apiScope !== 'ANY_API' ? {apiScope: index.apiScope} : {}),
    ...(index.density && index.density !== 'SPARSE_ALL' ? {density: index.density} : {}),
    ...(index.multikey === true ? {multikey: true} : {}),
    ...(index.unique === true ? {unique: true} : {})};
}
function functionConfig(fn) {
  // Preserve source/build/runtime/environment/IAM-relevant configuration while
  // avoiding comparisons of API observation and create/update timestamps.
  return Object.fromEntries(['buildConfig', 'serviceConfig', 'labels', 'environment',
    'entryPoint', 'runtime', 'httpsTrigger', 'eventTrigger', 'environmentVariables',
    'sourceArchiveUrl', 'sourceRepository', 'versionId', 'availableMemoryMb',
    'timeout', 'serviceAccountEmail', 'vpcConnector', 'vpcConnectorEgressSettings',
    'ingressSettings', 'minInstances', 'maxInstances'].filter(key => fn[key] !== undefined)
    .map(key => [key, fn[key]]));
}
function hasPublicInvoker(policy, role) {
  return (policy?.bindings || []).some(binding => binding.role === role &&
    !binding.condition && (binding.members || []).includes('allUsers'));
}
function policyProof(policy, role) {
  return {public: hasPublicInvoker(policy, role), policySha256: fingerprint(policy),
    invokerRole: role, bindingCount: (policy?.bindings || []).length};
}
function decodeValue(value) {
  if (!value || typeof value !== 'object') return undefined;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('stringValue' in value) return value.stringValue;
  if ('timestampValue' in value) return value.timestampValue;
  return undefined;
}

async function verify(argv = process.argv.slice(2)) {
  const [project, output, ...args] = argv;
  const allowed = new Set(['--preflight', '--dashboard-after', '--max-dashboard-age-minutes', '--additional-targets']);
  let preflight = false;
  let dashboardAfter;
  let maxAgeMinutes = 30;
  let additionalManifest;
  for (let index = 0; index < args.length; index++) {
    const flag = args[index];
    if (!allowed.has(flag)) throw Object.assign(new Error(), {code: 'invalid-arguments'});
    if (flag === '--preflight') preflight = true;
    if (flag === '--dashboard-after') {
      dashboardAfter = Date.parse(args[++index]);
      if (!Number.isFinite(dashboardAfter)) throw Object.assign(new Error(), {code: 'invalid-dashboard-time'});
    }
    if (flag === '--max-dashboard-age-minutes') {
      maxAgeMinutes = Number(args[++index]);
      if (!Number.isFinite(maxAgeMinutes) || maxAgeMinutes < 1 || maxAgeMinutes > 120) {
        throw Object.assign(new Error(), {code: 'invalid-dashboard-age'});
      }
    }
    if (flag === '--additional-targets') {
      if (!args[index + 1]) throw Object.assign(new Error(), {code: 'missing-target-manifest'});
      additionalManifest = path.resolve(args[++index]);
    }
  }
  if (project !== PROJECT || !output) throw Object.assign(new Error(), {code: 'invalid-arguments'});
  const destination = path.resolve(output);
  if (fs.existsSync(destination)) throw Object.assign(new Error(), {code: 'evidence-directory-exists'});
  if (SELECTED.length !== 43 || new Set(SELECTED).size !== 43) throw Object.assign(new Error(), {code: 'invalid-target-list'});
  // Additive, explicit release manifests keep unrelated dormant exports out of
  // verification. Strings infer HTTP/callable classification from deployed
  // trigger metadata; descriptors can require it even if a target is missing.
  const extra = additionalManifest
    ? additionalTargets(JSON.parse(fs.readFileSync(additionalManifest, 'utf8'))) : [];
  const selected = [...SELECTED, ...extra.map(item => item.name)];
  if (new Set(selected).size !== selected.length) throw Object.assign(new Error(), {code: 'duplicate-target'});
  const callables = new Set([...CALLABLES, ...extra.filter(item => item.callable).map(item => item.name)]);
  const publicHttp = new Set([...PUBLIC_HTTP, ...extra.filter(item => item.callable || item.publicEndpoint).map(item => item.name)]);
  const extrasByName = new Map(extra.map(item => [item.name, item]));
  const baselineConfig = JSON.parse(fs.readFileSync(path.join(BASELINE, 'remote-config.json'), 'utf8'));
  const declaredIndexes = JSON.parse(fs.readFileSync(path.join(ROOT, 'firestore.indexes.json'), 'utf8'));
  const startedAt = new Date().toISOString();
  const proof = {schemaVersion: 1, project, mode: preflight ? 'preflight' : 'full', startedAtUtc: startedAt,
    readOnly: true, applicationRequestsMethod: 'GET', secretPayloadsRead: false, deploymentPerformed: false,
    targetsSha256: fingerprint(selected), expectedSelectedFunctions: selected.length,
    additionalTargetsCount: extra.length, checks: {}};
  fs.mkdirSync(destination, {recursive: true, mode: 0o700});
  let token;
  let requestCount = 0;
  async function get(origin, resource, optional = false) {
    if (!Object.values(ORIGINS).includes(origin) || !resource.startsWith('/')) {
      throw Object.assign(new Error(), {code: 'unexpected-api-path'});
    }
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        requestCount++;
        const response = await fetch(origin + resource, {method: 'GET',
          headers: {Authorization: `Bearer ${token}`, Accept: 'application/json'},
          signal: AbortSignal.timeout(45000)});
        if (optional && response.status === 404) return null;
        if (!response.ok) throw Object.assign(new Error(), {status: response.status});
        return await response.json();
      } catch (error) {
        if (attempt === 2 || (error.status && ![429, 500, 502, 503, 504].includes(error.status))) throw error;
      }
    }
  }
  async function list(origin, resource, key, query = {}) {
    const result = [];
    const unreachable = new Set();
    let pageToken;
    do {
      // The cross-collection Firestore listing rejects explicit pageSize;
      // use its API default and still follow every returned page token.
      const params = new URLSearchParams({...query,
        ...(origin === ORIGINS.firestore ? {} : {pageSize: '100'}),
        ...(pageToken ? {pageToken} : {})});
      const suffix = params.toString();
      const response = await get(origin, resource + (suffix ? '?' + suffix : ''));
      result.push(...(response[key] || []));
      for (const region of response.unreachable || []) unreachable.add(region);
      pageToken = response.nextPageToken;
    } while (pageToken);
    return {items: result, unreachable: [...unreachable].sort()};
  }
  async function check(name, callback) {
    try {
      proof.checks[name] = await callback();
    } catch (error) {
      proof.checks[name] = {passed: false, errorCode: errorCode(error)};
    }
  }
  function finish() {
    proof.finishedAtUtc = new Date().toISOString();
    proof.apiGetRequestCount = requestCount;
    proof.passed = Object.values(proof.checks).every(check => check.passed || check.skipped);
    const bytes = Buffer.from(JSON.stringify(stable(proof), null, 2) + '\n');
    fs.writeFileSync(path.join(destination, 'deployment-verification.json'), bytes, {mode: 0o600, flag: 'wx'});
    const summary = {mode: proof.mode, status: proof.passed ? 'PASS' : 'FAIL',
      checks: Object.fromEntries(Object.entries(proof.checks).map(([name, value]) =>
        [name, value.skipped ? 'SKIPPED' : value.passed ? 'PASS' : 'FAIL'])),
      functions: proof.checks.functions?.activeSelectedCount ?? null,
      publicEndpoints: proof.checks.functions?.publicEndpointsCount ?? null,
      indexesReady: proof.checks.indexes?.readyCount ?? null,
      declaredIndexes: (declaredIndexes.indexes || []).length,
      ttlsActive: proof.checks.fieldOverrides?.activeTtlCount ?? null,
      declaredTtls: (declaredIndexes.fieldOverrides || []).filter(field => field.ttl).length,
      apiGetRequestCount: requestCount, proofSha256: hash(bytes)};
    console.log(JSON.stringify(summary));
    process.exitCode = proof.passed ? 0 : 1;
    return proof;
  }
  try {
    const cli = process.env.FIREBASE_TOOLS_LIB || path.join(process.env.APPDATA || '', 'npm', 'node_modules', 'firebase-tools', 'lib');
    require(path.join(cli, 'logger')).logger.silent = true;
    const auth = require(path.join(cli, 'auth'));
    const {requireAuth} = require(path.join(cli, 'requireAuth'));
    const options = {project, ...auth.getGlobalDefaultAccount()};
    await requireAuth(options);
    token = (await auth.getAccessToken(options.tokens.refresh_token, options.authScopes)).access_token;
    if (!token) throw Object.assign(new Error(), {code: 'missing-access-token'});
  } catch (error) {
    proof.checks.authentication = {passed: false, errorCode: errorCode(error)};
    return finish();
  }

  await Promise.all([
    ...[['firestoreRules', 'cloud.firestore', 'firestore.rules'],
      ['storageRules', `firebase.storage/${BUCKET}`, 'storage.rules']].map(([name, releaseId, file]) => check(name, async () => {
      const release = await get(ORIGINS.rules, `/v1/projects/${project}/releases/${releaseId}`);
      const ruleset = await get(ORIGINS.rules, `/v1/${release.rulesetName}`);
      const files = ruleset.source?.files || [];
      const source = files.length === 1 ? files[0]?.content : undefined;
      const expected = fs.readFileSync(path.join(ROOT, file), 'utf8');
      return {passed: source === expected, release: release.name, ruleset: release.rulesetName,
        releaseUpdatedAt: release.updateTime || null, sourceFileCount: files.length,
        expectedSha256: hash(expected), activeSha256: typeof source === 'string' ? hash(source) : null,
        exactSourceMatch: source === expected,
        equivalentLineEndingsOnly: typeof source === 'string' && source !== expected &&
          source.replace(/\r\n/g, '\n') === expected.replace(/\r\n/g, '\n')};
    })),
    check('remoteConfig', async () => {
      const live = await get(ORIGINS.remoteConfig, `/v1/projects/${project}/remoteConfig`);
      const expectedSha256 = fingerprint(semanticTemplate(baselineConfig));
      const actualSha256 = fingerprint(semanticTemplate(live));
      return {passed: expectedSha256 === actualSha256, entireSemanticTemplateCompared: true,
        excludedMetadataFields: ['version'], baselineRelativeFile: path.relative(ROOT, path.join(BASELINE, 'remote-config.json')),
        expectedSha256, actualSha256, parameterCount: Object.keys(live.parameters || {}).length,
        parameterGroupCount: Object.keys(live.parameterGroups || {}).length,
        conditionCount: (live.conditions || []).length};
    }),
    check('indexes', async () => {
      const {items} = await list(ORIGINS.firestore,
        `/v1/projects/${project}/databases/(default)/collectionGroups/-/indexes`, 'indexes');
      const matches = (declaredIndexes.indexes || []).map(spec => {
        const declarationHash = fingerprint(compositeSpec(spec));
        const candidates = items.filter(index => fingerprint(compositeSpec(index)) === declarationHash);
        const ready = candidates.find(index => index.state === 'READY');
        return {collectionGroup: spec.collectionGroup, declarationSha256: declarationHash,
          name: ready?.name || candidates[0]?.name || null, state: ready?.state || candidates[0]?.state || 'MISSING',
          passed: Boolean(ready)};
      });
      return {passed: matches.every(match => match.passed), declaredCount: matches.length,
        readyCount: matches.filter(match => match.passed).length, deployedIndexCount: items.length, matches};
    }),
    check('fieldOverrides', async () => {
      const {items} = await list(ORIGINS.firestore,
        `/v1/projects/${project}/databases/(default)/collectionGroups/-/fields`, 'fields',
        {filter: 'indexConfig.usesAncestorConfig=false OR ttlConfig:*'});
      const matches = (declaredIndexes.fieldOverrides || []).map(spec => {
        const expectedName = `projects/${project}/databases/(default)/collectionGroups/${spec.collectionGroup}/fields/${spec.fieldPath}`;
        const field = items.find(item => item.name === expectedName);
        const indexes = field?.indexConfig?.indexes || [];
        const expectedHashes = (spec.indexes || []).map(index => fingerprint(fieldIndexSpec(index))).sort();
        const actualHashes = indexes.map(index => fingerprint(fieldIndexSpec(index))).sort();
        const indexesMatch = fingerprint(expectedHashes) === fingerprint(actualHashes);
        const indexesReady = indexes.every(index => index.state === 'READY');
        const ttlActive = spec.ttl === true ? field?.ttlConfig?.state === 'ACTIVE' : !field?.ttlConfig;
        return {collectionGroup: spec.collectionGroup, fieldPath: spec.fieldPath,
          present: Boolean(field), expectedIndexCount: expectedHashes.length, activeIndexCount: actualHashes.length,
          indexesMatch, indexesReady, ttlExpected: spec.ttl === true,
          ttlState: field?.ttlConfig?.state || null,
          passed: Boolean(field) && indexesMatch && indexesReady && ttlActive};
      });
      return {passed: matches.every(match => match.passed), declaredCount: matches.length,
        activeTtlCount: matches.filter(match => match.ttlExpected && match.ttlState === 'ACTIVE').length, matches};
    }),
  ]);

  if (preflight) {
    for (const name of ['functions', 'licenseApi', 'growthConfig', 'dashboard']) {
      proof.checks[name] = {skipped: true, reason: 'preflight'};
    }
    return finish();
  }
  await Promise.all([
    check('functions', async () => {
      const [v1, v2] = await Promise.all([
        list(ORIGINS.functions, `/v1/projects/${project}/locations/-/functions`, 'functions'),
        list(ORIGINS.functions, `/v2/projects/${project}/locations/-/functions`, 'functions', {filter: 'environment="GEN_2"'}),
      ]);
      const all = [...v1.items.map(fn => ({...fn, generation: 1})), ...v2.items.map(fn => ({...fn, generation: 2}))];
      const matches = await Promise.all(selected.map(async name => {
        const candidates = all.filter(fn => fn.name === `projects/${project}/locations/us-central1/functions/${name}`);
        const fn = candidates.length === 1 ? candidates[0] : null;
        if (extrasByName.has(name) && fn) {
          const definition = extrasByName.get(name);
          const labeledCallable = fn.labels?.['deployment-callable'] === 'true' ||
            fn.labels?.['deployment-callable'] === '1' || fn.labels?.['deployment-callabled'] === 'true';
          if (definition.callable === undefined && labeledCallable) callables.add(name);
          const managedHttp = Boolean(fn.labels?.['deployment-scheduled'] || fn.labels?.['deployment-taskqueue']);
          const httpTrigger = !fn.eventTrigger && !managedHttp && Boolean(fn.httpsTrigger || fn.serviceConfig?.uri);
          if (definition.publicEndpoint === undefined && httpTrigger) publicHttp.add(name);
          if (callables.has(name)) publicHttp.add(name);
        }
        const result = {name, generation: fn?.generation || null, state: fn?.state || fn?.status || 'MISSING',
          passed: Boolean(fn && (fn.state || fn.status) === 'ACTIVE'), callable: callables.has(name),
          publicEndpointExpected: publicHttp.has(name)};
        if (!fn) return result;
        result.configurationSha256 = fingerprint(functionConfig(fn));
        if (fn.generation === 2) {
          const service = fn.serviceConfig?.service;
          if (!service) {
            result.passed = false;
            result.cloudRun = {ready: false, errorCode: 'missing-service-reference'};
          } else {
            try {
              const deployed = await get(ORIGINS.run, `/v2/${service}`);
              const condition = deployed.terminalCondition || (deployed.conditions || []).find(item => item.type === 'Ready');
              const ready = condition?.state === 'CONDITION_SUCCEEDED' || condition?.status === 'True';
              result.cloudRun = {ready, terminalConditionState: condition?.state || condition?.status || null,
                observedGeneration: deployed.observedGeneration || null,
                generation: deployed.generation || null, reconciling: deployed.reconciling === true};
              if (!ready || deployed.reconciling === true) result.passed = false;
              if (result.publicEndpointExpected) {
                result.invoker = policyProof(await get(ORIGINS.run, `/v2/${service}:getIamPolicy`), 'roles/run.invoker');
                if (!result.invoker.public) result.passed = false;
              }
            } catch (error) {
              result.cloudRun = {ready: false, errorCode: errorCode(error)};
              result.passed = false;
            }
          }
        } else if (result.publicEndpointExpected) {
          try {
            result.invoker = policyProof(await get(ORIGINS.functions, `/v1/${fn.name}:getIamPolicy`), 'roles/cloudfunctions.invoker');
            if (!result.invoker.public) result.passed = false;
          } catch (error) {
            result.invoker = {public: false, errorCode: errorCode(error)};
            result.passed = false;
          }
        }
        return result;
      }));
      const baselineFunctions = ['functions-v1.json', 'functions-v2.json'].flatMap(file =>
        JSON.parse(fs.readFileSync(path.join(BASELINE, file), 'utf8')).functions || []);
      const baselineLicense = baselineFunctions.find(fn => fn.name.endsWith('/licenseApi'));
      const liveLicense = all.find(fn => fn.name.endsWith('/licenseApi'));
      const baselineLicenseHash = baselineLicense ? fingerprint(functionConfig(baselineLicense)) : null;
      const liveLicenseHash = liveLicense ? fingerprint(functionConfig(liveLicense)) : null;
      proof.checks.licenseApi = {passed: Boolean(liveLicense && (liveLicense.state || liveLicense.status) === 'ACTIVE' &&
        baselineLicenseHash && baselineLicenseHash === liveLicenseHash),
        preserved: Boolean(baselineLicenseHash && baselineLicenseHash === liveLicenseHash),
        state: liveLicense?.state || liveLicense?.status || 'MISSING', baselineSha256: baselineLicenseHash,
        currentSha256: liveLicenseHash};
      return {passed: matches.every(match => match.passed) && v1.unreachable.length === 0 && v2.unreachable.length === 0,
        activeSelectedCount: matches.filter(match => match.state === 'ACTIVE').length,
        readySelectedCount: matches.filter(match => match.passed).length,
        publicEndpointsCount: matches.filter(match => match.invoker?.public).length,
        expectedPublicEndpointsCount: publicHttp.size, deployedFunctionCount: all.length,
        unreachableRegionCount: v1.unreachable.length + v2.unreachable.length, matches};
    }),
    check('growthConfig', async () => {
      const doc = await get(ORIGINS.firestore,
        `/v1/projects/${project}/databases/(default)/documents/growthOps/config`, true);
      const fields = doc?.fields || {};
      const config = Object.fromEntries(['enabled', 'stage', 'testerCapacity', 'missionHours',
        'welcomePoints', 'referrerPoints', 'maxInvitesPerDay', 'maxRewardsPerMonth',
        'maxRewardPointsPerMonth', 'holdHours', 'maxSupportPerDay', 'inviteExpiryDays']
        .map(key => [key, decodeValue(fields[key])]).filter(([, value]) => value !== undefined));
      // Missing fields use the implementation's defaults; record this explicitly
      // rather than pretending an absent document was explicitly configured.
      const effective = {enabled: true, stage: 'testers', testerCapacity: 20, missionHours: 48,
        welcomePoints: 5, referrerPoints: 10, maxInvitesPerDay: 10, maxRewardsPerMonth: 50,
        maxRewardPointsPerMonth: 100, holdHours: 24, maxSupportPerDay: 10, inviteExpiryDays: 7, ...config};
      return {passed: effective.enabled === true && effective.stage === 'testers' &&
        effective.testerCapacity === 20 && effective.missionHours === 48,
        documentExists: Boolean(doc), usingServerDefaults: !doc, effective,
        fieldsSha256: fingerprint(fields)};
    }),
    check('dashboard', async () => {
      const doc = await get(ORIGINS.firestore,
        `/v1/projects/${project}/databases/(default)/documents/dashboard/metrics`, true);
      const updatedAt = decodeValue(doc?.fields?.updatedAt);
      const updatedMs = Date.parse(updatedAt);
      const ageMs = Date.now() - updatedMs;
      const fresh = Number.isFinite(updatedMs) && ageMs >= -60000 && ageMs <= maxAgeMinutes * 60000;
      const afterRequiredTime = dashboardAfter === undefined || updatedMs >= dashboardAfter;
      return {passed: fresh && afterRequiredTime, documentExists: Boolean(doc),
        updatedAtUtc: Number.isFinite(updatedMs) ? new Date(updatedMs).toISOString() : null,
        ageMinutes: Number.isFinite(ageMs) ? Math.round(ageMs / 6000) / 10 : null,
        maximumAgeMinutes: maxAgeMinutes, fresh, afterRequiredTime,
        requiredAfterUtc: dashboardAfter === undefined ? null : new Date(dashboardAfter).toISOString(),
        fieldsSha256: fingerprint(doc?.fields || {})};
    }),
  ]);
  if (!proof.checks.licenseApi) proof.checks.licenseApi = {passed: false, errorCode: 'function-list-unavailable'};
  return finish();
}

if (require.main === module) {
  verify().catch(error => {
    console.error(JSON.stringify({status: 'FAIL', errorCode: errorCode(error)}));
    process.exitCode = 1;
  });
}
module.exports = {verify, SELECTED, CALLABLES, PUBLIC_HTTP, stable, semanticTemplate, additionalTargets,
  compositeSpec, fieldIndexSpec, functionConfig, hasPublicInvoker};
