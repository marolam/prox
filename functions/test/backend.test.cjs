const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Backend tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit', storageBucket: 'demo-prox-audit.appspot.com'});
const db = admin.firestore();
const {applyExternalCheckoutStatus, mapSquareEventToStatus, verifySquareWebhookSignature} = require('../lib/external_payments');
const {reconcileSquareLifecycle} = require('../lib/payment_reconciliation');
const {purchasePointsEntitlement, purchaseWithPoints} = require('../lib/points_purchases');
const {claimReward} = require('../lib/verified_rewards');
const {eraseUserData, deleteMyAccount} = require('../lib/account_lifecycle');
const {recordCompletedMeetup} = require('../lib/meetup_accounting');
const {publicProfile, publicProfilesEqual, syncPublicProfile} = require('../lib/public_profiles');
const {linkReferralCode, referralApkDownload} = require('../lib/referral_downloads');
const {onPartyWrite} = require('../lib/lib/party');
const {updateBusinessMode, setBusinessModeActive} = require('../lib/business_mode');
const {syncPresenceCoordinates} = require('../lib/presence_projection');
const {onAuthCreate} = require('../lib/on_auth_create');
const {onInPartyMatchMetrics} = require('../lib/lib/in_party_match_metrics');
const {syncReferralMentor, sendMentorNudge, deliverMentorNudge, sendReferralMentorNudge, MENTOR_NUDGE_COOLDOWN_MS} = require('../lib/referral_mentors');
const {reconcileVerifiedPartyConnection} = require('../lib/lib/party');
const {trustedPartyEdge} = require('../lib/lib/matching_scope_policy');
beforeEach(async () => {
  const result = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(result.status, 200);
});
after(async () => { await admin.app().delete(); });

const {endSafetySession, recordMeetupOutcome} = require('../lib/safety_sessions');
const {classifyUnresolvedOutcome, closeExpiredMeetup, sweepExpiredMeetups} = require('../lib/lib/meetup_auto_close');
const {onMeetupTransitionGuard} = require('../lib/lib/match_dashboard_enforcement');
const {onMeetupInteractionLockProjection} = require('../lib/lib/match_dashboard_enforcement');

const REFERRAL_ENV_KEYS = [
  'PROX_REFERRAL_ANDROID_URL',
  'PROX_PUBLIC_APK_URL',
  'PROX_PUBLIC_APK_FALLBACK_URL',
  'PROX_REFERRAL_IOS_URL',
  'PROX_IOS_UPDATE_URL',
  'PROX_IOS_UPDATE_FALLBACK_URL',
  'PROX_IOS_FALLBACK_URL',
];

async function withReferralEnv(overrides, run) {
  const prior = {};
  for (const key of REFERRAL_ENV_KEYS) {
    prior[key] = process.env[key];
  }
  try {
    for (const key of REFERRAL_ENV_KEYS) {
      const next = overrides[key];
      if (typeof next === 'string') process.env[key] = next;
      else delete process.env[key];
    }
    await run();
  } finally {
    for (const key of REFERRAL_ENV_KEYS) {
      if (typeof prior[key] === 'string') process.env[key] = prior[key];
      else delete process.env[key];
    }
  }
}

function makeReferralReq({method = 'GET', query = {}, headers = {}, body = {}} = {}) {
  const normalizedHeaders = {};
  for (const [key, value] of Object.entries(headers)) {
    normalizedHeaders[String(key).toLowerCase()] = String(value);
  }
  return {
    method,
    query,
    body,
    get(name) {
      return normalizedHeaders[String(name).toLowerCase()];
    },
  };
}

function makeReferralRes() {
  const res = {
    statusCode: 200,
    jsonBody: null,
    headers: {},
    redirectStatus: 0,
    redirectUrl: '',
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.jsonBody = payload;
    },
    set(name, value) {
      this.headers[String(name)] = String(value);
    },
    redirect(code, url) {
      this.redirectStatus = code;
      this.redirectUrl = url;
    },
  };
  return res;
}

async function mentorFixture(complete = true, autoAdd = true, inPersonVerified = true) {
  await db.doc('users/mentor').set({displayName: 'Mentor'});
  await db.doc('users/invitee').set({referrer: 'mentor', displayName: 'New user',
    ...(complete ? {selfieUrl: 'https://example.test/selfie.jpg',
      keywords: {'Searching For': ['gardening'], 'Can Provide': ['cooking']}} : {})});
  await db.doc('referralAttributions/invitee').set({referrerUid: 'mentor', inPersonVerified, token: 'T-ABCDEF123456789012'});
  await db.doc('users/mentor/referrals/invitee').set({uid: 'invitee', meetupsCompleted: 0, rewardCredited: false, partyInPersonQrRequested: autoAdd});
  await db.doc('users/mentor/settings/referral').set({autoAddMentorToParty: autoAdd});
}

test('direct referrer defaults to mentor and verified QR adds a profile-ready trusted Party pair', async () => {
  await mentorFixture(false);
  await syncReferralMentor('invitee');
  assert.equal((await db.doc('users/invitee/referralMentor/current').get()).data().mentorUid, 'mentor');
  assert.equal((await db.doc('users/invitee/party/mentor').get()).exists, false);
  await db.doc('users/invitee').update({selfieUrl: 'https://example.test/selfie.jpg',
    keywords: {'Searching For': ['gardening'], 'Can Provide': ['cooking']}});
  await Promise.all([syncReferralMentor('invitee'), syncReferralMentor('invitee')]);
  const forward = (await db.doc('users/invitee/party/mentor').get()).data();
  const reverse = (await db.doc('users/mentor/party/invitee').get()).data();
  const connection = (await db.doc(`partyConnections/${connectionId('mentor', 'invitee')}`).get()).data();
  assert.equal(forward.metInPerson, true);
  assert.equal(reverse.metInPerson, true);
  assert.equal(connection.proof.kind, 'referralQr');
  assert.equal(trustedPartyEdge('invitee', 'mentor', forward, reverse, connection), true);
  assert.equal(await reconcileVerifiedPartyConnection('invitee', 'mentor'), true);
  assert.equal((await db.doc('users/invitee/party/mentor').get()).data().metInPerson, true);
  const before = (await db.doc('users/mentor/mentorReferrals/invitee').get()).updateTime;
  await syncReferralMentor('invitee');
  assert.equal((await db.doc('users/mentor/mentorReferrals/invitee').get()).updateTime.isEqual(before), true);
});

test('remote attribution never adds a mentor Party contact or establishes trust', async () => {
  await mentorFixture(true, true, false);
  await syncReferralMentor('invitee');
  assert.equal((await db.doc('users/invitee/party/mentor').get()).exists, false);
  assert.equal((await db.doc('users/invitee/referralMentor/current').get()).data().inPersonVerified, false);
});

test('a new account cannot bypass mandatory trust with an ordinary referral code', async () => {
  await db.doc('users/newbie').set({referralTrustRequired: true, referralInPersonVerified: false});
  await db.doc('users/mentor').set({});
  await db.doc('referralCodes/INV123').set({referrerUid: 'mentor', active: true});
  await assert.rejects(linkReferralCode.run({auth: {uid: 'newbie'}, data: {code: 'INV123'}}), /in person/);
  assert.equal((await db.doc('referralAttributions/newbie').get()).exists, false);
});

test('mentor summaries show only verified activity and removing the contact never automatically readds it', async () => {
  await mentorFixture();
  await syncReferralMentor('invitee');
  await db.doc('users/peer').set({});
  await db.doc('meetups/real').set({aUid: 'invitee', bUid: 'peer', status: 'completed',
    aArrived: true, bArrived: true, completedAt: admin.firestore.Timestamp.now()});
  await recordCompletedMeetup('real', 'invitee');
  await syncReferralMentor('invitee');
  const summary = (await db.doc('users/mentor/mentorReferrals/invitee').get()).data();
  assert.equal(summary.role, 'mentor');
  assert.equal(summary.profileComplete, true);
  assert.equal(summary.meetupsCompleted, 1);
  assert.equal(summary.meetupId, undefined);
  assert.equal(summary.location, undefined);
  await changePartyConnection('invitee', {otherUid: 'mentor', action: 'remove'});
  await syncReferralMentor('invitee');
  assert.equal((await db.doc('users/invitee/party/mentor').get()).exists, false);
  assert.equal((await db.doc('users/invitee/referralMentor/current').get()).data().partyAdded, false);
  await db.doc('users/invitee/blocks/mentor').set({uid: 'mentor'});
  await syncReferralMentor('invitee');
  assert.equal((await db.doc('users/mentor/mentorReferrals/invitee').get()).exists, false);
  assert.equal((await db.doc('users/invitee/referralMentor/current').get()).exists, false);
});

test('Party toggle off keeps the mentor relationship without adding contacts or claiming in-person verification', async () => {
  await mentorFixture(true, false);
  await syncReferralMentor('invitee');
  assert.equal((await db.doc('users/invitee/referralMentor/current').get()).data().mentorUid, 'mentor');
  assert.equal((await db.doc('users/invitee/party/mentor').get()).exists, false);
  assert.equal((await db.doc('users/mentor/referrals/invitee').get()).data().inPersonVerified, undefined);
});

