const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');
const {readFileSync} = require('node:fs');
const path = require('node:path');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Icebreaker tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit'});
const db = admin.firestore();
const {icebreakerAction, icebreakerPoint, icebreakerClose, icebreakerSignal, sweepIcebreaker} = require('../lib/icebreaker');
const {connectionId} = require('../lib/party_connections');
const {reconcileVerifiedPartyConnection} = require('../lib/lib/party');
const {trustedPartyEdge} = require('../lib/lib/matching_scope_policy');
const tokens = {alice: 'a'.repeat(32), bob: 'b'.repeat(32), carol: 'c'.repeat(32)};
const ts = ms => admin.firestore.Timestamp.fromMillis(ms);
const call = (uid, action = 'observe', extra = {}) => icebreakerAction(uid, {action, token: tokens[uid], ...extra});
const presence = patch => ({geopoint: new admin.firestore.GeoPoint(40, -74), locationTs: ts(Date.now()),
  ts: ts(Date.now()), expiresAt: ts(Date.now() + 180000), cached: false, accuracyMeters: 5, modeKind: 'icebreaker', ...patch});
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(response.status, 200);
  for (const uid of Object.keys(tokens)) {
    await db.doc(`users/${uid}`).set({displayName: uid, keywords: {
      'Searching For': ['Guitar'], 'Can Provide': ['Guitar', 'private unrelated offering']}});
    await db.doc(`users/${uid}/settings/matching`).set({modeKind: 'icebreaker', partyScope: 'partyOnly'});
    await db.doc(`users/${uid}/presence/current`).set(presence());
  }
});
after(async () => admin.app().delete());

test('approximate proximity rejects cached, inaccurate, missing, future, stale and expired fixes', () => {
  const now = Date.now();
  const good = presence();
  assert.ok(icebreakerPoint(good, now));
  for (const patch of [{cached: true}, {cached: undefined}, {accuracyMeters: 21}, {accuracyMeters: -1},
    {accuracyMeters: undefined}, {locationTs: ts(now - 45001)}, {locationTs: ts(now + 5001)},
    {expiresAt: ts(now)}, {geopoint: undefined}]) assert.equal(icebreakerPoint({...good, ...patch}, now), null);
  const a = {latitude: 40, longitude: -74, accuracyMeters: 20};
  assert.equal(icebreakerClose(a, {...a, accuracyMeters: 20}), true);
  assert.equal(icebreakerClose(a, {...a, latitude: 40.0001}), false); // uncertainty > 45m
  assert.equal(icebreakerClose({...a, accuracyMeters: 1}, {...a, accuracyMeters: 1, latitude: 40.00028}), false); // > 30m
});

test('shared signal is symmetric, non-identifying, and changes between sessions', () => {
  const a = icebreakerSignal('alice', 'bob', tokens.alice, tokens.bob, 5);
  assert.deepEqual(a, icebreakerSignal('bob', 'alice', tokens.bob, tokens.alice, 5));
  assert.notEqual(a.key, icebreakerSignal('alice', 'bob', 'd'.repeat(32), tokens.bob, 5).key);
  assert.deepEqual(Object.keys(a).sort(), ['band', 'colorIndex', 'key', 'mark', 'symbolIndex']);
});

test('only foreground opt-in participants signal; keywords and identities remain withheld', async () => {
  let a = await call('alice');
  assert.equal(a.nearby, false);
  assert.equal(a.signals.length, 0);
  await call('bob');
  a = await call('alice');
  const b = await call('bob');
  assert.equal(a.nearby, true);
  assert.equal(a.signals.length, 1);
  assert.deepEqual(a.signals, b.signals);
  assert.equal(a.encounter, null);
  assert.equal(JSON.stringify(a).includes('bob'), false);
  assert.equal(JSON.stringify(a).includes('guitar'), false);
  assert.equal(JSON.stringify(a).includes('latitude'), false);
  await db.doc('users/bob/settings/matching').update({modeKind: 'normal'});
  a = await call('alice');
  assert.equal(a.nearby, false);
  assert.equal(a.signals.length, 0);
});

test('proximity without compatible keywords supplies only ambient warmth', async () => {
  await db.doc('users/bob').update({keywords: {'Searching For': ['gardening'], 'Can Provide': ['gardening']}});
  await call('alice');
  await call('bob');
  const a = await call('alice');
  assert.equal(a.nearby, true);
  assert.equal(a.band, 'close');
  assert.equal(a.signals.length, 0);
});

test('blocking, suspension, deletion and busy peers suppress signals and prevent code pairing', async () => {
  await call('alice');
  const bob = await call('bob');
  for (const [path, data] of [
    ['users/bob/blocks/alice', {blocked: true}],
    ['accountEnforcements/bob', {status: 'suspended'}],
    ['accountDeletions/bob', {deleted: true}],
  ]) {
    await db.doc(path).set(data);
    assert.equal((await call('alice')).nearby, false);
    await assert.rejects(call('alice', 'join', {code: bob.code}), /unavailable/);
    await db.doc(path).delete();
  }
  await db.doc('users/bob').update({interactionLock: {busyInMeetup: true}});
  assert.equal((await call('alice')).nearby, false);
  await assert.rejects(call('alice', 'join', {code: bob.code}), /active meetup/);
});

