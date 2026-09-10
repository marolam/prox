import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export async function claimReward(uid: string, category: string, contextId: string) {
  if (!/^[A-Za-z0-9_-]{1,120}$/.test(contextId)) throw new HttpsError('invalid-argument', 'A verified source is required.');
  if (!['policy_ack', 'support', 'feedback'].includes(category)) throw new HttpsError('invalid-argument', 'Unsupported reward.');
  const policy = category === 'policy_ack' ? {conduct: {version: 'conduct_v1', points: 10}, business_rules: {version: 'business_rules_v1', points: 15}}[contextId] : null;
  if (category === 'policy_ack' && !policy) throw new HttpsError('invalid-argument', 'Unsupported policy.');
  const source = policy ? db.doc(`users/${uid}/meta/policyAcks`) : db.doc(`${category === 'support' ? 'support_tickets' : 'feedback'}/${contextId}`);
  const reward = db.doc(`users/${uid}/rewardClaims/${category}_${policy?.version || contextId}`);
  const daily = db.doc(`users/${uid}/rewardLimits/${new Date().toISOString().slice(0, 10)}`);
  return db.runTransaction(async tx => {
    const [prior, verified, limit, deletion] = await tx.getAll(reward, source, daily, db.doc(`accountDeletions/${uid}`));
    if (deletion.exists) throw new HttpsError('failed-precondition', 'Account is being deleted.');
    if (prior.exists) return {awarded: false, points: 0, alreadyClaimed: true};
    const data = verified.data() || {};
    let points = 0;
    if (policy) {
      const ack = data.versions?.[policy.version] || data[`versions.${policy.version}`];
      if (ack !== true && ack?.accepted !== true) throw new HttpsError('failed-precondition', 'Accept the policy first.');
      points = policy.points;
    } else if (category === 'support') {
      if (data.technicianId !== uid || data.status !== 3 || data.payoutGranted !== true || data.doneDealConfirmed !== true || data.thumbsUp !== true) {
        throw new HttpsError('failed-precondition', 'Support reward requires a confirmed support ticket.');
      }
      // Shares the existing trigger marker, preventing trigger/callable double credit.
      if (data.payoutCredited === true) return {awarded: false, points: 0, alreadyClaimed: true};
      points = 1;
      tx.update(source, {payoutCredited: true, payoutCreditedAt: admin.firestore.FieldValue.serverTimestamp()});
    } else {
      if (data.uid !== uid || String(data.text || '').trim().length < 20) throw new HttpsError('failed-precondition', 'Submit detailed feedback first.');
      if (Number(limit.data()?.feedback || 0) >= 1) return {awarded: false, points: 0, dailyLimitReached: true};
      points = 2;
      tx.set(daily, {feedback: admin.firestore.FieldValue.increment(1)}, {merge: true});
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.create(reward, {category, contextId, points, createdAt: now});
    tx.set(db.doc(`users/${uid}/meta/points`), {currentPoints: admin.firestore.FieldValue.increment(points), totalPoints: admin.firestore.FieldValue.increment(points), updatedAt: now}, {merge: true});
    tx.create(db.doc(`users/${uid}/meta/points/events/${reward.id}`), {eventId: reward.id, amount: points, category, reason: contextId, timestamp: now});
    return {awarded: true, points};
  });
}

export const claimVerifiedReward = onCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to claim a reward.');
  return claimReward(request.auth.uid, String(request.data?.category || ''), String(request.data?.contextId || ''));
});

export const cancelMySubscription = onCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to manage your subscription.');
  const ref = db.doc(`users/${request.auth.uid}/billing/entitlements`);
  const [snap, deletion] = await db.getAll(ref, db.doc(`accountDeletions/${request.auth.uid}`));
  if (deletion.exists) throw new HttpsError('failed-precondition', 'Account is being deleted.');
  const data = snap.data() || {};
  if (data.providerSubscriptionId) {
    // Never report a cancellation until an actual recurring provider confirms it.
    throw new HttpsError('failed-precondition', 'Manage this recurring subscription through your payment provider.');
  }
  // Current points/Square checkout grants are prepaid 30-day access, never recurring.
  await ref.set({autoRenew: false, cancelAtPeriodEnd: true, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  return {cancelled: true, accessUntil: data.subscriptionRenewsAt?.toMillis() || null, recurringBilling: false};
});