test('only direct mentors can nudge; concurrent retries deduplicate and both reminder kinds share a cooldown', async () => {
  await mentorFixture();
  await syncReferralMentor('invitee');
  const request = {inviteeUid: 'invitee', requestId: 'mentor_nudge_request_001', kind: 'use_app'};
  await assert.rejects(sendMentorNudge('outsider', request), /direct referrer/);
  await assert.rejects(sendReferralMentorNudge.run({data: request}), /Sign in/);
  await assert.rejects(sendReferralMentorNudge.run({auth: {uid: 'mentor'}, data: {...request, expectedUid: 'other'}}), /account changed/);
  const results = await Promise.all([sendMentorNudge('mentor', request), sendMentorNudge('mentor', request)]);
  assert.equal(results.filter(r => !r.replayed).length, 1);
  assert.equal((await db.collection('referralMentorNudges').get()).size, 1);
  await assert.rejects(sendMentorNudge('mentor', {...request, requestId: 'mentor_nudge_request_002', kind: 'support'}), /12 hours/);
  await db.doc('users/mentor/mentorReferrals/invitee').update({
    lastReminderAt: admin.firestore.Timestamp.fromMillis(Date.now() - MENTOR_NUDGE_COOLDOWN_MS - 1)});
  await sendMentorNudge('mentor', {...request, requestId: 'mentor_nudge_request_002', kind: 'support'});
  assert.match((await db.doc('users/invitee/referralMentor/current').get()).data().lastNudge, /support/);
  await db.doc('users/mentor/blocks/invitee').set({uid: 'invitee'});
  await assert.rejects(sendMentorNudge('mentor', request), /direct referrer/);
});

test('mentor nudges persist without push devices and delivery rechecks blocks and deletion', async () => {
  await mentorFixture();
  await syncReferralMentor('invitee');
  const request = {inviteeUid: 'invitee', requestId: 'mentor_nudge_request_001', kind: 'use_app'};
  await sendMentorNudge('mentor', request);
  await deliverMentorNudge('mentor_mentor_nudge_request_001');
  assert.equal((await db.doc('referralMentorNudges/mentor_mentor_nudge_request_001').get()).data().status, 'no_devices');
  assert.match((await db.doc('users/invitee/referralMentor/current').get()).data().lastNudge, /mentor/);
  await db.doc('users/mentor/mentorReferrals/invitee').update({lastReminderAt: admin.firestore.Timestamp.fromMillis(1)});
  await sendMentorNudge('mentor', {...request, requestId: 'mentor_nudge_request_002'});
  await db.doc('accountDeletions/invitee').set({status: 'processing'});
  await deliverMentorNudge('mentor_mentor_nudge_request_002');
  assert.equal((await db.doc('referralMentorNudges/mentor_mentor_nudge_request_002').get()).data().status, 'cancelled');
  await assert.rejects(sendMentorNudge('mentor', request), /direct referrer/);
});

test('delayed meetup lock projection cannot recreate a deleted account', async () => {
  await db.doc('accountDeletions/alice').set({status: 'complete'});
  await db.doc('users/bob').set({});
  const meetup = db.doc('meetups/deleted-user');
  await meetup.set({aUid: 'alice', bUid: 'bob', status: 'live'});
  const after = await meetup.get();
  await onMeetupInteractionLockProjection.run({before: {exists: false}, after}, {});
  assert.equal((await db.doc('users/alice').get()).exists, false);
  assert.equal((await db.doc('users/alice/presence/current').get()).exists, false);
  assert.equal((await db.doc('users/bob').get()).data().interactionLock.busyInMeetup, true);
});

async function safetyFixture(status = 'live') {
  await db.doc('users/alice').set({});
  await db.doc('users/bob').set({});
  await db.doc('chats/safe').set({participants: ['alice', 'bob'], chatGate: {status: 'accepted'}});
  await db.doc('meetups/safe').set({aUid: 'alice', bUid: 'bob', status,
    requestedAt: admin.firestore.Timestamp.fromMillis(1000),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000), aArrived: false, bArrived: false});
}

test('safety exit authenticates membership and atomically ends meetup and chat for either participant', async () => {
  await safetyFixture();
  await assert.rejects(endSafetySession('', {chatId: 'safe', endChat: true}), /Sign in/);
  await assert.rejects(endSafetySession('mallory', {chatId: 'safe', endChat: true}), /Only participants/);
  await endSafetySession('bob', {chatId: 'safe', endChat: true});
  assert.equal((await db.doc('meetups/safe').get()).data().status, 'cancelled');
  const first = (await db.doc('chats/safe').get()).data().closedAt;
  await endSafetySession('bob', {chatId: 'safe', endChat: true});
  assert.ok(first.isEqual((await db.doc('chats/safe').get()).data().closedAt));
  assert.equal((await db.doc('users/bob/stats/trust').get()).exists, false);
});

test('meetup-only cancellation preserves chat and completion is never rewritten by a safety exit', async () => {
  await safetyFixture();
  await endSafetySession('alice', {chatId: 'safe', endChat: false});
  assert.equal((await db.doc('chats/safe').get()).data().closedAt, undefined);
  await db.doc('meetups/safe').update({status: 'completed'});
  await endSafetySession('alice', {chatId: 'safe', endChat: true});
  assert.equal((await db.doc('meetups/safe').get()).data().status, 'completed');
});

test('a group safety exit removes only the caller and transfers management when needed', async () => {
  await db.doc('chats/group').set({participants: ['alice', 'bob', 'carol'], isGroup: true, moderatorUid: 'alice', ownerUid: 'alice'});
  await endSafetySession('alice', {chatId: 'group', endChat: true});
  const group = (await db.doc('chats/group').get()).data();
  assert.deepEqual(group.participants, ['bob', 'carol']);
  assert.equal(group.closedAt, undefined);
  assert.equal(group.moderatorUid, 'bob');
});

test('expiry respects the deadline, preserves terminal outcomes, and records unfinished sessions', async () => {
  await safetyFixture('accepted');
  const ref = db.doc('meetups/safe');
  await ref.update({expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000)});
  assert.equal(await closeExpiredMeetup(ref), false);
  await ref.update({expiresAt: admin.firestore.Timestamp.fromMillis(0)});
  assert.equal(await closeExpiredMeetup(ref), true);
  assert.equal((await ref.get()).data().outcome, 'unfinished');
  assert.equal(await closeExpiredMeetup(ref), false);
  await ref.update({status: 'cancelled'});
  assert.equal(await closeExpiredMeetup(ref), false);
});

test('expiry completes both saved arrivals and concurrent cancellation remains terminal', async () => {
  await safetyFixture();
  const ref = db.doc('meetups/safe');
  await ref.update({aArrived: true, bArrived: true});
  await Promise.all([closeExpiredMeetup(ref), endSafetySession('alice', {chatId: 'safe', endChat: true})]);
  assert.ok(['cancelled', 'completed'].includes((await ref.get()).data().status));
  assert.equal(await closeExpiredMeetup(ref), false);
});

test('expiry paginates beyond a full page of unexpired meetups', async () => {
  const batch = db.batch();
  for (let i = 0; i < 301; i++) batch.set(db.doc(`meetups/a${String(i).padStart(3, '0')}`), {status: 'live', expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 3600000)});
  batch.set(db.doc('meetups/zexpired'), {status: 'live', expiresAt: admin.firestore.Timestamp.fromMillis(0)});
  await batch.commit();
  assert.equal(await sweepExpiredMeetups(), 1);
  assert.equal((await db.doc('meetups/zexpired').get()).data().status, 'auto_closed');
});

test('outcome receipts are idempotent across cleanup and omit peer identity and safety details', async () => {
  await safetyFixture();
  const data = {...(await db.doc('meetups/safe').get()).data(), status: 'cancelled'};
  await Promise.all([recordMeetupOutcome('safe', data, admin.firestore.Timestamp.now()), recordMeetupOutcome('safe', data, admin.firestore.Timestamp.now())]);
  const receipts = await db.collection('users/alice/meetupOutcomes').get();
  assert.equal(receipts.size, 1);
  assert.deepEqual(Object.keys(receipts.docs[0].data()).sort(), ['outcome', 'recordedAt']);
  assert.equal(receipts.docs[0].data().outcome, 'cancelled');
});

test('transition guard accepts cancellation and ignores stale events after a later write', async () => {
  await safetyFixture();
  const ref = db.doc('meetups/safe');
  const before = await ref.get();
  await endSafetySession('alice', {chatId: 'safe', endChat: false});
  const after = await ref.get();
  await onMeetupTransitionGuard.run({before, after}, {params: {meetupId: 'safe'}});
  assert.equal((await ref.get()).data().status, 'cancelled');
  await ref.update({status: 'accepted'});
  const invalid = await ref.get();
  await ref.update({status: 'cancelled'});
  await onMeetupTransitionGuard.run({before: after, after: invalid}, {params: {meetupId: 'safe'}});
  assert.equal((await ref.get()).data().status, 'cancelled');
});

