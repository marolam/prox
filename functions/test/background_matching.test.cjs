const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Background tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit'});
const db = admin.firestore();
const {reciprocalKeywords, alertAllowed, quietNow, MINUTE, DAY} = require('../lib/lib/background_match_policy');
const {recordBackgroundOpportunity, scanBackgroundMatches, dispatchBackgroundAlert, readBackgroundOpportunity,
  getBackgroundOpportunity, listBackgroundOpportunities} = require('../lib/background_matching');
const at = ms => admin.firestore.Timestamp.fromMillis(ms);
beforeEach(async () => {
  const r = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(r.status, 200);
});
after(async () => { await admin.app().delete(); });
test('background reads reject a callable whose bound account differs from its auth token', async () => {
  for (const callable of [getBackgroundOpportunity, listBackgroundOpportunities]) {
    await assert.rejects(callable.run({auth: {uid: 'alice'},
      data: {expectedUid: 'bob', opportunityId: '0'.repeat(64)}}), {code: 'failed-precondition'});
  }
});
const profile = (wants = ['gardening', 'carpentry'], offers = ['cooking', 'photography']) =>
  ({displayName: 'Example', ageYears: 30, keywords: {'Searching For': wants, 'Can Provide': offers}});
async function person(uid, reverse = false, overrides = {}, now = Date.now()) {
  const batch = db.batch();
  const values = {
    [`publicProfiles/${uid}`]: reverse ? profile(['cooking', 'photography'], ['gardening', 'carpentry']) : profile(),
    [`users/${uid}/settings/backgroundMatching`]: {enabled: true, notificationsEnabled: true, quietHoursEnabled: false, dailyAlertLimit: 3, deviceId: uid},
    [`users/${uid}/settings/matching`]: {modeKind: 'normal', normalMode: 'passive', radiusMiles: 2},
    [`users/${uid}/backgroundPresence/current`]: {enabled: true, deviceId: uid, latitude: 40, longitude: -74, accuracyMeters: 100,
      speedMps: 0, locationAt: at(now), receivedAt: at(now), utcOffsetMinutes: -240},
    ...overrides,
  };
  for (const [path, value] of Object.entries(values)) batch.set(db.doc(path), value);
  await batch.commit();
}
async function pair() { await person('alice'); await person('bob', true); }
const outbox = uid => db.collection(`users/${uid}/backgroundAlertOutbox`).get();

test('significance requires two distinct complementary keywords on each side', () => {
  const a = profile([' Gardening ', 'GARDENING', 'carpentry', 'help'], ['Cooking', 'photography']);
  assert.equal(reciprocalKeywords(a, profile(['cooking'], ['gardening', 'carpentry'])).significant, false);
  const fit = reciprocalKeywords(a, profile(['photography', 'cooking'], ['gardening', 'carpentry']));
  assert.deepEqual(fit.forA, ['carpentry', 'gardening']);
  assert.equal(fit.significant, true);
  assert.equal(reciprocalKeywords(profile(), profile()).significant, false);
  assert.equal(reciprocalKeywords(profile(['help', 'anything'], ['help', 'anything']), profile(['help', 'anything'], ['help', 'anything'])).significant, false);
});

test('quiet hours, rolling limits, four-hour gap and seven-day pair limit remain server enforced', () => {
  const now = Date.UTC(2026, 8, 13, 16);
  const p = {enabled: true, notificationsEnabled: true, dailyAlertLimit: 3, utcOffsetMinutes: -240};
  assert.equal(alertAllowed(p, [], 0, now), true);
  assert.equal(alertAllowed(p, [now - MINUTE], 0, now), false);
  assert.equal(alertAllowed(p, [now - 4 * 60 * MINUTE, now - 8 * 60 * MINUTE, now - 12 * 60 * MINUTE], 0, now), false);
  assert.equal(alertAllowed({...p, dailyAlertLimit: 6}, [now - 4 * 60 * MINUTE, now - 8 * 60 * MINUTE, now - 12 * 60 * MINUTE], 0, now), true);
  assert.equal(alertAllowed({...p, dailyAlertLimit: 999}, [now - 4 * 60 * MINUTE, now - 8 * 60 * MINUTE, now - 12 * 60 * MINUTE], 0, now), false);
  assert.equal(alertAllowed(p, [], now - 6 * DAY, now), false);
  assert.equal(alertAllowed(p, [now - DAY], now - 7 * DAY, now), true);
  assert.equal(quietNow(p, Date.UTC(2026, 8, 14, 2)), true);
  assert.equal(quietNow(p, Date.UTC(2026, 8, 14, 12)), false);
  assert.equal(alertAllowed({...p, notificationsEnabled: false}, [], 0, now), false);
});

