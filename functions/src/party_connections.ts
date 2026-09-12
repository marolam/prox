import * as admin from 'firebase-admin';
import {createHash, randomUUID} from 'node:crypto';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {onDocumentCreated, onDocumentWritten} from 'firebase-functions/v2/firestore';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {recordCompletedMeetup} from './meetup_accounting';
import {logger} from 'firebase-functions';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
export const PARTY_INACTIVITY_MS = 7 * 86400000;
export const PARTY_REMINDER_MS = 86400000;
export const connectionId = (a: string, b: string) => createHash('sha256').update(JSON.stringify([a, b].sort())).digest('hex');
const validId = (v: unknown): v is string => typeof v === 'string' && v.length > 0 && v.length <= 128 && !v.includes('/');
type Action = 'feedback' | 'add' | 'later' | 'remind' | 'remove' | 'block';

/** Both consent and both membership projections commit together. No client may consent for its peer. */
export async function changePartyConnection(uid: string, input: Record<string, unknown>) {
  const other = input.otherUid;
  const action = input.action as Action;
  if (!validId(uid) || !validId(other) || uid === other || !['feedback', 'add', 'later', 'remind', 'remove', 'block'].includes(action)) {
    throw new HttpsError('invalid-argument', 'Choose a valid meetup partner and action.');
  }
  const feedback = action === 'feedback';
  const chatId = input.chatId;
  const comment = typeof input.comment === 'string' ? input.comment.trim() : '';
  if (feedback && (!validId(chatId) || typeof input.thumb !== 'boolean' || comment.length > 1000 ||
      !['add', 'later'].includes(String(input.partyDecision)) || (input.thumb === false && input.partyDecision !== 'later'))) {
    throw new HttpsError('invalid-argument', 'Choose a rating and Party response. Comments may contain up to 1,000 characters.');
  }
  const id = connectionId(uid, other);
  const ref = db.doc(`partyConnections/${id}`);
  const mine = db.doc(`users/${uid}/party/${other}`);
  const theirs = db.doc(`users/${other}/party/${uid}`);
  const eventRef = ref.collection('notifications').doc(randomUUID());
  return db.runTransaction(async tx => {
    const now = admin.firestore.Timestamp.now();
    const [current, a, b, blockA, blockB, deletedA, deletedB, userA, userB] = await tx.getAll(
      ref, mine, theirs, db.doc(`users/${uid}/blocks/${other}`), db.doc(`users/${other}/blocks/${uid}`),
      db.doc(`accountDeletions/${uid}`), db.doc(`accountDeletions/${other}`), db.doc(`users/${uid}`), db.doc(`users/${other}`));
    if (deletedA.exists || deletedB.exists || !userA.exists || !userB.exists) throw new HttpsError('failed-precondition', 'This account is no longer available.');
    const previous = current.data() || {};
    const blocked = blockA.exists || blockB.exists;
    if (action === 'block' || action === 'remove') {
      if (action === 'block') tx.set(blockA.ref, {uid: other, createdAt: now});
      tx.delete(mine);
      tx.delete(theirs);
      tx.set(ref, {members: [uid, other].sort(), status: action === 'block' ? 'blocked' : 'removed', decisions: {}, updatedAt: now});
      return {status: action === 'block' ? 'blocked' : 'removed'};
    }
    if (blocked) throw new HttpsError('permission-denied', 'This connection is unavailable.');
    let receipt: FirebaseFirestore.DocumentSnapshot | undefined;
    if (feedback) {
      const meetup = await tx.get(db.doc(`meetups/${chatId}`));
      const m = meetup.data();
      if (!m || !((m.aUid === uid && m.bUid === other) || (m.aUid === other && m.bUid === uid))) {
        throw new HttpsError('permission-denied', 'Only this meetup’s participants can rate it.');
      }
      if (m.status !== 'completed' && !(m.status === 'live' && m.aArrived === true && m.bArrived === true)) {
        throw new HttpsError('failed-precondition', 'Both people must confirm arrival before rating the meetup.');
      }
      const completion = m.status === 'completed' && m.completedAt instanceof admin.firestore.Timestamp ? m.completedAt : now;
      const ratingKey = createHash('sha256').update(JSON.stringify([chatId, uid, completion.seconds, completion.nanoseconds])).digest('hex');
      receipt = await tx.get(db.doc(`meetups/${chatId}/partyFeedback/${ratingKey}`));
      if (receipt.exists) {
        const old = receipt.data()!;
        if (old.thumb !== input.thumb || old.comment !== comment || old.partyDecision !== input.partyDecision) {
          throw new HttpsError('already-exists', 'This rating is already saved. Manage your connection from Party.');
        }
        return {status: previous.status || 'rated', alreadySaved: true};
      }
      // Complete the state transition if both arrival acknowledgements arrived before the completion writer.
      if (m.status !== 'completed' || !(m.completedAt instanceof admin.firestore.Timestamp)) {
        tx.update(meetup.ref, {status: 'completed', completedAt: completion, updatedAt: now});
      }
      tx.set(db.doc(`ratings/${chatId}/entries/${uid}`), {thumb: input.thumb, reason: comment || null, ts: now});
      tx.set(db.doc(`users/${uid}/trustFeedback/${chatId}`), {meetupId: chatId, otherUid: other, wouldMeetAgain: input.thumb, updatedAt: now});
      tx.set(receipt.ref, {thumb: input.thumb, comment, partyDecision: input.partyDecision, createdAt: now});
      tx.set(db.doc(`users/${uid}/activityEvents/rating_${ratingKey}`), {
        kind: 'meetup_rated', title: input.thumb ? 'Meetup rated (thumbs up)' : 'Meetup rated (thumbs down)',
        delta: 0, meta: `chatId=${chatId};other=${other}`, createdAt: now});
    }
    const expires = previous.expiresAt as admin.firestore.Timestamp | undefined;
    const active = previous.status === 'pending' && expires instanceof admin.firestore.Timestamp && expires.toMillis() > now.toMillis();
    const connected = a.data()?.mutual === true && b.data()?.mutual === true &&
      (!current.exists || previous.status === 'connected');
    if (connected) return {status: 'connected'};
    if (!feedback && !active) throw new HttpsError('failed-precondition', 'This request has expired or is no longer available.');
    if (feedback && input.thumb === false && !active) return {status: 'rated'};
    const decisions: Record<string, string> = active ? {...previous.decisions} : {};
    const reminders: Record<string, admin.firestore.Timestamp> = active ? {...previous.reminders} : {};
    const choice = feedback ? String(input.partyDecision) : action === 'later' ? 'later' : 'add';
    if (action === 'remind') {
      if (decisions[uid] !== 'add') throw new HttpsError('failed-precondition', 'Choose Add to Party before sending a reminder.');
      const last = reminders[uid];
      if (last instanceof admin.firestore.Timestamp && now.toMillis() - last.toMillis() < PARTY_REMINDER_MS) {
        throw new HttpsError('resource-exhausted', 'You can remind this person once every 24 hours.');
      }
    } else if (!feedback && decisions[uid] === choice) return {status: 'pending'};
    decisions[uid] = choice;
    const mutual = decisions[uid] === 'add' && decisions[other] === 'add';
    const lastNotice = reminders[uid];
    const notify = !mutual && choice === 'add' && (!(lastNotice instanceof admin.firestore.Timestamp) ||
      now.toMillis() - lastNotice.toMillis() >= PARTY_REMINDER_MS);
    if (notify) reminders[uid] = now;
    tx.set(ref, {members: [uid, other].sort(), decisions, reminders, status: mutual ? 'connected' : 'pending',
      chatId: feedback ? chatId : previous.chatId, updatedAt: now,
      ...(mutual ? {connectedAt: now} : {expiresAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + PARTY_INACTIVITY_MS)})});
    if (mutual) {
      tx.set(mine, {uid: other, mutual: true, since: now, source: 'postMeetup', connectionId: id});
      tx.set(theirs, {uid, mutual: true, since: now, source: 'postMeetup', connectionId: id});
    } else {
      // Remove old one-sided projections: pending consent must never grant profile access.
      tx.delete(mine);
      tx.delete(theirs);
    }
    if (notify) tx.create(eventRef, {fromUid: uid, toUid: other, createdAt: now, kind: action === 'remind' ? 'reminder' : 'request'});
    return {status: mutual ? 'connected' : 'pending'};
  });
}

