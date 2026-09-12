import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions/v1';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

async function deleteQuery(query: FirebaseFirestore.Query): Promise<void> {
  for (;;) {
    const page = await query.limit(100).get();
    if (page.empty) return;
    for (const doc of page.docs) await db.recursiveDelete(doc.ref);
  }
}

/** Idempotent, bounded batches; usable by the callable and auth deletion retries. */
export async function eraseUserData(uid: string): Promise<void> {
  const deletionRef = db.doc(`accountDeletions/${uid}`);
  await deletionRef.set({status: 'processing', requestedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  // The rules use this marker to stop writes from a device with a cached ID token.
  const chatQueries = ['chats', 'threads'].map(collection =>
    db.collection(collection).where('participants', 'array-contains', uid));
  for (const query of chatQueries) {
    for (;;) {
      const page = await query.limit(100).get();
      if (page.empty) break;
      for (const chat of page.docs) {
        await deleteQuery(chat.ref.collection('messages').where('from', '==', uid));
        await deleteQuery(chat.ref.collection('messages').where('senderUid', '==', uid));
        await Promise.all([
          chat.ref.collection('typing').doc(uid).delete(),
          chat.ref.collection('members').doc(uid).delete(),
          admin.storage().bucket().deleteFiles({prefix: `chatMedia/${chat.id}/${uid}-`}),
        ]);
        const data = chat.data();
        const remaining = (data.participants as string[]).filter(id => id !== uid);
        await chat.ref.update({
          participants: remaining,
          lastMessage: '',
          lastFrom: admin.firestore.FieldValue.delete(),
          ...(data.moderatorUid === uid ? {moderatorUid: remaining[0] || ''} : {}),
          ...(data.ownerUid === uid ? {ownerUid: remaining[0] || ''} : {}),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
  }
  for (const collection of ['matches', 'meetups', 'meetupRequests', 'ratings', 'ratings_meetups']) {
    for (const field of ['aUid', 'bUid', 'requesterUid', 'recipientUid', 'ownerUid', 'raterUid', 'ratedUid']) {
      await deleteQuery(db.collection(collection).where(field, '==', uid));
    }
    await deleteQuery(db.collection(collection).where('participants', 'array-contains', uid));
  }
  for (const collection of ['bugReports', 'incidents', 'feedback', 'supportTickets', 'support_tickets', 'referralCodes', 'referralSingleUseTokens', 'keywordReports', 'metricsEvents', 'referralDownloadClicks', 'checkoutSessions']) {
    for (const field of ['uid', 'ownerUid', 'userId', 'reporterUid', 'actor', 'referrerUid', 'completedByUid', 'targetUid']) {
      await deleteQuery(db.collection(collection).where(field, '==', uid));
    }
  }
  // Remove reciprocal membership and notes without scanning every account.
  for (const group of ['party', 'blocks', 'referrals']) {
    await deleteQuery(db.collectionGroup(group).where('uid', '==', uid));
  }
  await deleteQuery(db.collection('trustFeedbackProjection').where('otherUid', '==', uid));
  await deleteQuery(db.collection('partyConnections').where('members', 'array-contains', uid));
  await deleteQuery(db.collection('paymentReconciliation').where('uid', '==', uid));
  for (const collection of ['profiles', 'publicProfiles', 'partyNetworkRequests', 'partyNetworkRateLimits', 'keywordEnforcement', 'technician_profiles', 'referralAttributions']) {
    await db.recursiveDelete(db.collection(collection).doc(uid));
  }
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await Promise.all([
    admin.storage().bucket().deleteFiles({prefix: `profiles/${uid}/`}),
    admin.storage().bucket().deleteFiles({prefix: `users/${uid}/`}),
  ]);
  await deletionRef.set({status: 'complete', completedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
}

export const deleteMyAccount = onCall({region: 'us-central1', timeoutSeconds: 540}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in before deleting your account.');
  if (request.data?.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'The signed-in account changed. Reopen account deletion.');
  const authTime = Number(request.auth.token.auth_time || 0) * 1000;
  const anonymous = request.auth.token.firebase?.sign_in_provider === 'anonymous';
  if (!anonymous && (!authTime || Date.now() - authTime > 5 * 60 * 1000)) {
    throw new HttpsError('failed-precondition', 'Sign in again to confirm account deletion.');
  }
  const uid = request.auth.uid;
  await eraseUserData(uid);
  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    if ((error as {code?: string}).code !== 'auth/user-not-found') throw error;
  }
  return {deleted: true};
});

export const onAuthDelete = functions.runWith({timeoutSeconds: 540, failurePolicy: true})
  .auth.user().onDelete(async user => { await eraseUserData(user.uid); });

// Per-receipt projection, rather than increment-on-trigger, remains correct when
// Firestore delivers the same event twice or an older event arrives late.
export const onTrustFeedbackWrite = onDocumentWritten({document: 'users/{uid}/trustFeedback/{meetupId}', retry: true}, async event => {
  const reference = event.data?.after.ref || event.data?.before.ref;
  if (!reference) return;
  const projection = db.doc(`trustFeedbackProjection/${event.params.uid}__${event.params.meetupId}`);
  await db.runTransaction(async tx => {
    const [fresh, previous] = await tx.getAll(reference, projection);
    const data = fresh.data();
    const old = previous.data();
    const target = String(data?.otherUid || old?.otherUid || '');
    if (!target) return;
    const [targetUser, targetDeletion] = await tx.getAll(db.doc(`users/${target}`), db.doc(`accountDeletions/${target}`));
    if (!targetUser.exists || targetDeletion.exists) {
      if (previous.exists) tx.delete(projection);
      return;
    }
    if (old && data && old.otherUid === target && old.positive === data.wouldMeetAgain) return;
    const totalDelta = (data ? 1 : 0) - (old ? 1 : 0);
    const positiveDelta = (data?.wouldMeetAgain === true ? 1 : 0) - (old?.positive === true ? 1 : 0);
    tx.set(db.doc(`users/${target}/stats/trust`), {
      total: admin.firestore.FieldValue.increment(totalDelta),
      positive: admin.firestore.FieldValue.increment(positiveDelta),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    if (data) tx.set(projection, {otherUid: target, positive: data.wouldMeetAgain === true});
    else tx.delete(projection);
  });
});
