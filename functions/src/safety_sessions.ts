import * as admin from 'firebase-admin';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {createHash} from 'node:crypto';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
export const ACTIVE_MEETUP_STATUSES = new Set(['requested', 'accepted', 'live']);

const NO_SHOW_WINDOW_DAYS = 30;
const NO_SHOW_LOCK_LADDER_MS = [15 * 60 * 1000, 2 * 60 * 60 * 1000, 24 * 60 * 60 * 1000, 72 * 60 * 60 * 1000];
const NO_SHOW_TRUST_LADDER = [1, 3, 6, 10];

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

function resolveTerminalOutcome(data: FirebaseFirestore.DocumentData, status: string): string {
  if (status === 'completed') return 'completed';
  if (status === 'cancelled') return 'cancelled';
  if (status === 'declined') return 'declined';
  const explicit = String(data.outcome ?? '').trim().toLowerCase();
  if (explicit === 'unanswered' || explicit === 'unfinished' || explicit === 'no_show') return explicit;
  return data.autoClosedFromStatus === 'requested' ? 'unanswered' : 'unfinished';
}

function noShowParticipantIds(data: FirebaseFirestore.DocumentData): string[] {
  const aUid = typeof data.aUid === 'string' ? data.aUid.trim() : '';
  const bUid = typeof data.bUid === 'string' ? data.bUid.trim() : '';
  const aArrived = data.aArrived === true;
  const bArrived = data.bArrived === true;
  if (!aUid || !bUid || aArrived === bArrived) return [];
  return aArrived ? [bUid] : [aUid];
}

async function applyNoShowPenalty(
  uid: string,
  meetupId: string,
  cycle: admin.firestore.Timestamp,
  eventTime: admin.firestore.Timestamp,
): Promise<void> {
  if (!uid || uid.includes('/')) return;
  const receiptId = createHash('sha256').update(`${meetupId}:${uid}:${cycle.seconds}:${cycle.nanoseconds}:no_show`).digest('hex');
  const penaltyRef = db.doc(`users/${uid}/meetupNoShowPenalties/${receiptId}`);
  const matchingRef = db.doc(`users/${uid}/meta/matching`);
  const trustRef = db.doc(`users/${uid}/stats/trust`);
  const windowStart = admin.firestore.Timestamp.fromMillis(
    eventTime.toMillis() - NO_SHOW_WINDOW_DAYS * 24 * 60 * 60 * 1000,
  );

  await db.runTransaction(async tx => {
    const [existing, user, deletion, matchingSnap] = await tx.getAll(
      penaltyRef,
      db.doc(`users/${uid}`),
      db.doc(`accountDeletions/${uid}`),
      matchingRef,
    );
    if (existing.exists || !user.exists || deletion.exists) return;

    const recentPenalties = await tx.get(
      db.collection(`users/${uid}/meetupNoShowPenalties`)
        .where('penalizedAt', '>=', windowStart)
        .orderBy('penalizedAt', 'desc')
        .limit(24),
    );
    const strikeCount = recentPenalties.size + 1;
    const tier = Math.min(strikeCount - 1, NO_SHOW_LOCK_LADDER_MS.length - 1);
    const lockDurationMs = NO_SHOW_LOCK_LADDER_MS[tier];
    const trustPenalty = NO_SHOW_TRUST_LADDER[Math.min(strikeCount - 1, NO_SHOW_TRUST_LADDER.length - 1)];
    const matching = matchingSnap.data() || {};
    const lockUntilEpochMs = Math.max(
      Number(matching.lockUntilEpochMs || 0),
      eventTime.toMillis() + lockDurationMs,
    );

    tx.create(penaltyRef, {
      meetupId,
      strikeCount,
      tier,
      lockDurationMs,
      trustPenalty,
      windowDays: NO_SHOW_WINDOW_DAYS,
      outcome: 'no_show',
      penalizedAt: eventTime,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(matchingRef, {
      lockUntilEpochMs,
      activePenaltyCount: admin.firestore.FieldValue.increment(1),
      noShowPenaltyCount: admin.firestore.FieldValue.increment(1),
      lastNoShowAt: eventTime,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAtClientMs: eventTime.toMillis(),
    }, {merge: true});

    tx.set(trustRef, {
      noShowCount: admin.firestore.FieldValue.increment(1),
      noShowTrustPenalty: admin.firestore.FieldValue.increment(trustPenalty),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

export async function recordMeetupOutcome(id: string, data: FirebaseFirestore.DocumentData, eventTime: admin.firestore.Timestamp) {
  const status = String(data.status);
  if (!['completed', 'cancelled', 'declined', 'expired', 'auto_closed'].includes(status)) return;
  const cycle = data.requestedAt instanceof admin.firestore.Timestamp ? data.requestedAt : data.startedAt instanceof admin.firestore.Timestamp ? data.startedAt : eventTime;
  const receiptId = createHash('sha256').update(`${id}:${cycle.seconds}:${cycle.nanoseconds}`).digest('hex');
  const outcome = resolveTerminalOutcome(data, status);
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

  if (outcome !== 'no_show') return;
  const noShows = noShowParticipantIds(data);
  if (noShows.length !== 1) return;
  await applyNoShowPenalty(noShows[0], id, cycle, eventTime);
}

export const onMeetupOutcome = onDocumentWritten({document: 'meetups/{meetupId}', retry: true}, async event => {
  const after = event.data?.after;
  const data = after?.data();
  if (!data || data.status === event.data?.before.data()?.status) return;
  await recordMeetupOutcome(event.params.meetupId, data, after!.updateTime!);
});
