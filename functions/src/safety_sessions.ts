import * as admin from 'firebase-admin';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {createHash} from 'node:crypto';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
export const ACTIVE_MEETUP_STATUSES = new Set(['requested', 'accepted', 'live']);

// No allegation, emergency action, or private safety reason is disclosed.
export async function endSafetySession(uid: string, input: {chatId?: unknown; endChat?: unknown}) {
  const id = typeof input.chatId === 'string' ? input.chatId.trim() : '';
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to end this session.');
  if (!id || id.includes('/') || typeof input.endChat !== 'boolean') {
    throw new HttpsError('invalid-argument', 'Choose a chat or meetup to end.');
  }
  const chatRef = db.doc(`chats/${id}`);
  const meetupRef = db.doc(`meetups/${id}`);
  return db.runTransaction(async tx => {
    const [chat, meetup] = await tx.getAll(chatRef, meetupRef);
    const c = chat.data() || {};
    const m = meetup.data();
    const inChat = Array.isArray(c?.participants) && c.participants.includes(uid);
    const inMeetup = m && [m.aUid, m.bUid].includes(uid);
    if ((!inChat && !inMeetup) || (input.endChat && chat.exists && !inChat) || (meetup.exists && !inMeetup)) {
      throw new HttpsError('permission-denied', 'Only participants can end this session.');
    }
    const now = admin.firestore.Timestamp.now();
    const active = ACTIVE_MEETUP_STATUSES.has(String(m?.status));
    if (active) {
      tx.update(meetupRef, {status: 'cancelled', outcome: 'cancelled',
        cancelledAt: now, closedAt: now, updatedAt: now,
        expiresAt: admin.firestore.FieldValue.delete()});
    }
    if (input.endChat && chat.exists && !c?.closedAt) {
      if (c?.isGroup === true || c?.participants.length > 2) {
        const remaining = c.participants.filter((member: string) => member !== uid);
        tx.update(chatRef, {participants: remaining, updatedAt: now,
          ...(c.moderatorUid === uid && remaining.length ? {moderatorUid: remaining[0]} : {}),
          ...(c.ownerUid === uid && remaining.length ? {ownerUid: remaining[0]} : {})});
      } else {
        tx.update(chatRef, {closedAt: now, updatedAt: now,
          'chatGate.status': 'expired', 'chatGate.expiredAt': now});
      }
    }
    return {ended: true, meetupStatus: active ? 'cancelled' : String(m?.status || ''), chatEnded: input.endChat};
  });
}

export const endMySafetySession = onCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to end this session.');
  return endSafetySession(request.auth.uid, request.data || {});
});

export async function recordMeetupOutcome(id: string, data: FirebaseFirestore.DocumentData, eventTime: admin.firestore.Timestamp) {
  const status = String(data.status);
  if (!['completed', 'cancelled', 'declined', 'expired', 'auto_closed'].includes(status)) return;
  const cycle = data.requestedAt instanceof admin.firestore.Timestamp ? data.requestedAt : data.startedAt instanceof admin.firestore.Timestamp ? data.startedAt : eventTime;
  const receiptId = createHash('sha256').update(`${id}:${cycle.seconds}:${cycle.nanoseconds}`).digest('hex');
  const outcome = status === 'completed' ? 'completed' : status === 'cancelled' ? 'cancelled' : status === 'declined' ? 'declined' : data.autoClosedFromStatus === 'requested' ? 'unanswered' : 'unfinished';
  for (const uid of new Set([data.aUid, data.bUid])) {
    if (typeof uid !== 'string' || !uid || uid.includes('/')) continue;
    await db.runTransaction(async tx => {
      const ref = db.doc(`users/${uid}/meetupOutcomes/${receiptId}`);
      const [prior, user, deletion] = await tx.getAll(ref, db.doc(`users/${uid}`), db.doc(`accountDeletions/${uid}`));
      if (prior.exists || !user.exists || deletion.exists) return;
      // Private, factual history. No allegation, coordinates, peer profile, or
      // automatic trust deduction; expiry cannot establish who was at fault.
      tx.create(ref, {outcome, recordedAt: eventTime});
    });
  }
}

export const onMeetupOutcome = onDocumentWritten({document: 'meetups/{meetupId}', retry: true}, async event => {
  const after = event.data?.after;
  const data = after?.data();
  if (!data || data.status === event.data?.before.data()?.status) return;
  await recordMeetupOutcome(event.params.meetupId, data, after!.updateTime!);
});
