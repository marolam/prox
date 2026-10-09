import * as admin from 'firebase-admin';
import {createHash, randomUUID, randomBytes} from 'node:crypto';
import {onCall, HttpsError} from './lib/active_callable';
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

const IN_PERSON_SESSION_MS = 3 * 60 * 1000;
const IN_PERSON_LOCATION_MS = 5 * 60 * 1000;
const MAX_IN_PERSON_DISTANCE_M = 120;

/** A location refreshed from an old cached fix is not evidence of being there now. */
function inPersonPoint(data: FirebaseFirestore.DocumentData | undefined, now: number) {
  const point = data?.geopoint;
  const captured = data?.locationTs ?? data?.ts;
  const expires = data?.expiresAt;
  const lat = point instanceof admin.firestore.GeoPoint ? point.latitude : data?.lat;
  const lng = point instanceof admin.firestore.GeoPoint ? point.longitude : data?.lon;
  if (typeof lat !== 'number' || typeof lng !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lng) ||
      Math.abs(lat) > 90 || Math.abs(lng) > 180 || !(captured instanceof admin.firestore.Timestamp) ||
      !(expires instanceof admin.firestore.Timestamp) || expires.toMillis() <= now ||
      captured.toMillis() > now + 10000 || now - captured.toMillis() > IN_PERSON_LOCATION_MS ||
      data?.cached === true || (typeof data?.accuracyMeters === 'number' && data.accuracyMeters > 100)) {
    throw new HttpsError('failed-precondition', 'Both people need a fresh location. Enable location, stand together, and reopen Meet in person.');
  }
  return {lat, lng};
}

