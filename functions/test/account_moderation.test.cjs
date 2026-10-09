const {beforeEach, afterEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Moderation tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit', storageBucket: 'demo-prox-audit.appspot.com'});
const db = admin.firestore();
const {moderateAccount, getAccountModerationStatus} = require('../lib/account_moderation');
const {assertAccountAccess, claimCallableRequest, onCall, onRecoveryCall, CALLS_PER_MINUTE} = require('../lib/lib/active_callable');
let original;
let calls;
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(response.status, 200);
  calls = [];
  const auth = admin.auth();
  original = {getUser: auth.getUser, updateUser: auth.updateUser, revokeRefreshTokens: auth.revokeRefreshTokens, deleteUser: auth.deleteUser};
  auth.getUser = async uid => ({uid, customClaims: uid === 'other-admin' ? {admin: true} : {}});
  auth.updateUser = async (uid, data) => {calls.push(['update', uid, data]); return {uid};};
  auth.revokeRefreshTokens = async uid => {calls.push(['revoke', uid]);};
  auth.deleteUser = async uid => {calls.push(['delete', uid]);};
  await db.doc('users/admin').set({});
  await db.doc('users/target').set({displayName: 'Target'});
});
afterEach(() => Object.assign(admin.auth(), original));
after(async () => admin.app().delete());
const input = (action = 'suspend', requestId = 'moderation_request_001') => ({
  targetUid: 'target', action, reason: 'Reported referral farming', requestId, expectedUid: 'admin',
});
const request = data => ({auth: {uid: 'admin', token: {admin: true}}, data});

test('moderation requires a real administrator, stable request ID, reason and correct account', async () => {
  await assert.rejects(moderateAccount.run({data: input()}), /Sign in/);
  await assert.rejects(moderateAccount.run({auth: {uid: 'target', token: {}}, data: input()}), /administrator/);
  await assert.rejects(moderateAccount.run(request({...input(), expectedUid: 'other'})), /changed/);
  await assert.rejects(moderateAccount.run(request({...input(), targetUid: 'admin'})), /different target/);
  await assert.rejects(moderateAccount.run(request({...input(), targetUid: 'other-admin'})), /privileged recovery/);
  await assert.rejects(moderateAccount.run(request({...input(), reason: 'bad'})), /reason/);
  assert.equal((await db.collection('accountEnforcements').get()).size, 0);
});

test('suspension immediately blocks cached callable credentials and survives idempotent retries', async () => {
  const result = await moderateAccount.run(request(input()));
  assert.equal(result.status, 'suspended');
  assert.equal((await db.doc('users/target').get()).data().disabled, true);
  await assert.rejects(assertAccountAccess('target'), /suspended/);
  const guarded = onCall(async () => ({ok: true}));
  await assert.rejects(guarded.run({auth: {uid: 'target', token: {}}, data: {}}), /restricted/);
  const recovery = onRecoveryCall({}, async () => ({support: true}));
  assert.equal((await recovery.run({auth: {uid: 'target', token: {}}, data: {}})).support, true);
  assert.equal((await moderateAccount.run(request(input()))).replayed, true);
  assert.equal(calls.filter(call => call[0] === 'revoke').length, 1);
  await assert.rejects(moderateAccount.run(request({...input(), reason: 'Different evidence'})), /already used/);
  assert.equal((await db.collection('accountModerationAudit').get()).size, 1);
});

test('administrator can restore a suspended account but never restore a deleted one', async () => {
  await db.doc('users/target').update({status: 'banned'});
  await moderateAccount.run(request(input()));
  await moderateAccount.run(request(input('restore', 'moderation_request_002')));
  await assertAccountAccess('target');
  assert.equal((await db.doc('users/target').get()).data().disabled, false);
  assert.equal((await db.doc('users/target').get()).data().status, 'active');
  await db.doc('accountDeletions/target').set({status: 'processing'});
  await assert.rejects(moderateAccount.run(request(input('restore', 'moderation_request_003'))), /cannot be restored/);
});

test('Auth failures leave access closed, with explicit failed audit and safe same-ID recovery', async () => {
  admin.auth().updateUser = async () => {throw new Error('simulated Auth outage');};
  await assert.rejects(moderateAccount.run(request(input())), /incomplete/);
  await assert.rejects(assertAccountAccess('target'), /suspended/);
  assert.equal((await db.collection('accountModerationAudit').get()).docs[0].data().phase, 'failed');
  const recovered = await getAccountModerationStatus.run(request({targetUid: 'target', expectedUid: 'admin'}));
  assert.deepEqual(recovered.pending, input());
  await assert.rejects(getAccountModerationStatus.run({
    auth: {uid: 'other-admin', token: {admin: true}}, data: {targetUid: 'target', expectedUid: 'other-admin'},
  }), /Another administrator/);
  admin.auth().updateUser = async uid => ({uid});
  await moderateAccount.run(request(input()));
  assert.equal((await db.collection('accountModerationAudit').get()).docs[0].data().phase, 'complete');
});

test('admin deletion erases account data, disables Auth, preserves enforcement and moderation receipts', async () => {
  await db.doc('users/target/referralMentor/current').set({mentorUid: 'admin'});
  await moderateAccount.run(request(input('delete')));
  assert.equal((await db.doc('users/target').get()).exists, false);
  assert.equal((await db.doc('accountEnforcements/target').get()).data().status, 'deleted');
  assert.equal((await db.doc('accountDeletions/target').get()).data().status, 'complete');
  assert.equal((await db.collection('accountModerationAudit').get()).size, 1);
  assert.equal(calls.some(call => call[0] === 'delete'), true);
  assert.equal((await moderateAccount.run(request(input('delete')))).replayed, true);
});

test('callable rate limits are shared, transactional, bounded, and cannot be bypassed by concurrency', async ({mock}) => {
  const now = Date.now();
  mock.method(Date, 'now', () => now);
  await db.doc('functionRateLimits/target').set({minute: Math.floor(Date.now() / 60000), count: CALLS_PER_MINUTE - 1});
  const results = await Promise.allSettled([claimCallableRequest('target'), claimCallableRequest('target')]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal(results.find(result => result.status === 'rejected').reason.code, 'resource-exhausted');
  await db.doc('functionRateLimits/target').update({minute: Math.floor(Date.now() / 60000) - 1});
  await claimCallableRequest('target');
  assert.equal((await db.doc('functionRateLimits/target').get()).data().count, 1);
});

test('new users cannot bypass QR trust through unrelated callable APIs, while support recovery remains available', async () => {
  await db.doc('users/target').update({referralTrustRequired: true, referralInPersonVerified: false});
  const active = onCall(async () => ({purchased: true}));
  const recovery = onRecoveryCall({}, async () => ({submitted: true}));
  await assert.rejects(active.run({auth: {uid: 'target', token: {}}, data: {}}), /in person/);
  assert.equal((await recovery.run({auth: {uid: 'target', token: {}}, data: {}})).submitted, true);
  await db.doc('users/target').update({referralInPersonVerified: true});
  assert.equal((await active.run({auth: {uid: 'target', token: {}}, data: {}})).purchased, true);
});
