const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Dashboard metrics tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit'});
const db = admin.firestore();
const {recomputeDashboardMetricsSnapshot} = require('../lib/dashboard_metrics');
const {updateBusinessMode} = require('../lib/business_mode');
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(response.status, 200);
});
after(async () => { await admin.app().delete(); });
const now = Date.UTC(2026, 10, 5, 12), today = admin.firestore.Timestamp.fromMillis(now - 1000);

test('metrics use trusted registration dates and exact active paid billing paths with owner deletion guards', async () => {
  await db.doc('users/alice').set({createdAt: today, businessEnabled: true});
  await db.doc('users/bob').set({createdAt: admin.firestore.Timestamp.fromMillis(0)});
  await db.doc('users/deleted').set({createdAt: today});
  await db.doc('accountDeletions/deleted').set({status: 'complete'});
  await db.doc('users/alice/billing/entitlements').set({businessModeActive: true, businessPurchased: true, businessModeEnabledAt: today});
  await db.doc('users/bob/billing/entitlements').set({businessModeActive: true, businessSubscriptionActive: true,
    subscriptionRenewsAt: admin.firestore.Timestamp.fromMillis(now - 1), businessModeEnabledAt: today});
  await db.doc('users/deleted/billing/entitlements').set({businessModeActive: true, businessPurchased: true, businessModeEnabledAt: today});
  await db.doc('users/alice/billing/other').set({businessModeActive: true, businessPurchased: true});
  await db.doc('foreign/alice/entitlements/fake').set({businessModeActive: true, businessPurchased: true});
  await db.doc('users/orphan/billing/entitlements').set({businessModeActive: true, businessPurchased: true});
  await db.doc('users/alice/presence/current').set({kind: 'current', geopoint: new admin.firestore.GeoPoint(1, 1)});
  await db.doc('users/bob/presence/historical').set({kind: 'historical', geopoint: new admin.firestore.GeoPoint(1, 1)});
  await db.doc('users/deleted/presence/current').set({kind: 'current', geopoint: new admin.firestore.GeoPoint(1, 1)});
  await db.doc('foreign/alice/presence/current').set({kind: 'current', geopoint: new admin.firestore.GeoPoint(1, 1)});
  await db.doc('profiles/alice').set({activeKeywords: ['Local Help']});
  await db.doc('profiles/deleted').set({activeKeywords: ['Deleted keyword']});
  await db.doc('profiles/orphan').set({activeKeywords: ['Orphan keyword']});
  await recomputeDashboardMetricsSnapshot({now, registrationTimes: {alice: now - 86400000, bob: now - 1000, deleted: now - 1000}});
  const metrics = (await db.doc('dashboard/metrics').get()).data();
  assert.equal(metrics.totalUsers, 2);
  assert.equal(metrics.newUsersToday, 1);
  assert.equal(metrics.totalBusinessModeUsers, 1);
  assert.equal(metrics.newBusinessModeUsersToday, 1);
  assert.equal(metrics.geofenceUsersCovered, 1);
  assert.equal(metrics.geofenceCoverageRatio, 0.5);
  assert.deepEqual(metrics.topKeywords, [{keyword: 'local help', count: 1}]);
});

test('legacy unknown activation dates never become today from an unrelated billing update', async () => {
  await db.doc('users/alice').set({businessEnabled: true});
  await db.doc('users/alice/billing/entitlements').set({businessModeActive: true, businessPurchased: true, updatedAt: today});
  await db.doc('dashboard/metrics').set({newBusinessModeUsersToday: 99});
  await recomputeDashboardMetricsSnapshot({now, registrationTimes: {alice: now - 86400000}});
  const metrics = (await db.doc('dashboard/metrics').get()).data();
  assert.equal(metrics.totalBusinessModeUsers, 1);
  assert.equal(metrics.newUsersToday, 0);
  assert.equal(metrics.businessActivationDatesKnown, 0);
  assert.equal(metrics.businessActivationDatesUnknown, 1);
  assert.equal('newBusinessModeUsersToday' in metrics, false);
});