function distanceMeters(a: {lat: number, lng: number}, b: {lat: number, lng: number}) {
  const rad = Math.PI / 180;
  const h = Math.sin((b.lat - a.lat) * rad / 2) ** 2 +
    Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin((b.lng - a.lng) * rad / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
}

export function writeVerifiedPartyPair(tx: FirebaseFirestore.Transaction, uid: string, other: string,
  source: string, proof: Record<string, unknown>, now = admin.firestore.Timestamp.now()) {
  const id = connectionId(uid, other);
  tx.set(db.doc(`partyConnections/${id}`), {members: [uid, other].sort(), status: 'connected',
    decisions: {[uid]: 'add', [other]: 'add'}, source, proof, connectedAt: now, updatedAt: now});
  tx.set(db.doc(`users/${uid}/party/${other}`), {uid: other, mutual: true, metInPerson: true,
    source, connectionId: id, since: now});
  tx.set(db.doc(`users/${other}/party/${uid}`), {uid, mutual: true, metInPerson: true,
    source, connectionId: id, since: now});
}

export function writeMentorPartyPair(tx: FirebaseFirestore.Transaction, uid: string, mentor: string,
  now = admin.firestore.Timestamp.now()) {
  const id = connectionId(uid, mentor);
  tx.set(db.doc(`partyConnections/${id}`), {members: [uid, mentor].sort(), status: 'connected',
    decisions: {[uid]: 'add', [mentor]: 'add'}, source: 'referralMentor',
    proof: {kind: 'referralMentor', inviteeUid: uid, mentorUid: mentor}, connectedAt: now, updatedAt: now});
  for (const [owner, peer] of [[uid, mentor], [mentor, uid]]) {
    tx.set(db.doc(`users/${owner}/party/${peer}`), {
      uid: peer, mutual: true, metInPerson: false, source: 'referralMentor', connectionId: id, since: now,
    });
  }
}

export async function issuePartyInPersonSession(uid: string) {
  if (!validId(uid)) throw new HttpsError('invalid-argument', 'Invalid account.');
  const code = randomBytes(5).toString('hex').toUpperCase();
  const nonce = randomUUID();
  return db.runTransaction(async tx => {
    const session = db.doc(`partyInPersonSessions/${uid}`);
    const codeRef = db.doc(`partyInPersonCodes/${code}`);
    const [user, deleted, presence, previous, existingCode] = await tx.getAll(db.doc(`users/${uid}`),
      db.doc(`accountDeletions/${uid}`), db.doc(`users/${uid}/presence/current`), session, codeRef);
    const now = admin.firestore.Timestamp.now();
    if (!user.exists || deleted.exists) throw new HttpsError('failed-precondition', 'This account is unavailable.');
    inPersonPoint(presence.data(), now.toMillis());
    const prior = previous.data();
    if (prior?.createdAt instanceof admin.firestore.Timestamp && now.toMillis() - prior.createdAt.toMillis() < 15000) {
      throw new HttpsError('resource-exhausted', 'Wait a few seconds before requesting another code.');
    }
    if (existingCode.exists) throw new HttpsError('aborted', 'Please try creating your code again.');
    const expiresAt = admin.firestore.Timestamp.fromMillis(now.toMillis() + IN_PERSON_SESSION_MS);
    if (typeof prior?.code === 'string') tx.delete(db.doc(`partyInPersonCodes/${prior.code}`));
    const data = {uid, code, nonce, active: true, createdAt: now, expiresAt};
    tx.set(session, data);
    tx.create(codeRef, {uid, nonce, expiresAt});
    return {code, expiresAtMs: expiresAt.toMillis()};
  });
}

export async function closePartyInPersonSession(uid: string) {
  return db.runTransaction(async tx => {
    const session = db.doc(`partyInPersonSessions/${uid}`);
    const existing = await tx.get(session);
    const code = existing.data()?.code;
    if (!existing.exists) return;
    tx.update(session, {active: false});
    if (typeof code === 'string') tx.delete(db.doc(`partyInPersonCodes/${code}`));
  });
}

export async function confirmPartyCode(uid: string, rawCode: unknown) {
  const code = typeof rawCode === 'string' ? rawCode.toUpperCase().replace(/[\s-]/g, '') : '';
  if (!validId(uid) || !/^[A-F0-9]{10}$/.test(code)) {
    throw new HttpsError('invalid-argument', 'Enter the 10-character code on the other person’s screen.');
  }
  // Count unsuccessful lookups too: failed consent transactions cannot roll back this throttle.
  await db.runTransaction(async tx => {
    const limit = db.doc(`partyInPersonRateLimits/${uid}`);
    const existing = (await tx.get(limit)).data();
    const now = admin.firestore.Timestamp.now();
    const within = existing?.startedAt instanceof admin.firestore.Timestamp && now.toMillis() - existing.startedAt.toMillis() < 60000;
    const attempts = within ? Number(existing?.attempts || 0) : 0;
    if (attempts >= 10) throw new HttpsError('resource-exhausted', 'Too many code attempts. Wait a minute and try again.');
    tx.set(limit, {startedAt: within ? existing!.startedAt : now, attempts: attempts + 1});
  });
  return db.runTransaction(async tx => {
    const target = await tx.get(db.doc(`partyInPersonCodes/${code}`));
    const other = target.data()?.uid;
    if (!validId(other) || other === uid) throw new HttpsError('failed-precondition', 'Ask the other person to open Meet in person and show their current code.');
    const id = connectionId(uid, other);
    const [mine, theirs, myPresence, theirPresence, connection, myUser, theirUser, myDeletion, theirDeletion, myBlock, theirBlock] = await tx.getAll(
      db.doc(`partyInPersonSessions/${uid}`), db.doc(`partyInPersonSessions/${other}`),
      db.doc(`users/${uid}/presence/current`), db.doc(`users/${other}/presence/current`), db.doc(`partyConnections/${id}`),
      db.doc(`users/${uid}`), db.doc(`users/${other}`), db.doc(`accountDeletions/${uid}`), db.doc(`accountDeletions/${other}`),
      db.doc(`users/${uid}/blocks/${other}`), db.doc(`users/${other}/blocks/${uid}`));
    const now = admin.firestore.Timestamp.now();
    const a = mine.data();
    const b = theirs.data();
    if (!myUser.exists || !theirUser.exists || myDeletion.exists || theirDeletion.exists || myBlock.exists || theirBlock.exists) {
      throw new HttpsError('permission-denied', 'This Party connection is unavailable.');
    }
    for (const session of [a, b]) {
      if (!session?.active || !(session.expiresAt instanceof admin.firestore.Timestamp) || session.expiresAt.toMillis() <= now.toMillis()) {
        throw new HttpsError('failed-precondition', 'Your codes expired. Both people should reopen Meet in person.');
      }
    }
    if (b!.code !== code || target.data()?.nonce !== b!.nonce) throw new HttpsError('failed-precondition', 'That code is no longer active.');
    const distanceM = distanceMeters(inPersonPoint(myPresence.data(), now.toMillis()), inPersonPoint(theirPresence.data(), now.toMillis()));
    if (distanceM > MAX_IN_PERSON_DISTANCE_M) throw new HttpsError('failed-precondition', 'Stand together before exchanging Party codes.');
    const previous = connection.data() || {};
    if (previous.status === 'connected' && previous.proof && previous.proof.kind !== 'referralMentor') return {status: 'connected', peerUid: other, distanceM};
    const sessionIds = {[uid]: a!.nonce, [other]: b!.nonce};
    const sameSession = previous.status === 'pending' && previous.proof?.kind === 'inPersonCode' &&
      previous.proof.sessionIds?.[uid] === a!.nonce && previous.proof.sessionIds?.[other] === b!.nonce;
    const decisions = sameSession ? {...previous.decisions} : {};
    decisions[uid] = 'add';
    const proof = {kind: 'inPersonCode', sessionIds, distanceM, verifiedAt: now};
    const paired = decisions[other] === 'add';
    if (paired) {
      writeVerifiedPartyPair(tx, uid, other, 'inPersonDirectInvite', proof, now);
      tx.update(mine.ref, {active: false});
      tx.update(theirs.ref, {active: false});
      tx.delete(db.doc(`partyInPersonCodes/${a!.code}`));
      tx.delete(target.ref);
    } else {
      tx.set(connection.ref, {members: [uid, other].sort(), status: 'pending', decisions,
        source: 'inPersonDirectInvite', proof, expiresAt: admin.firestore.Timestamp.fromMillis(
          Math.min(a!.expiresAt.toMillis(), b!.expiresAt.toMillis())), updatedAt: now});
    }
    return {status: paired ? 'connected' : 'pending', peerUid: other, distanceM};
  });
}

function signedInPartyUid(request: {auth?: {uid: string}, data?: Record<string, unknown>}) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  if (request.data?.expectedUid && request.data.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'Your signed-in account changed.');
  return request.auth.uid;
}
export const startPartyInPersonSession = onCall(request => issuePartyInPersonSession(signedInPartyUid(request)));
export const stopPartyInPersonSession = onCall(async request => {
  await closePartyInPersonSession(signedInPartyUid(request));
  return {stopped: true};
});
export const confirmPartyInPersonCode = onCall(request => confirmPartyCode(signedInPartyUid(request), request.data?.code));

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
    const active = previous.status === 'pending' && validId(previous.chatId) &&
      (!previous.proof || previous.proof.kind === 'completedMeetup') &&
      expires instanceof admin.firestore.Timestamp && expires.toMillis() > now.toMillis();
    const connected = a.data()?.mutual === true && b.data()?.mutual === true &&
      previous.status === 'connected' && (previous.proof || previous.chatId);
    if (connected) {
      if (feedback && previous.proof?.kind === 'referralMentor') {
        writeVerifiedPartyPair(tx, uid, other, 'postMeetup', {kind: 'completedMeetup', chatId}, now);
      }
      return {status: 'connected'};
    }
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
      source: 'postMeetup', proof: feedback ? {kind: 'completedMeetup', chatId} : previous.proof || {kind: 'completedMeetup', chatId: previous.chatId},
      chatId: feedback ? chatId : previous.chatId, updatedAt: now,
      ...(mutual ? {connectedAt: now} : {expiresAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + PARTY_INACTIVITY_MS)})});
    if (mutual) {
      tx.set(mine, {uid: other, mutual: true, metInPerson: true, since: now, source: 'postMeetup', connectionId: id});
      tx.set(theirs, {uid, mutual: true, metInPerson: true, since: now, source: 'postMeetup', connectionId: id});
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
  const uid = signedInPartyUid(request);
  const result = await changePartyConnection(uid, request.data || {});
  if (request.data?.action === 'feedback') {
    // Accounting is idempotent; a delayed reward/referral refresh must not hide a saved rating.
    try { await recordCompletedMeetup(request.data.chatId, uid); }
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
  // Keep short-lived exchange codes out of storage after they stop being usable.
  const sessions = await db.collection('partyInPersonSessions').where('expiresAt', '<=', now).limit(300).get();
  await Promise.all(sessions.docs.map(doc => db.runTransaction(async tx => {
    const fresh = await tx.get(doc.ref);
    const session = fresh.data();
    if (!(session?.expiresAt instanceof admin.firestore.Timestamp) || session.expiresAt.toMillis() > now.toMillis()) return;
    tx.delete(doc.ref);
    if (typeof session.code === 'string' && /^[A-F0-9]{10}$/.test(session.code)) tx.delete(db.doc(`partyInPersonCodes/${session.code}`));
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
  if (a.exists || b.exists || deleted.exists || senderDeleted.exists || c?.status !== 'pending' ||
      c.proof?.kind === 'inPersonCode' || !(c.expiresAt instanceof admin.firestore.Timestamp) || c.expiresAt.toMillis() <= Date.now()) return;
  const tokens = await db.collection(`users/${d.toUid}/deviceTokens`).limit(100).get();
  const validTokens = tokens.docs.filter(t => t.data().valid !== false).map(t => t.id);
  if (!validTokens.length) return;
  await admin.messaging().sendEachForMulticast({tokens: validTokens,
    notification: {title: 'Pending Party Add', body: d.kind === 'reminder' ? 'Your meetup partner reminded you about their Party request.' : 'Your meetup partner would like to add you to Party.'},
    data: {type: 'party_request', otherUid: d.fromUid, eventId: event.params.eventId},
    apns: {headers: {'apns-collapse-id': event.params.eventId}, payload: {aps: {sound: 'default'}}},
    android: {notification: {tag: event.params.eventId, channelId: 'chat_alerts'}}});
});
