const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Party tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit'});
const db = admin.firestore();
const {issuePartyInPersonSession, closePartyInPersonSession, confirmPartyCode, connectionId, changePartyConnection, expirePartyConnections} = require('../lib/party_connections');
const {onPartyWrite} = require('../lib/lib/party');
const {createReferralSingleUseToken, finalizeReferralSingleUseToken} = require('../lib/referral_downloads');
const ts = ms => admin.firestore.Timestamp.fromMillis(ms);
const pair = () => db.doc(`partyConnections/${connectionId('alice', 'bob')}`);
beforeEach(async () => {
  const result = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method:'DELETE'});
  assert.equal(result.status, 200);
  await Promise.all(['alice', 'bob', 'mallory'].map(async uid => {
    await db.doc(`users/${uid}`).set({displayName: uid});
    await db.doc(`users/${uid}/presence/current`).set({geopoint: new admin.firestore.GeoPoint(40, -74),
      ts: ts(Date.now()), locationTs: ts(Date.now()), expiresAt: ts(Date.now() + 300000), accuracyMeters: 10, cached: false});
  }));
});
after(async () => admin.app().delete());
async function membership(expected) {
  for (const [uid, other] of [['alice','bob'], ['bob','alice']]) {
    const snap = await db.doc(`users/${uid}/party/${other}`).get();
    assert.equal(snap.exists, expected);
    if (expected) {
      assert.equal(snap.data().mutual, true);
      assert.equal(snap.data().metInPerson, true);
      assert.equal(snap.data().connectionId, connectionId(uid, other));
    }
  }
}
test('standing together, both users must enter the other code before Party membership exists', async () => {
  const a = await issuePartyInPersonSession('alice'), b = await issuePartyInPersonSession('bob');
  assert.match(a.code, /^[A-F0-9]{10}$/);
  assert.equal((await confirmPartyCode('alice', b.code.toLowerCase())).status, 'pending');
  await membership(false);
  await assert.rejects(changePartyConnection('bob', {action:'add', otherUid:'alice'}), /expired|no longer/);
  assert.equal((await confirmPartyCode('bob', a.code)).status, 'connected');
  await membership(true);
  assert.equal((await pair().get()).data().proof.kind, 'inPersonCode');
  assert.equal((await db.doc(`partyInPersonCodes/${a.code}`).get()).exists, false);
  assert.equal((await db.doc(`partyInPersonCodes/${b.code}`).get()).exists, false);
});
test('no pending completed-meetup receipt means arbitrary remote Party adds fail', async () => {
  await assert.rejects(changePartyConnection('alice', {action:'add', otherUid:'bob'}), /expired|no longer/);
  await membership(false);
});
test('remote, cached, stale or future locations cannot establish Party', async () => {
  const a = await issuePartyInPersonSession('alice'), b = await issuePartyInPersonSession('bob');
  for (const patch of [
    {geopoint: new admin.firestore.GeoPoint(41, -74)},
    {geopoint: new admin.firestore.GeoPoint(40, -74), cached:true},
    {cached:false, locationTs:ts(Date.now()-300001)},
    {locationTs:ts(Date.now()+60000)},
  ]) {
    await db.doc('users/bob/presence/current').update(patch);
    await assert.rejects(confirmPartyCode('alice', b.code), /Stand together|fresh location/);
    await membership(false);
  }
  assert.equal((await db.doc(`partyInPersonCodes/${a.code}`).get()).exists, true);
});
test('expired or revoked codes cannot pair; a replaced session cannot reuse older consent', async () => {
  const a = await issuePartyInPersonSession('alice'), b = await issuePartyInPersonSession('bob');
  await confirmPartyCode('alice', b.code);
  await closePartyInPersonSession('alice');
  await assert.rejects(confirmPartyCode('bob', a.code), /current code/);
  await db.doc('partyInPersonSessions/alice').update({createdAt:ts(Date.now()-16000)});
  const replacement = await issuePartyInPersonSession('alice');
  assert.equal((await confirmPartyCode('bob', replacement.code)).status, 'pending');
  await membership(false);
  await db.doc('partyInPersonSessions/bob').update({expiresAt:ts(Date.now()-1)});
  await assert.rejects(confirmPartyCode('alice', b.code), /expired/);
  await membership(false);
});
test('a block or deletion arriving between code confirmations prevents membership', async () => {
  const a = await issuePartyInPersonSession('alice'), b = await issuePartyInPersonSession('bob');
  await confirmPartyCode('alice', b.code);
  await db.doc('users/alice/blocks/bob').set({createdAt:ts(Date.now())});
  await assert.rejects(confirmPartyCode('bob', a.code), /unavailable/);
  await db.doc('users/alice/blocks/bob').delete();
  await db.doc('accountDeletions/alice').set({createdAt:ts(Date.now())});
  await assert.rejects(confirmPartyCode('bob', a.code), /unavailable/);
  await membership(false);
});
test('failed code guesses consume the server rate limit', async () => {
  for (let i = 0; i < 10; i++) await assert.rejects(confirmPartyCode('alice', '0000000000'), /current code/);
  await assert.rejects(confirmPartyCode('alice', '0000000000'), /Too many/);
  assert.equal((await db.doc('partyInPersonRateLimits/alice').get()).data().attempts, 10);
});
test('the sweep removes expired exchange codes while preserving a current session', async () => {
  const a = await issuePartyInPersonSession('alice'), b = await issuePartyInPersonSession('bob');
  await db.doc('partyInPersonSessions/alice').update({expiresAt:ts(Date.now()-1)});
  await expirePartyConnections();
  assert.equal((await db.doc('partyInPersonSessions/alice').get()).exists, false);
  assert.equal((await db.doc(`partyInPersonCodes/${a.code}`).get()).exists, false);
  assert.equal((await db.doc(`partyInPersonCodes/${b.code}`).get()).exists, true);
});
test('arbitrary reciprocal legacy membership never promotes itself into the trusted graph', async () => {
  await db.doc('users/alice/party/bob').set({uid:'bob', mutual:true});
  await db.doc('users/bob/party/alice').set({uid:'alice', mutual:true});
  await onPartyWrite.run({params:{uid:'alice',friendUid:'bob'}});
  await membership(false);
});
test('legacy server-created completed meetup receipts can upgrade their projections safely', async () => {
  await db.doc('users/alice/party/bob').set({uid:'bob', mutual:true});
  await db.doc('users/bob/party/alice').set({uid:'alice', mutual:true});
  await db.doc('meetups/proven').set({aUid:'alice',bUid:'bob',status:'completed'});
  await pair().set({members:['alice','bob'],status:'connected', decisions:{alice:'add',bob:'add'},chatId:'proven'});
  await onPartyWrite.run({params:{uid:'alice',friendUid:'bob'}});
  await membership(true);
  assert.equal((await pair().get()).data().proof.kind, 'completedMeetup');
});
function response() {
  return {statusCode:0, payload:null, status(code){this.statusCode=code;return this;}, json(payload){this.payload=payload;}};
}
async function authedRequest(uid, handler, body) {
  const auth = admin.auth(), previous = auth.verifyIdToken;
  auth.verifyIdToken = async () => ({uid});
  try {
    const result = response();
    await handler({method:'POST', body, get:name => name.toLowerCase()==='authorization' ? 'Bearer test' : ''}, result);
    return result;
  } finally {auth.verifyIdToken = previous;}
}
async function qrToken(extra = {}) {
  const issued = await authedRequest('alice', createReferralSingleUseToken,
    {latitude:40, longitude:-74, accuracyM:10, inPersonQrRequested:true, partyConsent:true, ...extra});
  assert.equal(issued.statusCode, 200);
  return issued.payload;
}
test('verified single-use referral QR joins both Parties only with explicit consent from both people', async () => {
  await db.doc('users/alice').update({root_referrer:'root'});
  const invitation = await qrToken();
  assert.equal(new URL(invitation.qrLink).searchParams.get('party'), '1');
  const joined = await authedRequest('bob', finalizeReferralSingleUseToken,
    {token:invitation.token, latitude:40, longitude:-74, accuracyM:10, partyConsent:true});
  assert.equal(joined.statusCode, 200);
  assert.equal(joined.payload.partyJoined, true);
  assert.equal((await db.doc('users/bob').get()).data().root_referrer, 'root');
  await membership(true);
  assert.equal((await pair().get()).data().proof.kind, 'referralQr');
  const replay = await authedRequest('bob', finalizeReferralSingleUseToken, {token:invitation.token});
  assert.equal(replay.payload.partyJoined, true);
  const hijack = await authedRequest('mallory', finalizeReferralSingleUseToken, {token:invitation.token});
  assert.equal(hijack.statusCode, 409);
});
test('plain referral tokens, declined Party consent and remote QR recipients grant no Party membership', async () => {
  for (const [inviter, invitee] of [
    [{partyConsent:false}, {partyConsent:true}],
    [{}, {partyConsent:false}],
    [{}, {partyConsent:true, latitude:41}],
  ]) {
    const invitation = await qrToken(inviter);
    const linked = await authedRequest('bob', finalizeReferralSingleUseToken,
      {token:invitation.token, latitude:40, longitude:-74, accuracyM:10, ...invitee});
    if (invitee.latitude === 41) {
      assert.equal(linked.statusCode, 409);
      assert.equal(linked.payload.error, 'in_person_verification_required');
      assert.equal((await db.doc(`referralSingleUseTokens/${invitation.token}`).get()).data().status, 'new');
    } else {
      assert.equal(linked.statusCode, 200);
      assert.equal(linked.payload.partyJoined, false);
    }
    await membership(false);
  }
});

