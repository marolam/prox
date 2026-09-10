import * as admin from 'firebase-admin';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const storeCatalog: Record<string, {cost: number; requiresBusiness: boolean; entitlement: string}> = {
  "service_single_keyword_match_unlock": {
    "cost": 65,
    "requiresBusiness": false,
    "entitlement": "singleKeywordMatchModeUnlocked"
  },
  "service_reciprocal_match_unlock": {
    "cost": 110,
    "requiresBusiness": false,
    "entitlement": "reciprocalKeywordMatchModeUnlocked"
  },
  "service_keyword_chain_unlock": {
    "cost": 140,
    "requiresBusiness": false,
    "entitlement": "keywordChainMatchModeUnlocked"
  },
  "biz_high_radius_unlock": {
    "cost": 90,
    "requiresBusiness": true,
    "entitlement": "highRadiusUnlocked"
  }
};
const catalog: Record<string, number> = {
  biz_monthly_subscription: 200,
  biz_onetime_unlock: 1200,
};

export async function purchasePointsEntitlement(uid: string, sku: string, requestId: string) {
  const item = storeCatalog[sku];
  const cost = catalog[sku] || item?.cost;
  if (!cost || !/^[a-zA-Z0-9_-]{16,100}$/.test(requestId)) {
    throw new HttpsError('invalid-argument', 'A supported item and unique purchase request ID are required.');
  }
  const points = db.doc(`users/${uid}/meta/points`);
  const entitlements = db.doc(`users/${uid}/billing/entitlements`);
  const invoice = db.doc(`users/${uid}/billing/invoices/items/points_${requestId}`);
  return db.runTransaction(async tx => {
    const purchase = db.doc(`users/${uid}/store/purchases/items/${sku}`);
    const [balance, entitlement, prior, deletion, owned] = await tx.getAll(points, entitlements, invoice, db.doc(`accountDeletions/${uid}`), purchase);
    if (deletion.exists) throw new HttpsError('failed-precondition', 'This account is being deleted.');
    if (prior.exists) {
      if (prior.data()?.sku !== sku) throw new HttpsError('already-exists', 'Purchase request ID already used.');
      return {purchased: true, invoiceId: invoice.id, replayed: true};
    }
    if (item && owned.exists) return {purchased: true, alreadyOwned: true, pointsSpent: 0};
    if (item?.requiresBusiness) {
      const ent = entitlement.data() || {};
      const active = ent.businessSubscriptionActive === true && ent.subscriptionRenewsAt instanceof admin.firestore.Timestamp && ent.subscriptionRenewsAt.toMillis() > Date.now();
      if (ent.businessPurchased !== true && !active) throw new HttpsError('permission-denied', 'Business access is required.');
    }
    if (sku === 'biz_onetime_unlock' && entitlement.data()?.businessPurchased === true) {
      return {purchased: true, alreadyOwned: true};
    }
    const currentExpiry = entitlement.data()?.subscriptionRenewsAt;
    if (sku === 'biz_monthly_subscription' && entitlement.data()?.businessSubscriptionActive === true && currentExpiry instanceof admin.firestore.Timestamp && currentExpiry.toMillis() > Date.now()) return {purchased: true, alreadyOwned: true, pointsSpent: 0};
    const available = Number(balance.data()?.currentPoints || 0);
    if (!Number.isSafeInteger(available) || available < cost) throw new HttpsError('failed-precondition', 'Not enough points.');
    const now = admin.firestore.FieldValue.serverTimestamp();
    const patch: Record<string, unknown> = {lastSku: sku, lastPaymentMethod: 'points', updatedAt: now};
    if (sku === 'biz_onetime_unlock' || sku === 'biz_monthly_subscription') {patch.businessStoreUnlocked = true; patch.businessWalletUnlocked = true;}
    if (sku === 'biz_onetime_unlock') {patch.businessPurchased = true; patch.businessPurchasedSourceSessionId = invoice.id; patch.businessLifetimePaymentCount = 1;}
    else if (sku === 'biz_monthly_subscription') {
      const expiry = entitlement.data()?.subscriptionRenewsAt;
      const current = expiry instanceof admin.firestore.Timestamp ? expiry.toMillis() : 0;
      patch.businessSubscriptionActive = true;
      patch.businessSubscriptionSourceSessionId = invoice.id;
      patch.subscriptionRenewsAt = admin.firestore.Timestamp.fromMillis(Math.max(Date.now(), current) + 30 * 86400000);
    }
    if (item) {
      patch[item.entitlement] = true;
      tx.create(purchase, {sku, costPoints: cost, requiresBusiness: item.requiresBusiness, purchasedAt: now});
    }
    tx.update(points, {currentPoints: available - cost, updatedAt: now});
    tx.set(entitlements, patch, {merge: true});
    tx.create(invoice, {invoiceId: invoice.id, sku, amountPoints: cost, amountUsd: 0, paymentMethod: 'points', status: 'paid', createdAt: now});
    tx.create(points.collection('events').doc(invoice.id), {eventId: invoice.id, amount: -cost, category: 'purchase', reason: sku, timestamp: now});
    return {purchased: true, invoiceId: invoice.id, replayed: false, pointsSpent: cost};
  });
}

export const purchaseWithPoints = onCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to purchase.');
  return purchasePointsEntitlement(request.auth.uid, String(request.data?.sku || ''), String(request.data?.requestId || ''));
});