test('passive users get reciprocal opportunities without activation; concurrent scans cannot duplicate alerts', async () => {
  await pair();
  await Promise.all([recordBackgroundOpportunity('alice', 'bob'), recordBackgroundOpportunity('bob', 'alice')]);
  assert.equal((await outbox('alice')).size, 1);
  assert.equal((await outbox('bob')).size, 1);
  assert.equal((await db.doc('users/alice/settings/matching').get()).data().normalMode, 'passive');
  const opportunities = await listBackgroundOpportunities.run({auth: {uid: 'alice'}, data: {}});
  assert.equal(opportunities.opportunities.length, 1);
  const opportunity = opportunities.opportunities[0];
  assert.equal(opportunity.significant, true);
  assert.equal(opportunity.latitude, undefined);
  assert.deepEqual(await readBackgroundOpportunity('mallory', opportunity.opportunityId), {available: false});
  await assert.rejects(getBackgroundOpportunity.run({data: {opportunityId: opportunity.opportunityId}}), /Sign in/);
});

test('ordinary reciprocal and Listen matches are quiet; Listen ignores keywords and criteria', async () => {
  await pair();
  await db.doc('publicProfiles/bob').set(profile(['cooking'], ['gardening']));
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), true);
  assert.equal((await outbox('alice')).size, 0);
  await db.doc('users/alice/settings/matching').set({modeKind: 'listen', businessOnly: true, partyScope: 'partyOnly', ageBracket: 'age55Plus'});
  await db.doc('users/bob/settings/matching').set({modeKind: 'listen'});
  await db.doc('publicProfiles/bob').set(profile([], []));
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), true);
  assert.equal((await outbox('alice')).size, 0);
});

test('Off, Treasure, mismatched modes and stale or wrong-device samples are excluded', async () => {
  await pair();
  for (const modeKind of ['off', 'treasureHunt', 'listen', 'travel']) {
    await db.doc('users/bob/settings/matching').update({modeKind});
    assert.equal(await recordBackgroundOpportunity('alice', 'bob'), false, modeKind);
  }
  await db.doc('users/bob/settings/matching').update({modeKind: 'normal'});
  await db.doc('users/bob/backgroundPresence/current').update({deviceId: 'old-phone'});
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), false);
  await db.doc('users/bob/backgroundPresence/current').update({deviceId: 'bob', locationAt: at(Date.now() - 31 * MINUTE)});
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), false);
});

test('mutual radius, blocking, deletion, meetup and criteria are enforced for both participants', async () => {
  await pair();
  for (const [path, patch] of [
    ['users/bob/blocks/alice', {}], ['accountDeletions/alice', {status: 'pending'}],
  ]) {
    await db.doc(path).set(patch);
    assert.equal(await recordBackgroundOpportunity('alice', 'bob'), false);
    await db.doc(path).delete();
  }
  for (const [path, patch, restore] of [
    ['publicProfiles/bob', {busyInMeetup: true}, {busyInMeetup: false}],
    ['users/alice/settings/matching', {businessOnly: true}, {businessOnly: false}],
    ['users/bob/settings/matching', {ageBracket: 'age55Plus'}, {ageBracket: 'all'}],
    ['users/bob/settings/matching', {partyScope: 'partyOnly'}, {partyScope: 'all'}],
    ['users/bob/backgroundPresence/current', {longitude: -74.1}, {longitude: -74}],
  ]) {
    await db.doc(path).update(patch);
    assert.equal(await recordBackgroundOpportunity('alice', 'bob'), false, JSON.stringify(patch));
    await db.doc(path).update(restore);
  }
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), true);
});

test('Travel needs fresh movement and accounts for uncertainty without issuing significant alerts', async () => {
  await pair();
  for (const uid of ['alice', 'bob']) await db.doc(`users/${uid}/settings/matching`).update({modeKind: 'travel'});
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), false);
  for (const uid of ['alice', 'bob']) await db.doc(`users/${uid}/backgroundPresence/current`).update({speedMps: 5});
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), true);
  assert.equal((await outbox('alice')).size, 0);
  await db.doc('users/bob/backgroundPresence/current').update({locationAt: at(Date.now() - 91 * 1000)});
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), false);
});

test('daily reservation is atomic across different peers and remains quiet while driving', async () => {
  await pair(); await person('carol', true);
  await db.doc('users/alice/settings/backgroundMatching').update({dailyAlertLimit: 1});
  await Promise.all([recordBackgroundOpportunity('alice', 'bob'), recordBackgroundOpportunity('alice', 'carol')]);
  assert.equal((await outbox('alice')).size, 1);
  await person('driver'); await person('passenger', true);
  await db.doc('users/driver/backgroundPresence/current').update({speedMps: 15});
  assert.equal(await recordBackgroundOpportunity('driver', 'passenger'), true);
  assert.equal((await outbox('driver')).size, 0);
  assert.equal((await outbox('passenger')).size, 0);
});

