const {test} = require('node:test');
const assert = require('node:assert/strict');
const {DEFAULT_PUBLIC_DISCOVERY_CONFIG, publicDiscoveryConfig, scopeAllows, reciprocalScopeAllows,
  trustedPartyEdge, recentEnrollmentLocation, currentPublicReceipt} = require('../lib/lib/matching_scope_policy');
const {DAY, MINUTE} = require('../lib/lib/background_match_policy');
const at = ms => ({toMillis: () => ms});

test('provisional local rollout defaults and invalid configuration fail closed', () => {
  assert.deepEqual(publicDiscoveryConfig(undefined), DEFAULT_PUBLIC_DISCOVERY_CONFIG);
  assert.deepEqual(publicDiscoveryConfig({minimumUsers: 1234, radiusMiles: 8}), {minimumUsers: 1234, radiusMiles: 8, activeWithinDays: 30});
  for (const config of [{}, {minimumUsers: 1, radiusMiles: 10}, {minimumUsers: 1000, radiusMiles: 0},
    {minimumUsers: 1000, radiusMiles: 10, enabled: false}, {minimumUsers: 1000, radiusMiles: 10, activeWithinDays: 90}]) {
    assert.equal(publicDiscoveryConfig(config), null);
  }
});
test('Party means direct, Tree means exactly up to two proven hops, and public must be locally unlocked on both sides', () => {
  for (const unlocked of [false, true]) {
    assert.equal(scopeAllows('partyOnly', unlocked, 'direct'), true);
    assert.equal(scopeAllows('partyOnly', unlocked, 'tree'), false);
    assert.equal(scopeAllows('tree', unlocked, 'tree'), true);
    assert.equal(scopeAllows('tree', unlocked, 'none'), false);
  }
  assert.equal(scopeAllows('all', false, 'none'), false);
  assert.equal(scopeAllows('public', true, 'none'), true);
  assert.equal(reciprocalScopeAllows({partyScope: 'public', publicUnlocked: true}, {partyScope: 'partyOnly', publicUnlocked: true}, 'tree'), false);
  assert.equal(reciprocalScopeAllows({partyScope: 'public', publicUnlocked: true}, {partyScope: 'public', publicUnlocked: false}, 'none'), false);
});
test('legacy mutual projections do not imply meeting; enrollment ages and area-specific public receipts expire', () => {
  const forward = {uid: 'bob', mutual: true, metInPerson: true, connectionId: 'id'};
  const reverse = {uid: 'alice', mutual: true, metInPerson: true, connectionId: 'id'};
  const receipt = {members: ['alice', 'bob'], status: 'connected', decisions: {alice: 'add', bob: 'add'}, proof: {kind: 'inPersonCode'}};
  assert.equal(trustedPartyEdge('alice', 'bob', forward, reverse, receipt), true);
  assert.equal(trustedPartyEdge('alice', 'bob', {...forward, metInPerson: false}, reverse, receipt), false);
  assert.equal(trustedPartyEdge('alice', 'bob', forward, reverse, {...receipt, proof: {}}), false);
  const now = Date.now();
  assert.equal(recentEnrollmentLocation({latitude: 40, longitude: -74, lastSeenAt: at(now - 29 * DAY)}, now), true);
  assert.equal(recentEnrollmentLocation({latitude: 40, longitude: -74, lastSeenAt: at(now - 31 * DAY)}, now), false);
  const area = {publicUnlocked: true, latitude: 40, longitude: -74, checkedAt: at(now)};
  assert.equal(currentPublicReceipt(area, {latitude: 40, longitude: -74}, now), true);
  assert.equal(currentPublicReceipt(area, {latitude: 41, longitude: -74}, now), false);
  assert.equal(currentPublicReceipt({...area, checkedAt: at(now - 16 * MINUTE)}, area, now), false);
});