test('strict progression guard rolls back a requested->live skip when strict step metadata is present', async () => {
  await safetyFixture('requested');
  const ref = db.doc('meetups/safe');
  await ref.update({currentStep: 'requested_waiting_accept', stepDeadlineAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000)});
  const before = await ref.get();
  await ref.update({status: 'live', currentStep: 'verify_and_confirm_arrival'});
  const after = await ref.get();
  await onMeetupTransitionGuard.run({before, after}, {params: {meetupId: 'safe'}});
  const rolledBack = (await ref.get()).data();
  assert.equal(rolledBack.status, 'requested');
  assert.equal(rolledBack.currentStep, 'requested_waiting_accept');
  assert.equal(rolledBack.statusPolicy.rollbackReason, 'invalid_meetup_transition');
});

test('cancel-by-request requires mutual handshake while preserving legacy safety cancellation path', async () => {
  await safetyFixture('live');
  const ref = db.doc('meetups/safe');

  const before = await ref.get();
  await ref.update({status: 'cancelled', cancelHandshakeByUid: {
    alice: {requestId: 'alice-only', requestedAt: admin.firestore.Timestamp.now()},
  }});
  const partial = await ref.get();
  await onMeetupTransitionGuard.run({before, after: partial}, {params: {meetupId: 'safe'}});
  assert.equal((await ref.get()).data().status, 'live');

  const beforeLegacyBoolean = await ref.get();
  await ref.update({status: 'cancelled', cancelRequestedByA: true, cancelRequestedByB: true});
  const legacyBoolean = await ref.get();
  await onMeetupTransitionGuard.run({before: beforeLegacyBoolean, after: legacyBoolean}, {params: {meetupId: 'safe'}});
  assert.equal((await ref.get()).data().status, 'live');

  const beforeMutual = await ref.get();
  await ref.update({status: 'cancelled', cancelHandshakeByUid: {
    alice: {requestId: 'alice-confirm', requestedAt: admin.firestore.Timestamp.now()},
    bob: {requestId: 'bob-confirm', requestedAt: admin.firestore.Timestamp.now()},
  }});
  const mutual = await ref.get();
  await onMeetupTransitionGuard.run({before: beforeMutual, after: mutual}, {params: {meetupId: 'safe'}});
  assert.equal((await ref.get()).data().status, 'cancelled');

  await safetyFixture('live');
  const safetyRef = db.doc('meetups/safe');
  const beforeSafety = await safetyRef.get();
  await safetyRef.update({status: 'cancelled', outcome: 'cancelled', cancelledAt: admin.firestore.Timestamp.now(), closedAt: admin.firestore.Timestamp.now()});
  const afterSafety = await safetyRef.get();
  await onMeetupTransitionGuard.run({before: beforeSafety, after: afterSafety}, {params: {meetupId: 'safe'}});
  assert.equal((await safetyRef.get()).data().status, 'cancelled');
});

test('timeout outcome classification distinguishes unanswered, unfinished and no_show', async () => {
  assert.equal(classifyUnresolvedOutcome({status: 'requested'}), 'unanswered');
  assert.equal(classifyUnresolvedOutcome({status: 'accepted', currentStep: 'requested_waiting_accept'}), 'unanswered');
  assert.equal(classifyUnresolvedOutcome({status: 'live', aArrived: true, bArrived: false}), 'no_show');
  assert.equal(classifyUnresolvedOutcome({status: 'accepted', aArrived: false, bArrived: false}), 'unfinished');
});

test('no_show penalties escalate deterministically and do not apply to completed or cancelled sessions', async () => {
  await db.doc('users/alice').set({});
  await db.doc('users/bob').set({});

  const now = Date.now();
  for (let i = 0; i < 3; i++) {
    const id = `noshow_${i}`;
    const eventTime = admin.firestore.Timestamp.fromMillis(now + i * 1000);
    await recordMeetupOutcome(id, {
      status: 'auto_closed',
      outcome: 'no_show',
      autoClosedFromStatus: 'live',
      aUid: 'alice',
      bUid: 'bob',
      aArrived: true,
      bArrived: false,
      requestedAt: admin.firestore.Timestamp.fromMillis(now - 60000),
    }, eventTime);
  }

  const penalties = await db.collection('users/bob/meetupNoShowPenalties').orderBy('penalizedAt').get();
  assert.equal(penalties.size, 3);
  assert.deepEqual(penalties.docs.map(doc => doc.data().lockDurationMs), [15 * 60 * 1000, 2 * 60 * 60 * 1000, 24 * 60 * 60 * 1000]);
  assert.equal((await db.collection('users/alice/meetupNoShowPenalties').get()).size, 0);

  const bobMatching = (await db.doc('users/bob/meta/matching').get()).data();
  assert.equal(bobMatching.noShowPenaltyCount, 3);
  assert.ok(Number(bobMatching.lockUntilEpochMs || 0) > now);
  const bobTrust = (await db.doc('users/bob/stats/trust').get()).data();
  assert.equal(bobTrust.noShowCount, 3);
  assert.equal(bobTrust.noShowTrustPenalty, 10);

  await recordMeetupOutcome('done', {
    status: 'completed',
    outcome: 'completed',
    aUid: 'alice',
    bUid: 'bob',
    aArrived: true,
    bArrived: true,
  }, admin.firestore.Timestamp.fromMillis(now + 5000));
  await recordMeetupOutcome('mutual_cancel', {
    status: 'cancelled',
    outcome: 'cancelled',
    aUid: 'alice',
    bUid: 'bob',
    cancelRequestedByA: true,
    cancelRequestedByB: true,
  }, admin.firestore.Timestamp.fromMillis(now + 6000));
  assert.equal((await db.collection('users/bob/meetupNoShowPenalties').get()).size, 3);
});

async function seedPayment() {
  await db.doc('users/alice/billing/externalCheckout/items/checkout123').set({uid: 'alice', sessionId: 'checkout123', provider: 'square', sku: 'points_topup_250', amountUsd: 4.99, status: 'session_created'});
}
const paid = () => applyExternalCheckoutStatus({uid: 'alice', sessionId: 'checkout123', status: 'paid', providerReference: 'square-event', amountCents: 499, currency: 'USD', callbackPayload: null});

test('business mode validates paid expiry, permits deactivation and limits preview to verified owner', async () => {
  await assert.rejects(updateBusinessMode('alice', true), /Current business access/);
  assert.deepEqual(await updateBusinessMode('alice', false), {active: false});
  await db.doc('users/alice/billing/entitlements').set({businessSubscriptionActive: true, subscriptionRenewsAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000)});
  await assert.rejects(updateBusinessMode('alice', true), /Current business access/);
  await db.doc('users/alice/billing/entitlements').update({subscriptionRenewsAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000)});
  assert.deepEqual(await updateBusinessMode('alice', true), {active: true});
  assert.deepEqual(await updateBusinessMode('alice', false), {active: false});
  await assert.rejects(setBusinessModeActive.run({data: {active: true}, auth: {uid: 'preview', token: {email: 'marty.marola@hotmail.com', email_verified: false}}}), /Current business access/);
  assert.deepEqual(await setBusinessModeActive.run({data: {active: true}, auth: {uid: 'preview', token: {email: 'marty.marola@hotmail.com', email_verified: true}}}), {active: true});
});

test('Square authorization/pending updates do not grant purchases', () => {
  assert.equal(mapSquareEventToStatus('payment.created', {data: {object: {payment: {status: 'APPROVED'}}}}), '');
  assert.equal(mapSquareEventToStatus('payment.updated', {data: {object: {payment: {status: 'COMPLETED'}}}}), 'paid');
  assert.equal(mapSquareEventToStatus('subscription.updated', {data: {object: {subscription: {status: 'ACTIVE'}}}}), '');
});

async function refundablePayment(sku = 'points_topup_250', amountUsd = 4.99, grant = true) {
  await db.doc('users/alice/billing/externalCheckout/items/refundable').set({uid: 'alice', sessionId: 'refundable', provider: 'square', sku, amountUsd, status: 'session_created', providerOrderId: 'order123'});
  await db.doc('checkoutSessions/refundable').set({uid: 'alice', providerOrderId: 'order123', providerPaymentId: 'payment123'});
  if (grant) await applyExternalCheckoutStatus({uid: 'alice', sessionId: 'refundable', status: 'paid', providerReference: 'paid-event', amountCents: Math.round(amountUsd * 100), currency: 'USD', orderId: 'order123', paymentId: 'payment123', callbackPayload: null});
}
function refundPayload(eventId = 'refund_event', overrides = {}) {
  return {type: 'refund.updated', event_id: eventId, data: {object: {refund: {id: 'refund123', payment_id: 'payment123', order_id: 'order123', status: 'COMPLETED', version: 2, amount_money: {amount: 499, currency: 'USD'}, ...overrides}}}};
}

