const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const {createHash} = require('node:crypto');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Matching tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit'});
const db = admin.firestore();
const {matchingGraph, trustedRelationship, localEnrollmentCount, refreshMatchingAccess, getMatchingAccess,
  acknowledgePublicMatchingUnlock, invalidateMatchingGraphs, matchingPairScope} = require('../lib/matching_scope');
const {DAY} = require('../lib/lib/background_match_policy');
const at = ms => admin.firestore.Timestamp.fromMillis(ms);
const id = (a, b) => createHash('sha256').update(JSON.stringify([a, b].sort())).digest('hex');
beforeEach(async () => {
  const r = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(r.status, 200);
});
after(async () => {await admin.app().delete();});
async function user(uid, lat = 40, lon = -74, lastSeenAt = Date.now()) {
  await db.doc(`users/${uid}`).set({displayName: uid});
  await db.doc(`publicProfiles/${uid}`).set({displayName: uid});
  await db.doc(`matchingLocations/${uid}`).set({uid, latitude: lat, longitude: lon, lastSeenAt: at(lastSeenAt)});
}
async function connect(a, b) {
  const connectionId = id(a, b);
  await db.doc(`partyConnections/${connectionId}`).set({members: [a, b].sort(), status: 'connected',
    decisions: {[a]: 'add', [b]: 'add'}, proof: {kind: 'inPersonCode'}, connectedAt: at(Date.now())});
  const batch = db.batch();
  for (const [owner, other] of [[a, b], [b, a]]) batch.set(db.doc(`users/${owner}/party/${other}`),
    {uid: other, mutual: true, metInPerson: true, connectionId, source: 'inPersonDirectInvite'});
  await batch.commit();
}
test('trusted graph expands exactly one friend-of-friend hop and names the real mutual person', async () => {
  for (const uid of ['alice', 'bob', 'carol', 'dave', 'legacy']) await user(uid);
  await connect('alice', 'bob'); await connect('bob', 'carol'); await connect('carol', 'dave');
  for (const [a, b] of [['alice', 'legacy'], ['legacy', 'alice']]) await db.doc(`users/${a}/party/${b}`).set({uid: b, mutual: true});
  const graph = await matchingGraph('alice');
  assert.deepEqual(graph.directUids, ['bob']);
  assert.deepEqual(graph.treeMatches, [{uid: 'carol', mutualUids: ['bob'], mutualNames: ['bob']}]);
  assert.deepEqual(await trustedRelationship('alice', 'dave'), {relationship: 'none', mutualUids: []});
  await db.doc('users/carol/blocks/alice').set({uid: 'alice'});
  assert.deepEqual((await matchingGraph('alice')).treeMatches, []);
});
test('local enrollment counts recent enrolled accounts, includes offline users, and excludes deletion, stale and far records', async () => {
  const now = Date.now();
  await user('alice'); await user('offline', 40, -74, now - 20 * DAY); await user('far', 45); await user('stale', 40, -74, now - 31 * DAY);
  await user('deleted'); await db.doc('accountDeletions/deleted').set({status: 'pending'});
  await user('disabled'); await db.doc('users/disabled').update({disabled: true});
  await db.doc('matchingLocations/forged').set({uid: 'forged', latitude: 40, longitude: -74, lastSeenAt: at(now)});
  assert.equal(await localEnrollmentCount({latitude: 40, longitude: -74}, {minimumUsers: 100, radiusMiles: 1}, now), 2);
  assert.equal(await localEnrollmentCount({latitude: 40, longitude: -74}, {minimumUsers: 100, radiusMiles: 1, activeWithinDays: 7}, now), 1);
});
test('existing server-consented completed meetups migrate to proven graph edges while arbitrary legacy party docs are revoked', async () => {
  await user('alice'); await user('bob'); await user('legacy');
  const connectionId = id('alice', 'bob');
  await db.doc('meetups/old').set({aUid: 'alice', bUid: 'bob', status: 'completed', aArrived: true, bArrived: true, completedAt: at(Date.now())});
  await db.doc(`partyConnections/${connectionId}`).set({members: ['alice', 'bob'], status: 'connected',
    decisions: {alice: 'add', bob: 'add'}, chatId: 'old', connectedAt: at(Date.now())});
  for (const [a, b] of [['alice', 'bob'], ['bob', 'alice']]) await db.doc(`users/${a}/party/${b}`).set({uid: b, mutual: true, source: 'postMeetup', connectionId});
  for (const [a, b] of [['alice', 'legacy'], ['legacy', 'alice']]) await db.doc(`users/${a}/party/${b}`).set({uid: b, mutual: true});
  assert.deepEqual((await matchingGraph('alice')).directUids, ['bob']);
  assert.equal((await db.doc('users/alice/party/bob').get()).data().metInPerson, true);
  assert.equal((await db.doc('users/alice/party/legacy').get()).exists, false);
});
test('public transition promotes Tree once, preserves later Tree and Party choices, and locks again in a sparse area', async () => {
  await user('alice'); await user('bob');
  await db.doc('matchingConfig/publicDiscovery').set({minimumUsers: 2, radiusMiles: 1});
  await db.doc('users/alice/settings/matching').set({partyScope: 'tree'});
  let access = await refreshMatchingAccess('alice');
  assert.equal(access.publicUnlocked, true); assert.equal(access.partyScope, 'public');
  assert.equal((await db.doc('users/alice/settings/matching').get()).data().partyScope, 'public');
  const firstUnlock = access.publicUnlockedAt.toMillis();
  await acknowledgePublicMatchingUnlock.run({auth: {uid: 'alice'}, data: {expectedUid: 'alice'}});
  const acknowledged = (await db.doc('users/alice/matchingAccess/current').get()).data().publicUnlockNotifiedAt.toMillis();
  await db.doc('users/alice/settings/matching').update({partyScope: 'tree'});
  access = await refreshMatchingAccess('alice');
  assert.equal(access.partyScope, 'tree'); assert.equal(access.publicUnlockedAt.toMillis(), firstUnlock);
  await db.doc('users/alice/presence/current').set({geopoint: new admin.firestore.GeoPoint(50, -74), ts: at(Date.now())});
  access = await refreshMatchingAccess('alice');
  assert.equal(access.publicUnlocked, false); assert.equal(access.partyScope, 'tree');
  assert.equal(access.publicUnlockNotifiedAt.toMillis(), acknowledged);
  await db.doc('users/bob/settings/matching').set({partyScope: 'partyOnly'});
  await db.doc('users/alice/presence/current').set({geopoint: new admin.firestore.GeoPoint(40, -74), ts: at(Date.now() + 1)});
  await refreshMatchingAccess('alice');
  const party = await refreshMatchingAccess('bob');
  assert.equal(party.publicUnlocked, true); assert.equal(party.partyScope, 'partyOnly');
});
test('reciprocal scopes never let public strangers bypass Party or Tree restrictions', async () => {
  for (const uid of ['alice', 'bob', 'carol']) await user(uid);
  await connect('alice', 'bob'); await connect('bob', 'carol');
  const location = {latitude: 40, longitude: -74}; const now = Date.now();
  for (const uid of ['alice', 'carol']) await db.doc(`users/${uid}/matchingAccess/current`).set({...location, checkedAt: at(now), publicUnlocked: true, publicConfigFingerprint: '1000:10:30'});
  assert.equal((await matchingPairScope('alice', 'carol', {partyScope: 'public'}, {partyScope: 'public'}, location, location, now)).relationship, 'none');
  await db.doc('matchingConfig/publicDiscovery').set({minimumUsers: 1000, radiusMiles: 10, enabled: false});
  assert.equal((await matchingPairScope('alice', 'carol', {partyScope: 'public'}, {partyScope: 'public'}, location, location, now)).relationship, 'tree');
  await db.doc('matchingConfig/publicDiscovery').delete();
  assert.equal((await matchingPairScope('alice', 'carol', {partyScope: 'tree'}, {partyScope: 'tree'}, location, location, now)).relationship, 'tree');
  assert.equal(await matchingPairScope('alice', 'carol', {partyScope: 'public'}, {partyScope: 'partyOnly'}, location, location, now), null);
  await db.doc('users/bob/party/carol').delete();
  assert.equal(await matchingPairScope('alice', 'carol', {partyScope: 'tree'}, {partyScope: 'tree'}, location, location, now), null);
});
test('Party removal invalidates adjacent graph receipts and refresh cannot restore the removed bridge', async () => {
  for (const uid of ['alice', 'bob', 'carol']) await user(uid);
  await connect('alice', 'bob'); await connect('bob', 'carol');
  await refreshMatchingAccess('alice'); await refreshMatchingAccess('bob'); await refreshMatchingAccess('carol');
  await db.doc('users/bob/party/carol').delete();
  await invalidateMatchingGraphs('bob', 'carol');
  const receipt = (await db.doc('users/alice/matchingAccess/current').get()).data();
  assert.equal(receipt.graphInvalidated, true); assert.deepEqual(receipt.treeMatches, []);
  const fresh = await refreshMatchingAccess('alice');
  assert.equal(fresh.graphInvalidated, false); assert.deepEqual(fresh.treeMatches, []);
});
test('matching callable account binding and notification acknowledgement are server guarded', async () => {
  await user('alice');
  await assert.rejects(getMatchingAccess.run({data: {}}), {code: 'unauthenticated'});
  await assert.rejects(getMatchingAccess.run({auth: {uid: 'alice'}, data: {expectedUid: 'bob'}}), {code: 'failed-precondition'});
  await assert.rejects(acknowledgePublicMatchingUnlock.run({auth: {uid: 'alice'}, data: {}}), {code: 'failed-precondition'});
  const locked = await getMatchingAccess.run({auth: {uid: 'alice'}, data: {expectedUid: 'alice'}});
  assert.equal(locked.publicUnlocked, false); assert.equal(locked.partyScope, 'tree');
  assert.equal(typeof locked.checkedAt, 'number'); assert.equal(locked.latitude, 40); assert.equal(locked.longitude, -74);
});
