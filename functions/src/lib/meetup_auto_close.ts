import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions/v1';
import {ACTIVE_MEETUP_STATUSES} from '../safety_sessions';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export function meetupDeadline(data: FirebaseFirestore.DocumentData, createdAt: admin.firestore.Timestamp): number {
  if (data.expiresAt instanceof admin.firestore.Timestamp) return data.expiresAt.toMillis();
  const base = data.status === 'requested' ? data.requestedAt : data.startedAt ?? data.acceptedAt;
  const timestamp = base instanceof admin.firestore.Timestamp ? base : createdAt;
  return timestamp.toMillis() + (data.status === 'requested' ? 5 * 60000 : 12 * 3600000);
}

export async function closeExpiredMeetup(ref: FirebaseFirestore.DocumentReference, now = admin.firestore.Timestamp.now()): Promise<boolean> {
  return db.runTransaction(async tx => {
    const doc = await tx.get(ref);
    const data = doc.data();
    if (!data || !ACTIVE_MEETUP_STATUSES.has(data.status) || meetupDeadline(data, doc.createTime!) > now.toMillis()) return false;
    // Re-read so a stale sweep cannot overwrite a terminal outcome.
    const completed = data.aArrived === true && data.bArrived === true;
    tx.update(ref, completed ? {
      status: 'completed', outcome: 'completed', completedAt: now, updatedAt: now,
      ratingStartedAt: now, ratingExpiresAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + 24 * 3600000),
    } : {
      status: 'auto_closed', outcome: data.status === 'requested' ? 'unanswered' : 'unfinished',
      autoClosedAt: now, closedAt: now, autoClosedFromStatus: data.status,
      updatedAt: now, expiresAt: admin.firestore.FieldValue.delete(),
    });
    return true;
  });
}

export async function sweepExpiredMeetups(now = admin.firestore.Timestamp.now()): Promise<number> {
  let closed = 0;
  for (const status of ACTIVE_MEETUP_STATUSES) {
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    do {
      let query = db.collection('meetups').where('status', '==', status)
        .orderBy(admin.firestore.FieldPath.documentId()).limit(300);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      for (let i = 0; i < page.docs.length; i += 20) {
        const results = await Promise.all(page.docs.slice(i, i + 20).map(doc => closeExpiredMeetup(doc.ref, now)));
        closed += results.filter(Boolean).length;
      }
      cursor = page.size === 300 ? page.docs[page.docs.length - 1] : undefined;
    } while (cursor);
  }
  return closed;
}

export const sweepMeetupAutoClose = functions.runWith({timeoutSeconds: 540}).pubsub
  .schedule('every 5 minutes').timeZone('UTC').onRun(async () => {
    const totalClosed = await sweepExpiredMeetups();
    await db.doc('dashboard/meetupAutoCloseSweep').set({totalClosed,
      lastRunAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  });