test('refund signatures require exact configured URL and original bytes', () => {
  const {createHmac} = require('node:crypto');
  const oldKey = process.env.SQUARE_WEBHOOK_SIGNATURE_KEY;
  const oldUrl = process.env.SQUARE_WEBHOOK_ENDPOINT_URL;
  process.env.SQUARE_WEBHOOK_SIGNATURE_KEY = 'test-signature-key';
  process.env.SQUARE_WEBHOOK_ENDPOINT_URL = 'https://example.test/square';
  const rawBody = Buffer.from(JSON.stringify(refundPayload()));
  const signature = createHmac('sha256', 'test-signature-key').update(`https://example.test/square${rawBody}`).digest('base64');
  assert.equal(verifySquareWebhookSignature({rawBody, header: () => signature}), true);
  assert.equal(verifySquareWebhookSignature({rawBody: Buffer.from('{}'), header: () => signature}), false);
  assert.equal(verifySquareWebhookSignature({rawBody, header: () => 'forged'}), false);
  if (oldKey === undefined) delete process.env.SQUARE_WEBHOOK_SIGNATURE_KEY; else process.env.SQUARE_WEBHOOK_SIGNATURE_KEY = oldKey;
  if (oldUrl === undefined) delete process.env.SQUARE_WEBHOOK_ENDPOINT_URL; else process.env.SQUARE_WEBHOOK_ENDPOINT_URL = oldUrl;
});

test('completed full topup refund reverses once across retries and stale events cannot reopen it', async () => {
  await refundablePayment();
  await Promise.all([reconcileSquareLifecycle(refundPayload()), reconcileSquareLifecycle(refundPayload())]);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 0);
  assert.equal((await db.doc('users/alice/billing/invoices/items/refundable').get()).data().status, 'refunded');
  assert.equal((await db.collection('users/alice/meta/points/events').get()).size, 2);
  const stale = await reconcileSquareLifecycle(refundPayload('older_event', {version: 1, status: 'PENDING'}));
  assert.equal(stale.status, 'ignored_stale');
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 0);
});

test('full lifetime refund revokes only the exact source and preserves unrelated prepaid access', async () => {
  await db.doc('users/alice/billing/entitlements').set({businessSubscriptionActive: true, subscriptionRenewsAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000), businessSubscriptionSourceSessionId: 'unrelated'});
  await refundablePayment('biz_onetime_unlock', 11.99);
  const result = await reconcileSquareLifecycle(refundPayload('lifetime_refund', {amount_money: {amount: 1199, currency: 'USD'}}));
  assert.equal(result.status, 'reconciled');
  const entitlement = (await db.doc('users/alice/billing/entitlements').get()).data();
  assert.equal(entitlement.businessPurchased, false);
  assert.equal(entitlement.businessSubscriptionActive, true);
  assert.equal(entitlement.businessWalletUnlocked, true);
});

test('full latest prepaid refund restores the previous prepaid period and its source', async () => {
  const previous = admin.firestore.Timestamp.fromMillis(Date.now() + 86400000);
  await db.doc('users/alice/billing/entitlements').set({businessSubscriptionActive: true, subscriptionRenewsAt: previous, businessSubscriptionSourceSessionId: 'points_prior', businessPurchased: true});
  await refundablePayment('biz_monthly_subscription', 49.99);
  const result = await reconcileSquareLifecycle(refundPayload('monthly_refund', {amount_money: {amount: 4999, currency: 'USD'}}));
  assert.equal(result.status, 'reconciled');
  const entitlement = (await db.doc('users/alice/billing/entitlements').get()).data();
  assert.equal(entitlement.subscriptionRenewsAt.isEqual(previous), true);
  assert.equal(entitlement.businessSubscriptionSourceSessionId, 'points_prior');
  assert.equal(entitlement.businessPurchased, true);
});

test('spent points, partial refunds, disputes and superseded grants enter durable operator review', async () => {
  await refundablePayment();
  await db.doc('users/alice/meta/points').update({currentPoints: 10});
  assert.equal((await reconcileSquareLifecycle(refundPayload())).reason, 'refunded_points_already_spent');
  assert.equal((await reconcileSquareLifecycle(refundPayload('partial', {id: 'partial_refund', amount_money: {amount: 100, currency: 'USD'}}))).reason, 'partial_or_mismatched_refund');
  const dispute = await reconcileSquareLifecycle({type: 'dispute.created', event_id: 'dispute_event', data: {object: {dispute: {id: 'dispute123', disputed_payment: {payment_id: 'payment123'}, state: 'EVIDENCE_REQUIRED', due_at: '2026-10-01', amount_money: {amount: 499, currency: 'USD'}}}}});
  assert.equal(dispute.reason, 'dispute_requires_operator');
  assert.equal((await reconcileSquareLifecycle(refundPayload('pending', {id: 'pending_refund', status: 'PENDING'}))).reason, 'refund_pending');
  assert.equal((await reconcileSquareLifecycle(refundPayload('failed', {id: 'failed_refund', status: 'FAILED'}))).reason, 'refund_failed');
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 10);
  assert.equal((await db.collection('paymentReconciliation').get()).size, 5);
  await db.doc('users/alice/billing/externalCheckout/items/refundable').update({sku: 'biz_onetime_unlock', amountUsd: 11.99});
  await db.doc('users/alice/billing/entitlements').set({businessPurchased: true, businessPurchasedSourceSessionId: 'points_newer'});
  const superseded = await reconcileSquareLifecycle(refundPayload('superseded', {id: 'lifetime_refund', amount_money: {amount: 1199, currency: 'USD'}}));
  assert.equal(superseded.reason, 'missing_or_superseded_entitlement_source');
  assert.equal((await db.doc('users/alice/billing/entitlements').get()).data().businessPurchased, true);
});

test('refund before payment grant prevents a delayed completed-payment event from granting access', async () => {
  await refundablePayment('points_topup_250', 4.99, false);
  assert.equal((await reconcileSquareLifecycle(refundPayload())).reason, 'refunded_before_grant');
  const paid = await applyExternalCheckoutStatus({uid: 'alice', sessionId: 'refundable', status: 'paid', providerReference: 'delayed-paid', amountCents: 499, currency: 'USD', orderId: 'order123', paymentId: 'payment123', callbackPayload: null});
  assert.equal(paid.applied, false);
  assert.equal((await db.doc('users/alice/meta/points').get()).exists, false);
});

test('a mismatched partial refund cannot flag or mutate an unrelated checkout', async () => {
  await refundablePayment();
  const result = await reconcileSquareLifecycle(refundPayload('mismatch', {payment_id: 'wrong_payment', amount_money: {amount: 100, currency: 'USD'}}));
  assert.equal(result.reason, 'payment_identity_mismatch');
  assert.equal((await db.doc('users/alice/billing/externalCheckout/items/refundable').get()).data().refundReviewRequired, undefined);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 250);
});

test('refunding a second lifetime payment preserves the first unrefunded purchase', async () => {
  await db.doc('users/alice/billing/entitlements').set({businessPurchased: true, businessPurchasedSourceSessionId: 'first_payment'});
  await refundablePayment('biz_onetime_unlock', 11.99);
  assert.equal((await db.doc('users/alice/billing/entitlements').get()).data().businessPurchasedSourceSessionId, 'first_payment');
  const result = await reconcileSquareLifecycle(refundPayload('duplicate_lifetime_refund', {amount_money: {amount: 1199, currency: 'USD'}}));
  assert.equal(result.reason, 'duplicate_lifetime_payment_refunded');
  assert.equal((await db.doc('users/alice/billing/entitlements').get()).data().businessPurchased, true);
});

test('latest monthly refund cannot restore a previously refunded source awaiting review', async () => {
  await db.doc('users/alice/billing/externalCheckout/items/prior_month').set({fullRefundConfirmed: true, refundReviewRequired: true});
  const priorExpiry = admin.firestore.Timestamp.fromMillis(Date.now() + 86400000);
  await db.doc('users/alice/billing/entitlements').set({businessSubscriptionActive: true, subscriptionRenewsAt: priorExpiry, businessSubscriptionSourceSessionId: 'prior_month'});
  await refundablePayment('biz_monthly_subscription', 49.99);
  const before = (await db.doc('users/alice/billing/entitlements').get()).data().subscriptionRenewsAt;
  const result = await reconcileSquareLifecycle(refundPayload('monthly_after_prior_refund', {amount_money: {amount: 4999, currency: 'USD'}}));
  assert.equal(result.reason, 'prior_prepaid_source_requires_review');
  assert.equal((await db.doc('users/alice/billing/entitlements').get()).data().subscriptionRenewsAt.isEqual(before), true);
});

test('refunding the original lifetime source preserves access while another lifetime payment remains', async () => {
  await refundablePayment('biz_onetime_unlock', 11.99);
  await db.doc('users/alice/billing/externalCheckout/items/later_lifetime').set({uid: 'alice', provider: 'square', sku: 'biz_onetime_unlock', amountUsd: 11.99, providerOrderId: 'later_order'});
  await applyExternalCheckoutStatus({uid: 'alice', sessionId: 'later_lifetime', status: 'paid', providerReference: 'later_paid', amountCents: 1199, currency: 'USD', orderId: 'later_order', paymentId: 'later_payment', callbackPayload: null});
  const result = await reconcileSquareLifecycle(refundPayload('original_lifetime_refund', {amount_money: {amount: 1199, currency: 'USD'}}));
  assert.equal(result.reason, 'lifetime_multiple_sources_requires_review');
  assert.equal((await db.doc('users/alice/billing/entitlements').get()).data().businessPurchased, true);
});

test('late account bootstrap cannot resurrect an erased account', async () => {
  await db.doc('accountDeletions/alice').set({status: 'complete'});
  await onAuthCreate.run({uid: 'alice'});
  assert.equal((await db.doc('users/alice').get()).exists, false);
});

