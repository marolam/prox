import * as admin from 'firebase-admin';
import {createHash} from 'node:crypto';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {onCall, HttpsError} from 'firebase-functions/v2/https';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export async function recordCompletedMeetup(meetupId: string, callerUid?: string): Promise<void> {
  if (!meetupId || meetupId.includes('/')) throw new HttpsError('invalid-argument', 'A valid meetup is required.');
  const meetupRef = db.doc(`meetups/${meetupId}`);
  const snapshot = await meetupRef.get();
  const data = snapshot.data() || {};
  const uids = [...new Set([String(data.aUid || ''), String(data.bUid || '')])];
  if (callerUid && !uids.includes(callerUid)) throw new HttpsError('permission-denied', 'Only a meetup participant can sync it.');
  if (uids.length !== 2 || uids.some(uid => !uid) || data.status !== 'completed' || data.aArrived !== true || data.bArrived !== true || !(data.completedAt instanceof admin.firestore.Timestamp)) return;
  const completed = data.completedAt as admin.firestore.Timestamp;
  const receiptId = createHash('sha256').update(`${meetupId}:${completed.seconds}:${completed.nanoseconds}`).digest('hex');
  for (const uid of uids) {
    await db.runTransaction(async tx => {
      const receipt = db.doc(`users/${uid}/completedMeetups/${receiptId}`);
      const [prior, user, fresh, deletion] = await tx.getAll(receipt, db.doc(`users/${uid}`), meetupRef, db.doc(`accountDeletions/${uid}`));
      if (prior.exists || deletion.exists || !user.exists) return;
      const current = fresh.data();
      if (current?.status !== 'completed' || current.aArrived !== true || current.bArrived !== true || !completed.isEqual(current.completedAt)) return;
      const referrer = String(user.data()?.referrer || '');
      const referral = referrer && referrer !== uid && !referrer.includes('/') ? db.doc(`users/${referrer}/referrals/${uid}`) : null;
      const referralSnap = referral ? await tx.get(referral) : null;
      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.create(receipt, {meetupId, completedAt: completed, recordedAt: now});
      tx.set(db.doc(`users/${uid}/meta/points`), {completedMeetups: admin.firestore.FieldValue.increment(1), updatedAt: now}, {merge: true});
      tx.set(db.doc(`users/${uid}/stats/current`), {completedMeetups: admin.firestore.FieldValue.increment(1), updatedAt: now}, {merge: true});
      tx.create(db.doc(`users/${uid}/meta/points/events/meetup_${receiptId}`), {eventId: `meetup_${receiptId}`, amount: 0, category: 'meetup_completed', reason: 'Meetup completed', meetupId, timestamp: now});
      if (referral && referralSnap?.exists) {
        const priorReferral = referralSnap.data() || {};
        const count = Math.max(0, Number(priorReferral.meetupsCompleted) || 0) + 1;
        const eligible = priorReferral.inPersonVerified === true && priorReferral.rewardEligible === true;
        tx.update(referral, {meetupsCompleted: count, rewardGranted: priorReferral.rewardGranted === true || (eligible && count >= 5), updatedAt: now});
      }
    });
  }
}

export const onMeetupCompletedAccounting = onDocumentWritten({document: 'meetups/{meetupId}', retry: true}, async event => {
  const data = event.data?.after.data();
  if (data?.status !== 'completed' || event.data?.before.data()?.status === 'completed') return;
  await recordCompletedMeetup(event.params.meetupId);
});

export const syncCompletedMeetup = onCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to sync a meetup.');
  await recordCompletedMeetup(String(request.data?.meetupId || ''), request.auth.uid);
  return {synced: true};
});