async function paired() {
  await call('alice');
  const b = await call('bob');
  await call('alice', 'join', {code: b.code});
}
async function membership(expected) {
  const a = await db.doc('users/alice/party/bob').get();
  const b = await db.doc('users/bob/party/alice').get();
  assert.equal(a.exists, expected);
  assert.equal(b.exists, expected);
}

test('QR/code confirmation is not keyword consent or Party consent; both decisions commit atomically', async () => {
  await paired();
  let a = await call('alice');
  assert.equal(a.encounter.revealed, false);
  assert.equal('keywords' in a.encounter, false);
  await membership(false);
  await assert.rejects(call('alice', 'add'), /agree to reveal/);
  a = await call('alice', 'reveal');
  assert.equal(a.encounter.myReveal, true);
  assert.equal('keywords' in a.encounter, false);
  let b = await call('bob', 'reveal');
  assert.deepEqual(b.encounter.keywords, ['guitar']);
  assert.equal(b.encounter.peerName, 'alice');
  await membership(false);
  a = await call('alice', 'add');
  assert.equal(a.encounter.connected, false);
  await membership(false);
  b = await call('bob', 'add');
  assert.equal(b.encounter.connected, true);
  await membership(true);
  const receipt = (await db.doc(`partyConnections/${connectionId('alice', 'bob')}`).get()).data();
  assert.equal(receipt.proof.kind, 'icebreaker');
  assert.equal(await reconcileVerifiedPartyConnection('alice', 'bob'), true);
  assert.equal(trustedPartyEdge('alice', 'bob',
    (await db.doc('users/alice/party/bob').get()).data(),
    (await db.doc('users/bob/party/alice').get()).data(), receipt), true);
  await call('alice', 'cancel');
  await membership(true);
});

test('expired leases, remote positions and a late block prevent reveal and Party writes', async () => {
  await paired();
  await call('alice', 'reveal');
  await call('bob', 'reveal');
  await call('alice', 'add');
  await db.doc('users/bob/blocks/alice').set({blocked: true});
  await assert.rejects(call('bob', 'add'), /ended/);
  await membership(false);
  await db.doc('users/bob/blocks/alice').delete();
  await db.doc('icebreakerSessions/bob').update({expiresAt: ts(Date.now() - 1)});
  await assert.rejects(call('alice', 'reveal'), /ended/);
  await call('bob');
  await db.doc('users/bob/presence/current').set(presence({geopoint: new admin.firestore.GeoPoint(40.01, -74)}));
  await assert.rejects(call('alice', 'reveal'), /ended/);
  await membership(false);
});

test('cancel revokes pending disclosure and stop tombstones delayed heartbeats', async () => {
  await paired();
  await call('alice', 'reveal');
  await call('bob', 'cancel');
  assert.equal((await call('alice')).encounter, null);
  await membership(false);
  await call('alice', 'stop');
  await assert.rejects(call('alice'), /session ended/);
  await call('alice', 'observe', {token: 'd'.repeat(32)});
  await call('alice', 'stop'); // stale session must not close its replacement
  assert.equal((await db.doc('icebreakerSessions/alice').get()).data().active, true);
});

test('failed guesses are throttled and codes cannot be used for oneself', async () => {
  const a = await call('alice');
  await assert.rejects(call('alice', 'join', {code: a.code}), /current Icebreaker code/);
  for (let i = 0; i < 9; i++) await assert.rejects(call('alice', 'join', {code: '0123456789'}), /current Icebreaker code/);
  await assert.rejects(call('alice', 'join', {code: '0123456789'}), /Too many/);
});

test('a replaced session cannot revoke another session consent; swept encounters can be reset', async () => {
  await paired();
  await assert.rejects(call('alice', 'cancel', {token: 'd'.repeat(32)}), /session is unavailable/);
  const id = (await db.doc('icebreakerSessions/alice').get()).data().encounterId;
  await db.doc(`icebreakerEncounters/${id}`).delete();
  await call('alice', 'cancel');
  await call('bob', 'cancel');
  assert.equal((await call('alice')).encounter, null);
});

test('foreground-only leases exclude remote and departed peers even with live ordinary presence', async () => {
  await call('alice');
  await call('bob');
  await db.doc('icebreakerSessions/bob').update({expiresAt: ts(Date.now() - 1)});
  assert.equal((await call('alice')).nearby, false);
  await call('bob');
  await db.doc('users/bob/presence/current').set(presence({geopoint: new admin.firestore.GeoPoint(40.001, -74)}));
  assert.equal((await call('alice')).nearby, false);
});

test('expired data is swept; authenticated clients cannot read or forge private sessions and consent', async () => {
  await paired();
  await db.doc('icebreakerRateLimits/alice').set({expiresAt: ts(Date.now() - 1)});
  await sweepIcebreaker.run({});
  assert.equal((await db.doc('icebreakerRateLimits/alice').get()).exists, false);
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const env = await initializeTestEnvironment({projectId: 'demo-prox-audit', firestore: {
    host, port: Number(port), rules: readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
  }});
  try {
    const client = env.authenticatedContext('alice').firestore();
    for (const collection of ['icebreakerSessions', 'icebreakerCodes', 'icebreakerEncounters', 'icebreakerRateLimits']) {
      await assertFails(getDoc(doc(client, `${collection}/alice`)));
      await assertFails(setDoc(doc(client, `${collection}/forged`), {members: ['alice', 'bob'], reveal: {bob: true}}));
    }
  } finally { await env.cleanup(); }
});