test('party metrics count distinct peers once and skip deleted users', async () => {
  await db.doc('users/alice/party/bob').set({uid: 'bob'});
  const event = id => ({params: {matchId: id}, data: {data: () => ({participants: ['alice', 'bob']})}});
  await onInPartyMatchMetrics.run(event('first'));
  await onInPartyMatchMetrics.run(event('second'));
  await onInPartyMatchMetrics.run(event('second'));
  const metrics = (await db.doc('users/alice/meta/inPartyMatchMetrics').get()).data();
  assert.equal(metrics.totalInPartyMatches, 2);
  assert.equal(metrics.uniquePairs, 1);
  await db.doc('accountDeletions/alice').set({status: 'complete'});
  await onInPartyMatchMetrics.run(event('after_deletion'));
  assert.equal((await db.doc('users/alice/meta/inPartyMatchMetrics').get()).data().totalInPartyMatches, 2);
});

test('legacy presence coordinates migrate idempotently and follow current geopoint', async () => {
  const reference = db.doc('users/alice/presence/current');
  await reference.set({geopoint: new admin.firestore.GeoPoint(42, -73), expiresAt: admin.firestore.Timestamp.now()});
  await syncPresenceCoordinates('alice');
  const first = await reference.get();
  assert.equal(first.data().latitude, 42);
  assert.equal(first.data().longitude, -73);
  assert.equal(first.data().kind, 'current');
  await syncPresenceCoordinates('alice');
  assert.equal((await reference.get()).updateTime.isEqual(first.updateTime), true);
  await reference.update({geopoint: new admin.firestore.GeoPoint(43, -74)});
  await syncPresenceCoordinates('alice');
  assert.equal((await reference.get()).data().latitude, 43);
});

test('simultaneous payment retries credit points and invoice exactly once', async () => {
  await seedPayment();
  const results = await Promise.all([paid(), paid(), paid()]);
  assert.equal(results.filter(result => result.applied).length, 1);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 250);
  assert.equal((await db.collection('users/alice/billing/invoices/items').get()).size, 1);
  assert.equal((await db.collection('users/alice/meta/points/events').get()).size, 1);
});

test('wrong payment amount cannot mark paid or create partial entitlements', async () => {
  await seedPayment();
  await assert.rejects(applyExternalCheckoutStatus({uid: 'alice', sessionId: 'checkout123', status: 'paid', providerReference: 'wrong', amountCents: 1, currency: 'USD', callbackPayload: null}), /payment_amount_mismatch/);
  assert.equal((await db.doc('users/alice/billing/externalCheckout/items/checkout123').get()).data().status, 'session_created');
  assert.equal((await db.doc('users/alice/meta/points').get()).exists, false);
  await paid();
});

test('paid external checkout for unlock service SKU grants ownership and entitlement exactly once', async () => {
  await db.doc('users/alice/billing/externalCheckout/items/service_unlock').set({
    uid: 'alice',
    sessionId: 'service_unlock',
    provider: 'square',
    sku: 'service_single_keyword_match_unlock',
    amountUsd: 0.65,
    status: 'session_created',
    providerOrderId: 'service_order_1',
  });

  const first = await applyExternalCheckoutStatus({
    uid: 'alice',
    sessionId: 'service_unlock',
    status: 'paid',
    providerReference: 'service_paid_event_1',
    amountCents: 65,
    currency: 'USD',
    orderId: 'service_order_1',
    paymentId: 'service_payment_1',
    callbackPayload: null,
  });
  const second = await applyExternalCheckoutStatus({
    uid: 'alice',
    sessionId: 'service_unlock',
    status: 'paid',
    providerReference: 'service_paid_event_1_retry',
    amountCents: 65,
    currency: 'USD',
    orderId: 'service_order_1',
    paymentId: 'service_payment_1',
    callbackPayload: null,
  });

  assert.equal(first.applied, true);
  assert.equal(second.applied, false);

  const entitlement = (await db.doc('users/alice/billing/entitlements').get()).data();
  assert.equal(entitlement.singleKeywordMatchModeUnlocked, true);
  assert.equal(entitlement.lastPaymentMethod, 'card_external');

  const purchase = (await db.doc('users/alice/store/purchases/items/service_single_keyword_match_unlock').get()).data();
  assert.equal(purchase.sku, 'service_single_keyword_match_unlock');
  assert.equal(purchase.paymentMethod, 'card_external');
  assert.equal(purchase.providerSessionId, 'service_unlock');
  assert.equal(purchase.amountUsd, 0.65);

  assert.equal((await db.collection('users/alice/billing/invoices/items').get()).size, 1);
  assert.equal((await db.collection('users/alice/meta/points/events').get()).size, 0);
});

test('paid external checkout for non-entitlement service SKU grants ownership without points side effects', async () => {
  await db.doc('users/alice/billing/externalCheckout/items/service_non_entitlement').set({
    uid: 'alice',
    sessionId: 'service_non_entitlement',
    provider: 'square',
    sku: 'service_profile_spotlight_week',
    amountUsd: 0.8,
    status: 'session_created',
    providerOrderId: 'service_order_2',
  });

  const result = await applyExternalCheckoutStatus({
    uid: 'alice',
    sessionId: 'service_non_entitlement',
    status: 'paid',
    providerReference: 'service_paid_event_2',
    amountCents: 80,
    currency: 'USD',
    orderId: 'service_order_2',
    paymentId: 'service_payment_2',
    callbackPayload: null,
  });

  assert.equal(result.applied, true);
  const purchase = (await db.doc('users/alice/store/purchases/items/service_profile_spotlight_week').get()).data();
  assert.equal(purchase.sku, 'service_profile_spotlight_week');
  assert.equal(purchase.paymentMethod, 'card_external');
  assert.equal(purchase.providerSessionId, 'service_non_entitlement');

  const entitlement = (await db.doc('users/alice/billing/entitlements').get()).data();
  assert.equal(entitlement.singleKeywordMatchModeUnlocked, undefined);
  assert.equal(entitlement.reciprocalKeywordMatchModeUnlocked, undefined);
  assert.equal(entitlement.keywordChainMatchModeUnlocked, undefined);

  assert.equal((await db.collection('users/alice/meta/points/events').get()).size, 0);
});

test('points purchases atomically debit once and reject overspending/inert samples', async () => {
  await db.doc('users/alice/meta/points').set({currentPoints: 100, totalPoints: 100});
  const call = () => purchasePointsEntitlement('alice', 'service_single_keyword_match_unlock', 'purchase_request_12345');
  await Promise.all([call(), call()]);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 35);
  assert.equal((await db.doc('users/alice/billing/entitlements').get()).data().singleKeywordMatchModeUnlocked, true);
  assert.equal((await db.doc('users/alice/store/purchases/items/service_single_keyword_match_unlock').get()).exists, true);
  await assert.rejects(purchasePointsEntitlement('alice', 'service_keyword_chain_unlock', 'another_request_12345'), /Not enough points/);
  await assert.rejects(purchasePointsEntitlement('alice', 'cosmetic_profile_glow', 'sample_request_123456'), /supported item/);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 35);
});

test('repeat monthly purchases with new keys preserve active access and balance', async () => {
  await db.doc('users/alice/meta/points').set({currentPoints: 1000, totalPoints: 1000});
  await purchasePointsEntitlement('alice', 'biz_monthly_subscription', 'first_monthly_12345');
  const result = await purchasePointsEntitlement('alice', 'biz_monthly_subscription', 'second_monthly_12345');
  assert.equal(result.alreadyOwned, true);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 800);
  assert.equal((await db.doc('users/alice/billing/entitlements').get()).data().businessWalletUnlocked, true);
});

test('policy rewards require acceptance and cannot be farmed or claimed for forged support', async () => {
  await assert.rejects(claimReward('alice', 'policy_ack', 'conduct'), /Accept the policy/);
  await db.doc('users/alice/meta/policyAcks').set({versions: {conduct_v1: {accepted: true}}});
  await Promise.all([claimReward('alice', 'policy_ack', 'conduct'), claimReward('alice', 'policy_ack', 'conduct')]);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 10);
  await assert.rejects(claimReward('alice', 'support', 'made_up_session'), /confirmed support/);
});

test('callables reject unauthenticated purchases and stale-session account deletion', async () => {
  await assert.rejects(purchaseWithPoints.run({data: {}}), /Sign in/);
  await assert.rejects(deleteMyAccount.run({data: {expectedUid: 'alice'}, auth: {uid: 'alice', token: {auth_time: 1}}}), /Sign in again/);
  await assert.rejects(deleteMyAccount.run({data: {expectedUid: 'bob'}, auth: {uid: 'alice', token: {auth_time: Date.now() / 1000}}}), /account changed/);
  assert.equal((await db.doc('accountDeletions/alice').get()).exists, false);
});