export const respondToPartyConnection = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  const result = await changePartyConnection(request.auth.uid, request.data || {});
  if (request.data?.action === 'feedback') {
    // Accounting is idempotent; a delayed reward/referral refresh must not hide a saved rating.
    try { await recordCompletedMeetup(request.data.chatId, request.auth.uid); }
    catch (error) { logger.warn('party.feedback.accounting', {message: String(error)}); }
  }
  return result;
});

export async function expirePartyConnections(now = admin.firestore.Timestamp.now()) {
  const candidates = await db.collection('partyConnections').where('expiresAt', '<=', now).limit(300).get();
  await Promise.all(candidates.docs.map(doc => db.runTransaction(async tx => {
    const fresh = await tx.get(doc.ref);
    const d = fresh.data();
    if (d?.status === 'pending' && d.expiresAt instanceof admin.firestore.Timestamp && d.expiresAt.toMillis() <= now.toMillis()) {
      tx.set(doc.ref, {status: 'expired', decisions: {}, expiresAt: admin.firestore.FieldValue.delete(), updatedAt: now}, {merge: true});
    }
  })));
}
export const sweepPartyConnections = onSchedule('every 60 minutes', async () => { await expirePartyConnections(); });

export const onPartyConnectionBlock = onDocumentWritten({document: 'users/{uid}/blocks/{otherUid}', retry: true}, async event => {
  const {uid, otherUid} = event.params;
  const block = db.doc(`users/${uid}/blocks/${otherUid}`);
  await db.runTransaction(async tx => {
    const [fresh, deletedA, deletedB] = await tx.getAll(block, db.doc(`accountDeletions/${uid}`), db.doc(`accountDeletions/${otherUid}`));
    if (!fresh.exists) return;
    tx.delete(db.doc(`users/${uid}/party/${otherUid}`));
    tx.delete(db.doc(`users/${otherUid}/party/${uid}`));
    const connection = db.doc(`partyConnections/${connectionId(uid, otherUid)}`);
    if (deletedA.exists || deletedB.exists) tx.delete(connection);
    else tx.set(connection, {members: [uid, otherUid].sort(), status: 'blocked', decisions: {}, updatedAt: admin.firestore.Timestamp.now()});
  });
});

