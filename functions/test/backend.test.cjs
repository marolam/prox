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
const {linkReferralCode} = require('../lib/referral_downloads');
const {onPartyWrite} = require('../lib/lib/party');
const {updateBusinessMode, setBusinessModeActive} = require('../lib/business_mode');
const {syncPresenceCoordinates} = require('../lib/presence_projection');
const {onAuthCreate} = require('../lib/on_auth_create');
const {onInPartyMatchMetrics} = require('../lib/lib/in_party_match_metrics');
beforeEach(async () => {
  const result = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(result.status, 200);
});
after(async () => { await admin.app().delete(); });

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
  await db.doc('referralCodes/PROX-ABC').set({referrerUid: 'referrer', active: true});
  await db.doc('users/referrer/referrals/alice').set({uid: 'alice', inPersonVerified: true, rewardEligible: true, meetupsCompleted: 4});
  await db.doc('users/alice').set({referrer: 'referrer'});
  const result = await linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'PROX-ABC'}});
  assert.equal(result.referrerUid, 'referrer');
  assert.equal((await db.doc('users/referrer/referrals/alice').get()).data().inPersonVerified, true);
  assert.equal((await db.doc('users/referrer/referrals/alice').get()).data().meetupsCompleted, 4);
  assert.equal((await linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'PROX-ABC'}})).replayed, true);
  await db.doc('referralCodes/PROX-OTHER').set({referrerUid: 'other', active: true});
  await assert.rejects(linkReferralCode.run({auth: {uid: 'alice'}, data: {code: 'PROX-OTHER'}}), /already assigned/);
});

test('mutual party projection is retry-safe and revokes after either membership is removed', async () => {
  await db.doc('users/alice/party/bob').set({source: 'manual', mutual: false});
  await db.doc('users/bob/party/alice').set({source: 'manual', mutual: false});
  const event = {params: {uid: 'alice', friendUid: 'bob'}};
  await onPartyWrite.run(event);
  const first = await db.doc('users/alice/party/bob').get();
  assert.equal(first.data().mutual, true);
  await onPartyWrite.run(event);
  assert.equal((await db.doc('users/alice/party/bob').get()).updateTime.isEqual(first.updateTime), true);
  await db.doc('users/bob/party/alice').delete();
  await onPartyWrite.run(event);
  assert.equal((await db.doc('users/alice/party/bob').get()).data().mutual, false);
});