test('completed meetup synchronization counts once per cycle and unlocks referral only at five verified completions', async () => {
  await db.doc('users/alice').set({referrer: 'referrer'});
  await db.doc('users/bob').set({displayName: 'Bob'});
  await db.doc('users/referrer/referrals/alice').set({inPersonVerified: true, rewardEligible: true, meetupsCompleted: 0});
  for (let i = 0; i < 5; i++) {
    const id = `meetup_${i}`;
    await db.doc(`meetups/${id}`).set({aUid: 'alice', bUid: 'bob', status: 'completed', aArrived: true, bArrived: true, completedAt: admin.firestore.Timestamp.now()});
    await recordCompletedMeetup(id, 'alice');
    await recordCompletedMeetup(id, 'alice');
    assert.equal((await db.doc('users/alice/meta/points').get()).data().completedMeetups, i + 1);
    assert.equal((await db.doc('users/referrer/referrals/alice').get()).data().rewardGranted, i === 4);
  }
  await assert.rejects(recordCompletedMeetup('meetup_0', 'mallory'), /participant/);
  assert.equal((await db.collection('users/alice/completedMeetups').get()).size, 5);
});

test('keyword moderation retries add one strike and preserve unrelated profile edits', async () => {
  const notifications = require('../../functions_notifications/index.js');
  await db.doc('users/target').set({displayName: 'Preserve me', SearchingFor: ['suppressed', 'gardening']});
  await db.doc('profiles/target').set({displayName: 'Preserve me', SearchingFor: ['suppressed', 'gardening']});
  for (const uid of ['a', 'b', 'c']) await db.doc(`keywordReports/${uid}`).set({reporterUid: uid, targetUid: 'target', normalizedKeyword: 'suppressed'});
  const event = {params: {reportId: 'c'}, data: await db.doc('keywordReports/c').get()};
  await notifications.onKeywordReportCreated.run(event);
  await db.doc('profiles/target').update({displayName: 'New display name'});
  await notifications.onKeywordReportCreated.run(event);
  assert.equal((await db.doc('keywordEnforcement/target').get()).data().strikeCount, 1);
  assert.deepEqual((await db.doc('profiles/target').get()).data().SearchingFor, ['gardening']);
  assert.equal((await db.doc('profiles/target').get()).data().displayName, 'New display name');
  await require('../../functions_notifications/node_modules/firebase-admin').app().delete();
});

test('account erasure removes nested private data, media, owned messages and peer access; retry is safe', {skip: !process.env.FIREBASE_STORAGE_EMULATOR_HOST}, async () => {
  await db.doc('users/alice').set({email: 'alice@example.test'});
  await db.doc('users/alice/settings/private').set({secret: 'private'});
  await db.doc('profiles/alice').set({displayName: 'Alice'});
  await db.doc('publicProfiles/alice').set({displayName: 'Alice'});
  await db.doc('paymentReconciliation/alice_event').set({uid: 'alice', status: 'review_required'});
  await db.doc('partyInPersonSessions/alice').set({uid:'alice',code:'AABBCCDDEE',active:true});
  await db.doc('partyInPersonCodes/AABBCCDDEE').set({uid:'alice'});
  await db.doc('partyInPersonRateLimits/alice').set({attempts:3});
  await db.doc('matchingLocations/alice').set({uid:'alice',publicMatchingAvailable:true});
  await db.doc('chats/pair').set({participants: ['alice', 'bob'], lastMessage: 'Alice secret'});
  await db.doc('chats/pair/messages/alice').set({from: 'alice', text: 'private'});
  await db.doc('chats/pair/messages/bob').set({from: 'bob', text: 'retained'});
  await admin.storage().bucket().file('profiles/alice/avatar.png').save('test', {contentType: 'image/png'});
  await eraseUserData('alice');
  await eraseUserData('alice');
  assert.equal((await db.doc('users/alice/settings/private').get()).exists, false);
  assert.equal((await db.doc('profiles/alice').get()).exists, false);
  assert.equal((await db.doc('publicProfiles/alice').get()).exists, false);
  assert.equal((await db.doc('paymentReconciliation/alice_event').get()).exists, false);
  for (const path of ['partyInPersonSessions/alice', 'partyInPersonCodes/AABBCCDDEE',
    'partyInPersonRateLimits/alice', 'matchingLocations/alice']) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  assert.equal((await db.doc('chats/pair/messages/alice').get()).exists, false);
  assert.equal((await db.doc('chats/pair/messages/bob').get()).exists, true);
  assert.deepEqual((await db.doc('chats/pair').get()).data().participants, ['bob']);
  assert.equal((await admin.storage().bucket().file('profiles/alice/avatar.png').exists())[0], false);
});

test('public profile projection excludes private fields, replaces stale mirrors and honors deletion', async () => {
  const account = {displayName: 'Alice', email: 'private@example.test', referrer: 'bob', dob: 'secret', keywords: {'Searching For': ['gardening'], 'Can Provide': ['cooking']}, keywordWorkspace: {hiddenInventory: ['secret'], visibleInventory: ['flowers']}, interactionLock: {busyInMeetup: true, meetupId: 'private-meetup'}};
  const projected = publicProfile('alice', account);
  assert.equal(projected.busyInMeetup, true);
  assert.deepEqual(projected.activeKeywords, ['cooking', 'gardening']);
  assert.equal(JSON.stringify(projected).includes('secret'), false);
  for (const key of ['email', 'referrer', 'dob', 'keywordWorkspace']) assert.equal(key in projected, false);
  await db.doc('users/alice').set(account);
  await db.doc('publicProfiles/alice').set({email: 'stale-leak'});
  await syncPublicProfile('alice');
  const first = await db.doc('publicProfiles/alice').get();
  assert.deepEqual(first.data(), projected);
  assert.equal(publicProfilesEqual(first.data(), projected), true);
  let attemptedWrites = 0;
  const originalRunTransaction = db.runTransaction.bind(db);
  db.runTransaction = (callback, options) => originalRunTransaction(tx => {
    const originalSet = tx.set.bind(tx);
    tx.set = (reference, ...args) => {
      if (reference.path === 'publicProfiles/alice') attemptedWrites++;
      return originalSet(reference, ...args);
    };
    return callback(tx);
  }, options);
  try { await syncPublicProfile('alice'); }
  finally { db.runTransaction = originalRunTransaction; }
  assert.equal(attemptedWrites, 0, 'Equivalent decoded maps must not incur another write.');
  assert.equal((await db.doc('publicProfiles/alice').get()).updateTime.isEqual(first.updateTime), true);
  await db.doc('accountDeletions/alice').set({status: 'processing'});
  await syncPublicProfile('alice');
  assert.equal((await db.doc('publicProfiles/alice').get()).exists, false);
});

test('code linking keeps the actual owner, immutable attribution and verified legacy progress', async () => {
  await db.doc('users/referrer').set({root_referrer: 'root'});
  await db.doc('referralCodes/PROX-ABC').set({referrerUid: 'referrer', active: true});
  await db.doc('users/referrer/referrals/alice').set({uid: 'alice', inPersonVerified: true, rewardEligible: true, meetupsCompleted: 4});
  await db.doc('users/alice').set({referrer: 'referrer'});
  const result = await linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'PROX-ABC'}});
  assert.equal(result.referrerUid, 'referrer');
  assert.equal((await db.doc('users/alice').get()).data().root_referrer, 'root');
  assert.equal((await db.doc('referralAttributions/alice').get()).data().rootReferrerUid, 'root');
  assert.equal((await db.doc('users/referrer/referrals/alice').get()).data().inPersonVerified, true);
  assert.equal((await db.doc('users/referrer/referrals/alice').get()).data().meetupsCompleted, 4);
  assert.equal((await linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'PROX-ABC'}})).replayed, true);
  await db.doc('referralCodes/PROX-OTHER').set({referrerUid: 'other', active: true});
  await assert.rejects(linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'PROX-OTHER'}}), /already assigned/);
});

test('code-only linking rejects missing accounts and ignores forged owner hints', async () => {
  await db.doc('referralCodes/INV123').set({referrerUid: 'owner', active: true});
  await db.doc('users/alice').set({});
  await assert.rejects(linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'INV123'}}), /unavailable/);
  await db.doc('users/owner').set({root_referrer: 'root'});
  const result = await linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'INV123', referrerUid: 'forged', expectedUid: 'alice'}});
  assert.equal(result.referrerUid, 'owner');
  await assert.rejects(linkReferralCode.run({auth: {uid: 'bob'}, data: {code: 'INV123'}}), /unavailable/);
  await assert.rejects(linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'INV123', expectedUid: 'bob'}}), /account changed/);
});

test('referral download android redirect keeps tracking params and tree fields', async () => {
  await db.doc('referralCodes/PROX-ABC').set({
    referrerUid: 'referrer',
    rootReferrerUid: 'root_referrer',
    active: true,
  });

  await withReferralEnv({
    PROX_PUBLIC_APK_URL: 'https://github.com/marolam/prox/releases/latest/download/app-release.apk',
  }, async () => {
    const req = makeReferralReq({
      method: 'GET',
      query: {
        code: 'prox-abc',
        party: '1',
      },
      headers: {
        'user-agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 7)',
        'x-forwarded-for': '203.0.113.9, 70.10.10.10',
      },
    });
    const res = makeReferralRes();

    await referralApkDownload(req, res);

    assert.equal(res.redirectStatus, 302);
    const redirect = new URL(res.redirectUrl);
    assert.equal(redirect.hostname, 'github.com');
    assert.equal(redirect.searchParams.get('ref'), 'referrer');
    assert.equal(redirect.searchParams.get('code'), 'PROX-ABC');
    assert.equal(redirect.searchParams.get('party'), '1');
    assert.equal(redirect.searchParams.get('inperson'), '1');

    const clicks = await db.collection('referralDownloadClicks').get();
    assert.equal(clicks.size, 1);
    const click = clicks.docs[0].data();
    assert.equal(click.referrerUid, 'referrer');
    assert.equal(click.rootReferrerUid, 'root_referrer');
    assert.equal(click.source, 'apk_redirect');
  });
});