test('a genuine empty population publishes current zero with an atomic keyword-count snapshot', async () => {
  await recomputeDashboardMetricsSnapshot({now, registrationTimes: {}});
  const metrics = (await db.doc('dashboard/metrics').get()).data();
  const keywords = (await db.doc('dashboard/keywordCounts').get()).data();
  assert.equal(metrics.totalUsers, 0);
  assert.equal(metrics.newUsersToday, 0);
  assert.equal(metrics.totalBusinessModeUsers, 0);
  assert.equal(metrics.newBusinessModeUsersToday, 0);
  assert.equal(metrics.totalPointsPaidOut, 0);
  assert.equal(metrics.updatedAt.toMillis(), keywords.updatedAt.toMillis());
  assert.deepEqual(metrics.topKeywords, []);
});

test('existing credited referral/support payout meaning remains intact and excludes foreign or deleted owners', async () => {
  await db.doc('users/alice').set({});
  await db.doc('users/deleted').set({});
  await db.doc('accountDeletions/deleted').set({status: 'complete'});
  await db.doc('users/alice/referrals/first').set({rewardCredited: true, rewardPoints: 7});
  await db.doc('users/alice/referrals/legacy_fallback').set({rewardCredited: true});
  await db.doc('users/alice/referrals/not_credited').set({rewardCredited: false, rewardPoints: 1000});
  await db.doc('users/deleted/referrals/ignored').set({rewardCredited: true, rewardPoints: 1000});
  await db.doc('foreign/alice/referrals/ignored').set({rewardCredited: true, rewardPoints: 1000});
  await db.doc('support_tickets/paid').set({payoutCredited: true, payoutPoints: 3, technicianId: 'alice'});
  await db.doc('support_tickets/legacy_fallback').set({payoutCredited: true, technicianId: 'alice'});
  await db.doc('support_tickets/deleted').set({payoutCredited: true, payoutPoints: 1000, technicianId: 'deleted'});
  await recomputeDashboardMetricsSnapshot({now, registrationTimes: {alice: now - 86400000}});
  const metrics = (await db.doc('dashboard/metrics').get()).data();
  assert.equal(metrics.totalReferralPointsPaidOut, 12);
  assert.equal(metrics.totalSupportPointsPaidOut, 4);
  assert.equal(metrics.totalPointsPaidOut, 16);
});

test('real mode activation records its first date once without fabricating a legacy active date on retry', async () => {
  const reference = db.doc('users/alice/billing/entitlements');
  await reference.set({businessPurchased: true});
  await updateBusinessMode('alice', true);
  const first = (await reference.get()).get('businessModeEnabledAt');
  assert.ok(first instanceof admin.firestore.Timestamp);
  await updateBusinessMode('alice', true);
  assert.equal((await reference.get()).get('businessModeEnabledAt').toMillis(), first.toMillis());
  await updateBusinessMode('alice', false);
  await updateBusinessMode('alice', true);
  assert.equal((await reference.get()).get('businessModeEnabledAt').toMillis(), first.toMillis());
  await db.doc('users/legacy/billing/entitlements').set({businessPurchased: true, businessModeActive: true});
  await updateBusinessMode('legacy', true);
  assert.equal((await db.doc('users/legacy/billing/entitlements').get()).get('businessModeEnabledAt'), undefined);
});

test('keyword metrics follow modern profile edits and clears while retaining safe legacy fallback', async () => {
  await db.doc('users/alice').set({keywords: {'Searching For': ['Repair'], 'Can Provide': ['Transport', 'Repair']}});
  await db.doc('profiles/alice').set({activeKeywords: ['stale tag']});
  await db.doc('users/cleared').set({keywords: {'Searching For': [], 'Can Provide': []}});
  await db.doc('profiles/cleared').set({activeKeywords: ['cleared stale tag']});
  await db.doc('users/legacy').set({});
  await db.doc('profiles/legacy').set({activeKeywords: ['Legacy Help']});
  await recomputeDashboardMetricsSnapshot({now, registrationTimes: {alice: 0, cleared: 0, legacy: 0}});
  const rows = (await db.doc('dashboard/metrics').get()).get('topKeywords');
  const counts = Object.fromEntries(rows.map(row => [row.keyword, row.count]));
  assert.deepEqual(counts, {repair: 1, transport: 1, 'legacy help': 1});
});