export const onPartyConnectionNotification = onDocumentCreated({document: 'partyConnections/{connection}/notifications/{eventId}', retry: true}, async event => {
  const d = event.data?.data();
  if (!d) return;
  const [connection, a, b, deleted, senderDeleted] = await db.getAll(db.doc(`partyConnections/${event.params.connection}`),
    db.doc(`users/${d.fromUid}/blocks/${d.toUid}`), db.doc(`users/${d.toUid}/blocks/${d.fromUid}`), db.doc(`accountDeletions/${d.toUid}`), db.doc(`accountDeletions/${d.fromUid}`));
  const c = connection.data();
  if (a.exists || b.exists || deleted.exists || senderDeleted.exists || c?.status !== 'pending' || c.expiresAt.toMillis() <= Date.now()) return;
  const tokens = await db.collection(`users/${d.toUid}/deviceTokens`).limit(100).get();
  const validTokens = tokens.docs.filter(t => t.data().valid !== false).map(t => t.id);
  if (!validTokens.length) return;
  await admin.messaging().sendEachForMulticast({tokens: validTokens,
    notification: {title: 'Pending Party Add', body: d.kind === 'reminder' ? 'Your meetup partner reminded you about their Party request.' : 'Your meetup partner would like to add you to Party.'},
    data: {type: 'party_request', otherUid: d.fromUid, eventId: event.params.eventId},
    apns: {headers: {'apns-collapse-id': event.params.eventId}, payload: {aps: {sound: 'default'}}},
    android: {notification: {tag: event.params.eventId, channelId: 'chat_alerts'}}});
});
