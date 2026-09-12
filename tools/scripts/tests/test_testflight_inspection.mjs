import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { inspect, inspectRecentBuilds, tokenFor } from '../inspect_testflight.mjs';

test('ASC token uses verifiable ES256 and a bounded lifetime', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const key = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const token = tokenFor({ APP_STORE_CONNECT_API_KEY_ID: 'fixture', APP_STORE_CONNECT_ISSUER_ID: 'issuer',
    APP_STORE_CONNECT_API_KEY_P8_BASE64: Buffer.from(key).toString('base64') }, 1000);
  const [header, payload, signature] = token.split('.');
  assert.equal(JSON.parse(Buffer.from(payload, 'base64url')).exp, 1300);
  assert.equal(Buffer.from(signature, 'base64url').length, 64);
  assert(verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
});

test('only enabled genuine TestFlight links are returned', async () => {
  const result = await inspect(async path => path.startsWith('/v1/apps?')
    ? { data: [{ id: '123', attributes: { bundleId: 'com.prox-us.prox' } }] }
    : { data: [
      { attributes: { name: 'public', publicLinkEnabled: true, publicLink: 'https://testflight.apple.com/join/abcd1234' } },
      { attributes: { name: 'disabled', publicLinkEnabled: false, publicLink: 'https://testflight.apple.com/join/disabled' } },
      { attributes: { name: 'invalid', publicLinkEnabled: true, publicLink: 'https://example.invalid/join/abcd' } },
    ] });
  assert.deepEqual(result.groups.map(g => g.publicLink), ['https://testflight.apple.com/join/abcd1234', null, null]);
});

test('ambiguous app lookup is rejected', async () => {
  await assert.rejects(inspect(async () => ({ data: [] })), /exactly one/);
});

test('recent builds distinguish processing from tester-group access without returning tester data', async () => {
  const result = await inspectRecentBuilds(async path => {
    assert.match(path, /filter\[app\]=123&/);
    return {data: [{id: 'build', attributes: {version: '23', processingState: 'VALID', expired: false}, relationships: {
      preReleaseVersion: {data: {type: 'preReleaseVersions', id: 'version'}},
      buildBetaDetail: {data: {type: 'buildBetaDetails', id: 'detail'}},
      betaGroups: {data: [{type: 'betaGroups', id: 'group'}]},
    }}], included: [
      {type: 'preReleaseVersions', id: 'version', attributes: {version: '0.19.0'}},
      {type: 'buildBetaDetails', id: 'detail', attributes: {internalBuildState: 'IN_BETA_TESTING', externalBuildState: 'READY_FOR_BETA_SUBMISSION', autoNotifyEnabled: true}},
      {type: 'betaGroups', id: 'group', attributes: {name: 'Prox Testers', isInternalGroup: true, testers: ['private fixture']}},
    ]};
  }, '123');
  assert.equal(result[0].version, '0.19.0');
  assert.equal(result[0].build, '23');
  assert.equal(result[0].internalBuildState, 'IN_BETA_TESTING');
  assert.equal(result[0].externalBuildState, 'READY_FOR_BETA_SUBMISSION');
  assert.deepEqual(result[0].groups, [{name: 'Prox Testers', internal: true}]);
  assert(!JSON.stringify(result).includes('private fixture'));
});

test('a processing build with no beta detail does not imply testing availability', async () => {
  const result = await inspectRecentBuilds(async () => ({data: [{attributes: {version: '23', processingState: 'PROCESSING'}}]}), '123');
  assert.equal(result[0].processingState, 'PROCESSING');
  assert.equal(result[0].internalBuildState, null);
  assert.deepEqual(result[0].groups, []);
});