test('FCM attempts are at most once even after ambiguous delivery and contain no peer identity', async () => {
  await pair(); await recordBackgroundOpportunity('alice', 'bob');
  await db.doc('users/alice/deviceTokens/fake-emulator-token').set({valid: true});
  const alert = (await outbox('alice')).docs[0];
  let attempts = 0;
  const send = async message => {
    attempts++;
    assert.equal(message.data.type, 'significant_match');
    assert.equal(message.data.otherUid, undefined);
    assert.equal(JSON.stringify(message).includes('gardening'), false);
    throw new Error('Delivery result lost');
  };
  await assert.rejects(dispatchBackgroundAlert('alice', alert.id, send), /result lost/);
  await dispatchBackgroundAlert('alice', alert.id, send);
  assert.equal(attempts, 1);
});

test('queued delivery and opening revalidate opt-out, location, criteria, blocks and significance', async () => {
  await pair(); await recordBackgroundOpportunity('alice', 'bob');
  await db.doc('users/alice/deviceTokens/fake').set({valid: true});
  const alert = (await outbox('alice')).docs[0];
  const id = alert.data().opportunityId;
  for (const [path, patch, restore] of [
    ['users/bob/settings/backgroundMatching', {enabled: false}, {enabled: true}],
    ['users/bob/backgroundPresence/current', {longitude: -75}, {longitude: -74}],
    ['users/alice/settings/matching', {businessOnly: true}, {businessOnly: false}],
  ]) {
    await db.doc(path).update(patch);
    assert.deepEqual(await readBackgroundOpportunity('alice', id), {available: false});
    await alert.ref.update({state: 'pending'});
    await dispatchBackgroundAlert('alice', alert.id, async () => assert.fail('No notification allowed'));
    assert.equal((await alert.ref.get()).data().state, 'suppressed');
    await db.doc(path).update(restore);
  }
  await db.doc('users/bob/blocks/alice').set({});
  assert.deepEqual(await readBackgroundOpportunity('alice', id), {available: false});
  await db.doc('users/bob/blocks/alice').delete();
  await db.doc('publicProfiles/bob').set(profile(['cooking'], ['gardening']));
  await alert.ref.update({state: 'pending'});
  await dispatchBackgroundAlert('alice', alert.id, async () => assert.fail('No longer significant'));
  assert.equal((await alert.ref.get()).data().state, 'suppressed');
});

test('geographic scans find a significant peer, ignore far users and throttle repeat events', async () => {
  await pair(); await person('far', true);
  await db.doc('users/far/backgroundPresence/current').update({latitude: 41});
  await scanBackgroundMatches('alice');
  assert.equal((await db.collection('users/alice/backgroundOpportunities').get()).size, 1);
  const first = (await db.doc('users/alice/backgroundScanState/current').get()).data().scannedAt;
  await scanBackgroundMatches('alice');
  assert.ok(first.isEqual((await db.doc('users/alice/backgroundScanState/current').get()).data().scannedAt));
});

test('geographic scans wrap at the date line', async () => {
  await pair();
  await db.doc('users/alice/backgroundPresence/current').update({latitude: 0, longitude: 179.999});
  await db.doc('users/bob/backgroundPresence/current').update({latitude: 0, longitude: -179.999});
  await scanBackgroundMatches('alice');
  assert.equal((await db.collection('users/alice/backgroundOpportunities').get()).size, 1);
});


test('small user radii are never widened and quiet hours are rechecked at delivery', async () => {
  await pair();
  await db.doc('users/alice/settings/matching').update({radiusMiles: .1});
  // Even at one center, two 100-meter accuracy circles exceed this radius.
  assert.equal(await recordBackgroundOpportunity('alice', 'bob'), false);
  await db.doc('users/alice/settings/matching').update({radiusMiles: 2});
  await recordBackgroundOpportunity('alice', 'bob');
  const alert = (await outbox('alice')).docs[0];
  const utcMinutes = new Date().getUTCHours() * 60 + new Date().getUTCMinutes();
  let offset = 23 * 60 - utcMinutes;
  if (offset > 840) offset -= 1440;
  await db.doc('users/alice/settings/backgroundMatching').update({quietHoursEnabled: true});
  await db.doc('users/alice/backgroundPresence/current').update({utcOffsetMinutes: offset});
  await dispatchBackgroundAlert('alice', alert.id, async () => assert.fail('Quiet hours must suppress pending delivery'));
  assert.equal((await alert.ref.get()).data().state, 'suppressed');
});