test('referral download iOS user-agent redirects to configured iOS URL', async () => {
  await db.doc('referralCodes/PROX-IOS').set({
    referrerUid: 'ios_referrer',
    rootReferrerUid: 'ios_root',
    active: true,
  });

  await withReferralEnv({
    PROX_PUBLIC_APK_URL: 'https://github.com/marolam/prox/releases/latest/download/app-release.apk',
    PROX_IOS_UPDATE_URL: 'https://testflight.apple.com/join/AbCdEf12',
  }, async () => {
    const req = makeReferralReq({
      method: 'GET',
      query: {
        code: 'prox-ios',
      },
      headers: {
        'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
      },
    });
    const res = makeReferralRes();

    await referralApkDownload(req, res);

    assert.equal(res.redirectStatus, 302);
    const redirect = new URL(res.redirectUrl);
    assert.equal(redirect.hostname, 'testflight.apple.com');
    assert.equal(redirect.searchParams.get('ref'), 'ios_referrer');
    assert.equal(redirect.searchParams.get('code'), 'PROX-IOS');
  });
});

test('referral download iOS path fails safely when iOS URL is missing', async () => {
  await db.doc('referralCodes/PROX-NO-IOS').set({
    referrerUid: 'owner_no_ios',
    active: true,
  });

  await withReferralEnv({
    PROX_PUBLIC_APK_URL: 'https://github.com/marolam/prox/releases/latest/download/app-release.apk',
  }, async () => {
    const req = makeReferralReq({
      method: 'GET',
      query: {
        code: 'prox-no-ios',
      },
      headers: {
        'user-agent': 'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X)',
      },
    });
    const res = makeReferralRes();

    await referralApkDownload(req, res);

    assert.equal(res.statusCode, 503);
    assert.deepEqual(res.jsonBody, {ok: false, error: 'ios_url_not_configured'});
    const clicks = await db.collection('referralDownloadClicks').get();
    assert.equal(clicks.size, 0);
  });
});

test('referral download target precedence uses explicit env then hint then fallback', async () => {
  await db.doc('referralCodes/PROX-PRE').set({
    referrerUid: 'pre_owner',
    active: true,
  });

  await withReferralEnv({
    PROX_REFERRAL_ANDROID_URL: 'https://github.com/marolam/prox/releases/download/v3/app-explicit.apk',
    PROX_PUBLIC_APK_URL: 'https://github.com/marolam/prox/releases/download/v2/app-public.apk',
    PROX_PUBLIC_APK_FALLBACK_URL: 'https://github.com/marolam/prox/releases/download/v1/app-fallback.apk',
  }, async () => {
    const explicitReq = makeReferralReq({
      method: 'GET',
      query: {
        code: 'prox-pre',
        apk: 'https://github.com/marolam/prox/releases/download/v4/app-hint.apk',
      },
      headers: {
        'user-agent': 'Mozilla/5.0 (Linux; Android 14)',
      },
    });
    const explicitRes = makeReferralRes();
    await referralApkDownload(explicitReq, explicitRes);
    assert.equal(new URL(explicitRes.redirectUrl).pathname.endsWith('/v3/app-explicit.apk'), true);
  });

  await withReferralEnv({
    PROX_REFERRAL_ANDROID_URL: 'https://evil.example.com/app.apk',
    PROX_PUBLIC_APK_URL: 'https://evil.example.com/app2.apk',
    PROX_PUBLIC_APK_FALLBACK_URL: 'https://github.com/marolam/prox/releases/download/v1/app-fallback.apk',
  }, async () => {
    const hintReq = makeReferralReq({
      method: 'GET',
      query: {
        code: 'prox-pre',
        apk: 'https://github.com/marolam/prox/releases/download/v4/app-hint.apk',
      },
      headers: {
        'user-agent': 'Mozilla/5.0 (Linux; Android 14)',
      },
    });
    const hintRes = makeReferralRes();
    await referralApkDownload(hintReq, hintRes);
    assert.equal(new URL(hintRes.redirectUrl).pathname.endsWith('/v4/app-hint.apk'), true);
  });

  await withReferralEnv({
    PROX_REFERRAL_ANDROID_URL: 'https://evil.example.com/app.apk',
    PROX_PUBLIC_APK_URL: 'https://evil.example.com/app2.apk',
    PROX_PUBLIC_APK_FALLBACK_URL: 'https://github.com/marolam/prox/releases/download/v1/app-fallback.apk',
  }, async () => {
    const fallbackReq = makeReferralReq({
      method: 'GET',
      query: {
        code: 'prox-pre',
        apk: 'https://evil.example.com/not-allowed.apk',
      },
      headers: {
        'user-agent': 'Mozilla/5.0 (Linux; Android 14)',
      },
    });
    const fallbackRes = makeReferralRes();
    await referralApkDownload(fallbackReq, fallbackRes);
    assert.equal(new URL(fallbackRes.redirectUrl).pathname.endsWith('/v1/app-fallback.apk'), true);
  });
});

test('mutual party projection is retry-safe and revokes after either membership is removed', async () => {
  await seedPartyMeetup();
  await changePartyConnection('alice', feedback('bob'));
  await changePartyConnection('bob', feedback('alice'));
  const event = {params: {uid: 'alice', friendUid: 'bob'}};
  await onPartyWrite.run(event);
  const first = await db.doc('users/alice/party/bob').get();
  assert.equal(first.data().mutual, true);
  await onPartyWrite.run(event);
  assert.equal((await db.doc('users/alice/party/bob').get()).updateTime.isEqual(first.updateTime), true);
  await db.doc('users/bob/party/alice').delete();
  await onPartyWrite.run(event);
  assert.equal((await db.doc('users/alice/party/bob').get()).exists, false);
  assert.equal((await partyPairRef().get()).data().status, 'removed');
});