test('new accounts unlock only with a fresh in-person QR, without consuming failed remote scans', async () => {
  await db.doc('users/bob').update({referralTrustRequired: true, referralInPersonVerified: false});
  const invitation = await qrToken({partyConsent: false});
  for (const body of [{}, {latitude: 41, longitude: -74, accuracyM: 10}, {latitude: 40, longitude: -74, accuracyM: 150}]) {
    const failed = await authedRequest('bob', finalizeReferralSingleUseToken, {token: invitation.token, ...body});
    assert.equal(failed.statusCode, 409);
    assert.equal((await db.doc('users/bob').get()).data().referralInPersonVerified, false);
    assert.equal((await db.doc('referralAttributions/bob').get()).exists, false);
    assert.equal((await db.doc(`referralSingleUseTokens/${invitation.token}`).get()).data().status, 'new');
  }
  const accepted = await authedRequest('bob', finalizeReferralSingleUseToken,
    {token: invitation.token, latitude: 40, longitude: -74, accuracyM: 10});
  assert.equal(accepted.statusCode, 200);
  assert.equal((await db.doc('users/bob').get()).data().referralInPersonVerified, true);
  assert.equal((await db.doc('referralAttributions/bob').get()).data().inPersonVerified, true);
  await membership(false);
});

test('unverified users cannot recruit and all QR creation needs an accurate location', async () => {
  await db.doc('users/alice').update({referralTrustRequired: true, referralInPersonVerified: false});
  assert.equal((await authedRequest('alice', createReferralSingleUseToken,
    {latitude: 40, longitude: -74, accuracyM: 10})).statusCode, 409);
  await db.doc('users/alice').update({referralInPersonVerified: true});
  assert.equal((await authedRequest('alice', createReferralSingleUseToken, {})).statusCode, 400);
  assert.equal((await authedRequest('alice', createReferralSingleUseToken,
    {latitude: 40, longitude: -74, accuracyM: 150})).statusCode, 400);
  assert.equal((await db.collection('referralSingleUseTokens').get()).size, 0);
});

test('HTTP referral APIs explicitly distinguish suspension from exhausted request budgets', async () => {
  await db.doc('functionRateLimits/alice').set({minute: Math.floor(Date.now() / 60000), count: 120});
  const limited = await authedRequest('alice', createReferralSingleUseToken,
    {latitude: 40, longitude: -74, accuracyM: 10});
  assert.equal(limited.statusCode, 429);
  assert.equal(limited.payload.error, 'resource_exhausted');
  await db.doc('accountEnforcements/alice').set({status: 'suspended'});
  const suspended = await authedRequest('alice', createReferralSingleUseToken,
    {latitude: 40, longitude: -74, accuracyM: 10});
  assert.equal(suspended.statusCode, 403);
  assert.equal(suspended.payload.error, 'permission_denied');
  assert.equal((await db.collection('referralSingleUseTokens').get()).size, 0);
});
