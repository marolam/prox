import * as admin from 'firebase-admin';
import {createHash} from 'node:crypto';
import {HttpsError, onCall} from './lib/active_callable';
import {eraseUserData} from './account_lifecycle';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
type ModerationAction = 'suspend' | 'restore' | 'delete';

export async function moderateAccountForAdmin(actorUid: string, targetUid: string,
  action: ModerationAction, reason: string, requestId: string): Promise<{status: string; replayed: boolean}> {
  if (!targetUid || targetUid.length > 128 || targetUid.includes('/') || targetUid === actorUid ||
      !['suspend', 'restore', 'delete'].includes(action) ||
      reason.trim().length < 8 || reason.length > 1000 || !/^[A-Za-z0-9_-]{8,120}$/.test(requestId)) {
    throw new HttpsError('invalid-argument', 'A different target user, action, reason and stable request ID are required.');
  }
  const receiptId = createHash('sha256').update(JSON.stringify([actorUid, requestId])).digest('hex');
  const receiptRef = db.doc(`accountModerationAudit/${receiptId}`);
  const enforcementRef = db.doc(`accountEnforcements/${targetUid}`);
  const existing = await receiptRef.get();
  if (existing.exists && (existing.data()?.targetUid !== targetUid ||
      existing.data()?.action !== action || existing.data()?.reason !== reason.trim())) {
    throw new HttpsError('already-exists', 'This request ID was already used for another moderation action.');
  }
  if (existing.data()?.phase === 'complete') return {status: existing.data()!.status, replayed: true};
  let target: admin.auth.UserRecord | undefined;
  try {
    target = await admin.auth().getUser(targetUid);
  } catch (error) {
    if ((error as {code?: string}).code !== 'auth/user-not-found') throw error;
    if (action !== 'delete' || !existing.exists) throw new HttpsError('not-found', 'The target account does not exist.');
  }
  if (target?.customClaims?.admin === true) throw new HttpsError('permission-denied', 'Administrator accounts require separate privileged recovery.');
  const status = action === 'restore' ? 'active' : action === 'delete' ? 'deleted' : 'suspended';
  const claimed = await db.runTransaction(async tx => {
    const [receipt, enforcement, deletion] = await tx.getAll(receiptRef, enforcementRef, db.doc(`accountDeletions/${targetUid}`));
    if (receipt.exists && (receipt.data()?.targetUid !== targetUid || receipt.data()?.action !== action ||
        receipt.data()?.reason !== reason.trim())) throw new HttpsError('already-exists', 'This request ID was already used.');
    if (receipt.data()?.phase === 'complete') return false;
    const lastUpdate = receipt.data()?.updatedAt;
    if (receipt.data()?.phase === 'enforcing' && lastUpdate instanceof admin.firestore.Timestamp &&
        Date.now() - lastUpdate.toMillis() < 10 * 60 * 1000) {
      throw new HttpsError('failed-precondition', 'This moderation action is running. Wait for completion before retrying.');
    }
    if (enforcement.data()?.pendingRequest && enforcement.data()?.pendingRequest !== receiptId) {
      throw new HttpsError('failed-precondition', 'Another moderation action is pending. Retry that action first.');
    }
    if (action === 'restore' && (deletion.exists || enforcement.data()?.status === 'deleted')) {
      throw new HttpsError('failed-precondition', 'A deleted account cannot be restored.');
    }
    tx.set(receiptRef, {actorUid, targetUid, action, reason: reason.trim(), requestId, status, phase: 'enforcing',
      updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    tx.set(enforcementRef, {pendingRequest: receiptId,
      ...(action !== 'restore' ? {status, publicMessage: 'This account is restricted. Contact support to appeal.'} : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    if (action !== 'restore') tx.set(db.doc(`users/${targetUid}`), {
      disabled: true, banned: action === 'delete', updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return true;
  });
  if (!claimed) return {status, replayed: true};
  try {
    if (target) {
      await admin.auth().updateUser(targetUid, {disabled: action !== 'restore'});
      if (action !== 'restore') await admin.auth().revokeRefreshTokens(targetUid);
    }
    if (action === 'delete') {
      await eraseUserData(targetUid);
      if (target) {
        try { await admin.auth().deleteUser(targetUid); }
        catch (error) { if ((error as {code?: string}).code !== 'auth/user-not-found') throw error; }
      }
    }
    await db.runTransaction(async tx => {
      const [receipt, user] = await tx.getAll(receiptRef, db.doc(`users/${targetUid}`));
      if (receipt.data()?.phase === 'complete') return;
      if (action === 'restore') tx.set(db.doc(`users/${targetUid}`), {
        disabled: false, banned: false, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(['disabled', 'banned', 'deactivated'].includes(user.data()?.status) ? {status: 'active'} : {}),
      }, {merge: true});
      tx.set(enforcementRef, {status, publicMessage: status === 'active' ? '' : 'This account is restricted. Contact support to appeal.',
        pendingRequest: admin.firestore.FieldValue.delete(), updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
      tx.update(receiptRef, {phase: 'complete', completedAt: admin.firestore.FieldValue.serverTimestamp()});
    });

    return {status, replayed: false};
  } catch (error) {
    console.error('Account moderation incomplete', {actorUid, targetUid, action, receiptId, error});
    await receiptRef.set({phase: 'failed', updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    throw new HttpsError('internal', 'Moderation is incomplete. Access remains restricted; retry the same request ID.');
  }
}

export const moderateAccount = onCall({region: 'us-central1', timeoutSeconds: 540}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in as an administrator.');
  if (request.auth.token.admin !== true) throw new HttpsError('permission-denied', 'An administrator account is required.');
  if (request.data?.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'The signed-in administrator changed.');
  const {targetUid, action, reason, requestId} = request.data || {};
  if (typeof targetUid !== 'string' || typeof action !== 'string' || typeof reason !== 'string' || typeof requestId !== 'string' ||
      !['suspend', 'restore', 'delete'].includes(action)) throw new HttpsError('invalid-argument', 'Invalid moderation request.');
  return moderateAccountForAdmin(request.auth.uid, targetUid, action as ModerationAction, reason, requestId);
});

export const getAccountModerationStatus = onCall({region: 'us-central1'}, async request => {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'An administrator account is required.');
  }
  if (request.data?.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'The signed-in administrator changed.');
  const targetUid = request.data?.targetUid;
  if (typeof targetUid !== 'string' || !targetUid || targetUid.length > 128 || targetUid.includes('/')) {
    throw new HttpsError('invalid-argument', 'A valid target user UID is required.');
  }
  const enforcement = (await db.doc(`accountEnforcements/${targetUid}`).get()).data();
  if (!enforcement?.pendingRequest) return {status: enforcement?.status || 'no_enforcement', pending: null};
  const receipt = (await db.doc(`accountModerationAudit/${enforcement.pendingRequest}`).get()).data();
  if (!receipt || receipt.targetUid !== targetUid || typeof receipt.requestId !== 'string') {
    throw new HttpsError('internal', 'The pending moderation audit is unavailable.');
  }
  if (receipt.actorUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'Another administrator owns the pending action. Ask them to retry it.');
  return {status: enforcement.status || 'restricted', phase: receipt.phase,
    pending: {targetUid, action: receipt.action, reason: receipt.reason, requestId: receipt.requestId, expectedUid: request.auth.uid}};
});