const {changePartyConnection, connectionId, expirePartyConnections, PARTY_INACTIVITY_MS, PARTY_REMINDER_MS, onPartyConnectionBlock} = require('../lib/party_connections');
async function seedPartyMeetup() {
  await Promise.all(['alice', 'bob', 'mallory'].map(uid => db.doc(`users/${uid}`).set({displayName: uid})));
  await db.doc('meetups/party-test').set({aUid: 'alice', bUid: 'bob', status: 'completed', aArrived: true, bArrived: true});
}
const feedback = (otherUid, choice = 'add', thumb = true, comment = '') => ({action: 'feedback', otherUid, chatId: 'party-test', thumb, partyDecision: choice, comment});
const partyPairRef = () => db.doc(`partyConnections/${connectionId('alice', 'bob')}`);
async function assertPartyPair(connected) {
  for (const [a,b] of [['alice','bob'],['bob','alice']]) {
    const snap = await db.doc(`users/${a}/party/${b}`).get();
    assert.equal(snap.exists, connected);
    if (connected) assert.equal(snap.data().mutual, true);
  }
}
test('Party: first yes is pending; second yes atomically adds both members', async () => {
  await seedPartyMeetup();
  assert.equal((await changePartyConnection('alice', feedback('bob'))).status, 'pending');
  await assertPartyPair(false);
  assert.equal((await changePartyConnection('bob', feedback('alice'))).status, 'connected');
  await assertPartyPair(true);
});
test('Party: concurrent approvals are symmetric and retries do not duplicate or extend consent', async () => {
  await seedPartyMeetup();
  await Promise.all([changePartyConnection('alice', feedback('bob')), changePartyConnection('bob', feedback('alice'))]);
  await assertPartyPair(true);
  const before = (await partyPairRef().get()).data().updatedAt.toMillis();
  await changePartyConnection('alice', feedback('bob'));
  assert.equal((await partyPairRef().get()).data().updatedAt.toMillis(), before);
  assert.equal((await db.collection('ratings/party-test/entries').get()).size, 2);
});
test('Party: either Not Right Now keeps both out until later consent', async () => {
  for (const first of ['alice','bob']) {
    await seedPartyMeetup();
    const second = first === 'alice' ? 'bob' : 'alice';
    await changePartyConnection(first, feedback(second, 'later'));
    await changePartyConnection(second, feedback(first));
    await assertPartyPair(false);
    assert.equal((await changePartyConnection(first, {action: 'add', otherUid: second})).status, 'connected');
    await assertPartyPair(true);
    await db.recursiveDelete(db.doc('meetups/party-test'));
    await partyPairRef().delete();
    await db.doc('users/alice/party/bob').delete();
    await db.doc('users/bob/party/alice').delete();
  }
});
test('Party: negative feedback accepts blank or optional comments without creating membership', async () => {
  await seedPartyMeetup();
  assert.equal((await changePartyConnection('alice', feedback('bob', 'later', false, 'Did not feel comfortable'))).status, 'rated');
  await changePartyConnection('bob', feedback('alice', 'later', false));
  await assertPartyPair(false);
  assert.equal((await db.doc('ratings/party-test/entries/alice').get()).data().reason, 'Did not feel comfortable');
  assert.equal((await db.doc('ratings/party-test/entries/bob').get()).data().reason, null);
});
test('Party: outsiders, mismatched partners and unconfirmed meetups cannot be rated', async () => {
  await seedPartyMeetup();
  await assert.rejects(changePartyConnection('mallory', feedback('bob')), /participants/);
  await assert.rejects(changePartyConnection('alice', feedback('mallory')), /participants/);
  await db.doc('meetups/party-test').update({status: 'live', bArrived: false});
  await assert.rejects(changePartyConnection('alice', feedback('bob')), /confirm arrival/);
  await db.doc('meetups/party-test').update({bArrived: true});
  await changePartyConnection('alice', feedback('bob'));
  assert.equal((await db.doc('meetups/party-test').get()).data().status, 'completed');
});
test('Party: reminders are durable, rate limited and extend inactivity without granting consent', async () => {
  await seedPartyMeetup();
  await changePartyConnection('alice', feedback('bob'));
  await assert.rejects(changePartyConnection('alice', {action: 'remind', otherUid: 'bob'}), /24 hours/);
  await partyPairRef().update({'reminders.alice': admin.firestore.Timestamp.fromMillis(Date.now() - PARTY_REMINDER_MS - 1000)});
  await changePartyConnection('alice', {action: 'remind', otherUid: 'bob'});
  const d = (await partyPairRef().get()).data();
  assert.ok(d.expiresAt.toMillis() > Date.now() + PARTY_INACTIVITY_MS - 5000);
  assert.equal((await partyPairRef().collection('notifications').get()).size, 2);
  await assertPartyPair(false);
});
test('Party: expired requests cannot be accepted or reminded and are swept', async () => {
  await seedPartyMeetup();
  await changePartyConnection('alice', feedback('bob'));
  await partyPairRef().update({expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1)});
  await assert.rejects(changePartyConnection('bob', {action: 'add', otherUid: 'alice'}), /expired/);
  await assert.rejects(changePartyConnection('alice', {action: 'remind', otherUid: 'bob'}), /expired/);
  await expirePartyConnections();
  assert.equal((await partyPairRef().get()).data().status, 'expired');
  await assertPartyPair(false);
});
test('Party: blocking or removal clears both sides and stale retries cannot reconnect', async () => {
  await seedPartyMeetup();
  await changePartyConnection('alice', feedback('bob'));
  await changePartyConnection('bob', feedback('alice'));
  await changePartyConnection('alice', {action: 'remove', otherUid: 'bob'});
  await changePartyConnection('bob', feedback('alice'));
  await assertPartyPair(false);
  await changePartyConnection('alice', {action: 'block', otherUid: 'bob'});
  await assert.rejects(changePartyConnection('bob', {action: 'add', otherUid: 'alice'}), /unavailable/);
  await db.doc('users/alice/party/bob').set({mutual: false});
  await onPartyWrite.run({params: {uid:'alice', friendUid:'bob'}});
  await assertPartyPair(false);
});
test('Party: external block writes clear pending requests and preserve blocks after stale events', async () => {
  await seedPartyMeetup();
  await changePartyConnection('alice', feedback('bob'));
  await db.doc('users/bob/blocks/alice').set({uid:'alice'});
  await onPartyConnectionBlock.run({params:{uid:'bob', otherUid:'alice'}});
  assert.equal((await partyPairRef().get()).data().status, 'blocked');
  await assert.rejects(changePartyConnection('alice', feedback('bob')), /unavailable/);
  await assertPartyPair(false);
});


test('Party: rating an existing mutual member does not remove an established connection', async () => {
  await seedPartyMeetup();
  await db.doc('users/alice/party/bob').set({uid:'bob',mutual:true});
  await db.doc('users/bob/party/alice').set({uid:'alice',mutual:true});
  await partyPairRef().set({members:['alice','bob'], status:'connected', decisions:{alice:'add',bob:'add'},
    proof:{kind:'inPersonCode'}, source:'inPersonDirectInvite'});
  assert.equal((await changePartyConnection('alice', feedback('bob','later'))).status, 'connected');
  await assertPartyPair(true);
});
test('Party: toggling consent cannot bypass the reminder cooldown', async () => {
  await seedPartyMeetup();
  await changePartyConnection('alice', feedback('bob'));
  await changePartyConnection('alice', {action:'later',otherUid:'bob'});
  await changePartyConnection('alice', {action:'add',otherUid:'bob'});
  assert.equal((await partyPairRef().collection('notifications').get()).size, 1);
  await assertPartyPair(false);
});
test('Party: a block racing with acceptance leaves neither membership', async () => {
  await seedPartyMeetup();
  await changePartyConnection('alice', feedback('bob'));
  await Promise.allSettled([
    changePartyConnection('bob', feedback('alice')),
    changePartyConnection('alice', {action:'block',otherUid:'bob'}),
  ]);
  await assertPartyPair(false);
  assert.equal((await partyPairRef().get()).data().status, 'blocked');
});


test('Party: delayed block triggers never resurrect a deleted account connection', async () => {
  await seedPartyMeetup();
  await db.doc('users/alice/blocks/bob').set({uid:'bob'});
  await db.doc('accountDeletions/bob').set({status:'processing'});
  await onPartyConnectionBlock.run({params:{uid:'alice',otherUid:'bob'}});
  assert.equal((await partyPairRef().get()).exists, false);
  await assertPartyPair(false);
});


test('Party: a new meetup in the same chat has a fresh rating receipt and consent', async () => {
  await seedPartyMeetup();
  await changePartyConnection('alice', feedback('bob'));
  await changePartyConnection('bob', feedback('alice'));
  await changePartyConnection('alice', {action:'remove',otherUid:'bob'});
  await db.doc('meetups/party-test').update({completedAt:admin.firestore.Timestamp.fromMillis(Date.now()+10000)});
  await changePartyConnection('alice', feedback('bob','later'));
  assert.equal((await partyPairRef().get()).data().status, 'pending');
  assert.equal((await db.collection('meetups/party-test/partyFeedback').get()).size, 3);
  await assertPartyPair(false);
});


test('chat transition guard distinguishes Listen expiry, Active deadlines and explicit renewal', async () => {
  const {chatGateTransitionAllowed, onChatGateTransitionGuard} = require('../lib/lib/match_dashboard_enforcement');
  const now = Date.now();
  const before = {participants: ['alice', 'bob'], chatGate: {status: 'requested', requestedBy: 'alice', modeKind: 'listen', responseWindowSeconds: 86400, requestedAt: admin.firestore.Timestamp.fromMillis(now - 120000)}};
  const expired = {...before, chatGate: {...before.chatGate, status: 'expired', expiredBySystem: true}};
  assert.equal(chatGateTransitionAllowed(before, expired, now), false);
  assert.equal(chatGateTransitionAllowed(before, expired, now + 86400000), true);
  const active = {...before, chatGate: {...before.chatGate, modeKind: 'normal', responseWindowSeconds: 60}};
  assert.equal(chatGateTransitionAllowed(active, {...active, chatGate: {...active.chatGate, status: 'expired'}}, now), true);
  const renewed = {...before, chatGate: {status: 'requested', requestedBy: 'bob', requestedAt: admin.firestore.Timestamp.fromMillis(now), modeKind: 'listen', responseWindowSeconds: 86400}};
  assert.equal(chatGateTransitionAllowed(expired, renewed, now), true);
  assert.equal(chatGateTransitionAllowed({...expired, closedAt: admin.firestore.Timestamp.now()}, renewed, now), false);
  assert.equal(chatGateTransitionAllowed({...expired, chatGate: {...expired.chatGate, declinedBy: 'bob'}}, renewed, now), false);
  const ref = db.doc('chats/listen');
  await ref.set(before);
  const first = await ref.get();
  await ref.set(expired);
  const second = await ref.get();
  await onChatGateTransitionGuard.run({before: first, after: second}, {params: {chatId: 'listen'}});
  assert.equal((await ref.get()).data().chatGate.status, 'requested');
  // A late guard must not roll back a newer acceptance.
  await ref.update({'chatGate.status': 'accepted'});
  await onChatGateTransitionGuard.run({before: first, after: second}, {params: {chatId: 'listen'}});
  assert.equal((await ref.get()).data().chatGate.status, 'accepted');
});

test('meetup growth evidence uses Firestore completion time rather than a forged participant date', async () => {
  await db.doc('users/alice').set({});
  await db.doc('users/bob').set({});
  const meetup = db.doc('meetups/clock-forgery');
  await meetup.set({aUid: 'alice', bUid: 'bob', status: 'completed', aArrived: true, bArrived: true, completedAt: admin.firestore.Timestamp.fromMillis(1)});
  const source = await meetup.get();
  await recordCompletedMeetup('clock-forgery', 'alice');
  const receipt = (await db.collection('users/alice/completedMeetups').get()).docs[0].data();
  assert.equal(receipt.completedAt.toMillis(), 1);
  assert.equal(receipt.verifiedCompletedAt.toMillis(), source.updateTime.toMillis());
});
