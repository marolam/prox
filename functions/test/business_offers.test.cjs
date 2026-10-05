const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Offer tests require the local Firestore emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit'});
const db = admin.firestore();
const offers = require('../lib/lib/business_offers');
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(response.status, 200);
  await account('owner'); await account('viewer', false); await account('operator', false);
});
after(async () => { await admin.app().delete(); });
async function account(uid, paid = true) {
  await db.doc(`users/${uid}`).set({displayName: 'Local Pro', preciseAddress: 'Never public', email: 'private@example.test'});
  await db.doc(`users/${uid}/billing/entitlements`).set({businessModeActive: paid, businessPurchased: paid});
}
function draft(extra = {}) { return {title: 'Bike tune-up', description: 'A careful local bicycle tune-up service.', terms: 'Parts quoted separately.', locationLabel: 'Westchester County',
  expiresAtMs: Date.now() + 7 * 86400000, discountPercent: 10, visibility: 'public', ...extra}; }
function save(offerId = 'offer0001', extra = {}) { return {offerId, requestId: `${offerId}_save`, expectedRevision: 0, draft: draft(), submitForReview: true, ...extra}; }
async function publish(offerId = 'offer0001', extra = {}) {
  await offers.saveBusinessOfferForUid('owner', save(offerId, extra));
  await offers.reviewBusinessOfferForOperator('operator', {offerId, requestId: `${offerId}_review`, expectedRevision: 1, decision: 'approve'});
}
test('save is private and replay-safe; only human approval creates the limited public projection', async () => {
  const input = save();
  const [a, b] = await Promise.all([offers.saveBusinessOfferForUid('owner', input), offers.saveBusinessOfferForUid('owner', input)]);
  assert.equal(a.revision, 1); assert.equal(b.revision, 1);
  assert.equal((await db.doc('publicBusinessOffers/offer0001').get()).exists, false);
  assert.equal((await offers.listPublicBusinessOffersForUid('viewer')).offers.length, 0);
  await offers.reviewBusinessOfferForOperator('operator', {offerId: 'offer0001', requestId: 'review0001', expectedRevision: 1, decision: 'approve'});
  const row = (await offers.listPublicBusinessOffersForUid('viewer')).offers[0];
  assert.equal(row.title, input.draft.title); assert.equal(row.ownerUid, 'owner');
  assert.equal(row.email, undefined); assert.equal(row.preciseAddress, undefined); assert.equal(row.reviewedBy, undefined);
  const budget = (await db.collection('businessOfferBudgets').get()).docs[0]; assert.equal(budget.get('writes'), 1);
});
test('stale edits cannot overwrite a review; editing removes publication and preserves original creation time', async () => {
  await publish();
  const created = (await db.doc('businessOffers/offer0001').get()).get('createdAt').toMillis();
  await assert.rejects(offers.saveBusinessOfferForUid('owner', save('offer0001', {requestId: 'stale0001', expectedRevision: 1})), {code: 'aborted'});
  await offers.saveBusinessOfferForUid('owner', save('offer0001', {requestId: 'edit00001', expectedRevision: 2, submitForReview: false}));
  const row = await db.doc('businessOffers/offer0001').get();
  assert.equal(row.get('createdAt').toMillis(), created); assert.equal(row.get('status'), 'draft');
  assert.equal((await db.doc('publicBusinessOffers/offer0001').get()).exists, false);
});
test('paid access and expected-account/admin authorization cannot be bypassed', async () => {
  await assert.rejects(offers.saveBusinessOfferForUid('viewer', save()), {code: 'permission-denied'});
  await assert.rejects(offers.upsertBusinessOffer.run({data: save()}), {code: 'unauthenticated'});
  await assert.rejects(offers.upsertBusinessOffer.run({auth: {uid: 'owner', token: {}}, data: {...save(), expectedUid: 'viewer'}}), {code: 'failed-precondition'});
  await assert.rejects(offers.reviewBusinessOffer.run({auth: {uid: 'owner', token: {admin: false}}, data: {}}), {code: 'permission-denied'});
  await offers.saveBusinessOfferForUid('owner', save());
  await assert.rejects(offers.changeBusinessOfferForUid('viewer', {offerId: 'offer0001', requestId: 'steal0001', expectedRevision: 1, action: 'delete'}), {code: 'not-found'});
});
test('contact and unsafe content requires correction; valid drafts still require review', async () => {
  const input = save('offer0001', {draft: draft({terms: 'Call 914-555-1212 for a quote'}), submitForReview: false});
  await offers.saveBusinessOfferForUid('owner', input);
  await assert.rejects(offers.changeBusinessOfferForUid('owner', {offerId: 'offer0001', requestId: 'submit001', expectedRevision: 1, action: 'submit'}), {code: 'invalid-argument'});
  assert.match(offers.offerContentIssue({title: 'stolen goods'}), /cannot/);
  await assert.rejects(offers.saveBusinessOfferForUid('owner', save('offer0002', {draft: draft({expiresAtMs: Date.now() + 31 * 86400000})})), {code: 'invalid-argument'});
});
test('live reads enforce entitlement expiry, deletion, blocks and both approved Party directions', async () => {
  await publish('party0001', {draft: draft({visibility: 'party'})});
  assert.equal((await offers.listPublicBusinessOffersForUid('viewer')).offers.length, 0);
  await db.doc('users/owner/party/viewer').set({mutual: true});
  assert.equal((await offers.listPublicBusinessOffersForUid('viewer')).offers.length, 0);
  await db.doc('users/viewer/party/owner').set({mutual: true});
  assert.equal((await offers.listPublicBusinessOffersForUid('viewer')).offers.length, 1);
  await db.doc('users/viewer/blocks/owner').set({createdAt: new Date()});
  assert.equal((await offers.listPublicBusinessOffersForUid('viewer')).offers.length, 0);
  await db.doc('users/viewer/blocks/owner').delete();
  await db.doc('users/owner/billing/entitlements').set({businessModeActive: true, businessSubscriptionActive: true, subscriptionRenewsAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1)});
  assert.equal((await offers.listPublicBusinessOffersForUid('viewer')).offers.length, 0);
  await account('owner'); await db.doc('accountDeletions/owner').set({status: 'pending'});
  assert.equal((await offers.listPublicBusinessOffersForUid('viewer')).offers.length, 0);
});
test('withdraw and deletion remain available after paid access expires; retries never recreate deleted offers', async () => {
  await publish(); await account('owner', false);
  const withdraw = {offerId: 'offer0001', requestId: 'withdraw1', expectedRevision: 2, action: 'withdraw'};
  await offers.changeBusinessOfferForUid('owner', withdraw);
  assert.equal((await db.doc('publicBusinessOffers/offer0001').get()).exists, false);
  const del = {...withdraw, requestId: 'delete001', expectedRevision: 3, action: 'delete'};
  await offers.changeBusinessOfferForUid('owner', del);
  assert.equal((await offers.changeBusinessOfferForUid('owner', del)).replayed, true);
  assert.equal((await db.doc('businessOffers/offer0001').get()).exists, false);
  await account('owner');
  await assert.rejects(offers.saveBusinessOfferForUid('owner', save('offer0001', {requestId: 'recreate1'})), {code: 'not-found'});
});
test('concurrent approvals enforce the five-live-offer cap and reused IDs cannot mutate a request', async () => {
  for (let i = 0; i < 4; i++) await publish(`offer000${i}`);
  await offers.saveBusinessOfferForUid('owner', save('offer0004'));
  await offers.saveBusinessOfferForUid('owner', save('offer0005'));
  const outcomes = await Promise.allSettled([4, 5].map(i => offers.reviewBusinessOfferForOperator('operator', {offerId: `offer000${i}`, requestId: `review000${i}`, expectedRevision: 1, decision: 'approve'})));
  assert.equal(outcomes.filter(x => x.status === 'fulfilled').length, 1);
  assert.equal((await db.collection('publicBusinessOffers').get()).size, 5);
  const input = save('offer0006'); await offers.saveBusinessOfferForUid('owner', input);
  await assert.rejects(offers.saveBusinessOfferForUid('owner', {...input, draft: {...input.draft, title: 'Different tune-up'}}), {code: 'already-exists'});
});
test('account deletion clears private/public records and operator receipts, then rejects cached retries', async () => {
  await publish(); const input = save('offer0002'); await offers.saveBusinessOfferForUid('owner', input);
  await db.doc('accountDeletions/owner').set({status: 'pending'});
  await offers.eraseDeletedOwnerOffers('owner'); await offers.eraseDeletedOwnerOffers('owner');
  for (const collection of ['businessOffers', 'publicBusinessOffers', 'businessOfferRequests', 'businessOfferBudgets', 'businessOfferTombstones']) assert.equal((await db.collection(collection).get()).size, 0);
  await assert.rejects(offers.saveBusinessOfferForUid('owner', input), {code: 'failed-precondition'});
});
test('bounded public paging continues past filtered rows without exposing a paused canonical record', async () => {
  await publish('aaaa0001'); await publish('bbbb0001');
  await db.doc('businessOffers/aaaa0001').update({status: 'paused'});
  const first = await offers.listPublicBusinessOffersForUid('viewer', {limit: 1});
  assert.deepEqual(first.offers, []); assert.equal(first.nextCursor, 'aaaa0001');
  const second = await offers.listPublicBusinessOffersForUid('viewer', {limit: 1, cursor: first.nextCursor});
  assert.equal(second.offers[0].offerId, 'bbbb0001');
  await assert.rejects(offers.listPublicBusinessOffersForUid('viewer', {limit: 31}), {code: 'invalid-argument'});
});
test('parallel creates at nineteen saved offers cannot exceed the twenty-offer cap', async () => {
  const batch = db.batch();
  for (let i = 0; i < 19; i++) batch.set(db.doc(`businessOffers/seeded00${i}`), {uid: 'owner', status: 'draft', revision: 1});
  await batch.commit();
  const results = await Promise.allSettled(['new00001', 'new00002'].map(id => offers.saveBusinessOfferForUid('owner', save(id))));
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal((await db.collection('businessOffers').where('uid', '==', 'owner').get()).size, 20);
});
