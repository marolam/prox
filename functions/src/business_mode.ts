import * as admin from 'firebase-admin';
import {onCall, HttpsError} from 'firebase-functions/v2/https';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export async function updateBusinessMode(uid: string, active: boolean, preview = false): Promise<{active: boolean}> {
  const reference = db.doc(`users/${uid}/billing/entitlements`);
  return db.runTransaction(async tx => {
    const [entitlement, deletion] = await tx.getAll(reference, db.doc(`accountDeletions/${uid}`));
    if (deletion.exists) throw new HttpsError('failed-precondition', 'Account is being deleted.');
    const data = entitlement.data() || {};
    const prepaid = data.businessSubscriptionActive === true && data.subscriptionRenewsAt instanceof admin.firestore.Timestamp && data.subscriptionRenewsAt.toMillis() > Date.now();
    if (active && data.businessPurchased !== true && !prepaid && !preview) throw new HttpsError('permission-denied', 'Current business access is required.');
    tx.set(reference, {businessModeActive: active, updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    return {active};
  });
}

export const setBusinessModeActive = onCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to manage business mode.');
  if (typeof request.data?.active !== 'boolean') throw new HttpsError('invalid-argument', 'Choose whether business mode is active.');
  const preview = request.auth.token.email_verified === true && String(request.auth.token.email || '').toLowerCase() === 'marty.marola@hotmail.com';
  return updateBusinessMode(request.auth.uid, request.data.active, preview);
});
