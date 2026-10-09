import * as admin from 'firebase-admin';
import {onCall, onRecoveryCall, HttpsError} from './lib/active_callable';
import {onDocumentCreated, onDocumentWritten} from 'firebase-functions/v2/firestore';
import * as logger from 'firebase-functions/logger';
import {connectionId, writeMentorPartyPair, writeVerifiedPartyPair} from './party_connections';
import {referralProfileComplete} from './lib/profile_completion';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
export const MENTOR_NUDGE_COOLDOWN_MS = 12 * 3600000;
const validUid = (value: unknown): value is string =>
  typeof value === 'string' && value.length > 0 && value.length <= 128 && !value.includes('/');

export async function syncReferralMentor(uid: string): Promise<void> {
  if (!validUid(uid)) throw new HttpsError('invalid-argument', 'Invalid account.');
  await db.runTransaction(async tx => {
    const contact = db.doc(`users/${uid}/referralMentor/current`);
    const [user, attribution, deletion, prior] = await tx.getAll(db.doc(`users/${uid}`),
      db.doc(`referralAttributions/${uid}`), db.doc(`accountDeletions/${uid}`), contact);
    const owner = user.data()?.referrer;
    if (!user.exists || deletion.exists || !validUid(owner) || owner === uid) {
      if (prior.exists) tx.delete(contact);
      return;
    }
    const [mentor, mentorDeletion, blockA, blockB, settings, stats, referral, connection, progress, growth] = await tx.getAll(
      db.doc(`users/${owner}`), db.doc(`accountDeletions/${owner}`),
      db.doc(`users/${uid}/blocks/${owner}`), db.doc(`users/${owner}/blocks/${uid}`),
      db.doc(`users/${owner}/settings/referral`), db.doc(`users/${uid}/stats/current`),
      db.doc(`users/${owner}/referrals/${uid}`), db.doc(`partyConnections/${connectionId(uid, owner)}`),
      db.doc(`growthProgress/${uid}`), db.doc(`growthReferrals/${uid}`));
    const summary = db.doc(`users/${owner}/mentorReferrals/${uid}`);
    const summarySnap = await tx.get(summary);
    if (!mentor.exists || mentorDeletion.exists || blockA.exists || blockB.exists ||
        (attribution.exists && attribution.data()?.referrerUid !== owner)) {
      if (summarySnap.exists) tx.delete(summary);
      if (prior.exists) tx.delete(contact);
      return;
    }
    const complete = referralProfileComplete(user.data() || {});
    const autoAdd = typeof prior.data()?.partyRequested === 'boolean' ? prior.data()?.partyRequested === true
      : (settings.data()?.autoAddMentorToParty ?? settings.data()?.allowInPersonQrPartyJoin) === true;
    const c = connection.data();
    const neverRemoved = !['removed', 'blocked'].includes(c?.status);
    const now = admin.firestore.Timestamp.now();
    const inPersonVerified = attribution.data()?.inPersonVerified === true || referral.data()?.inPersonVerified === true;
    const qrVerified = attribution.data()?.inPersonVerified === true && typeof attribution.data()?.token === 'string';
    const consented = !qrVerified || referral.data()?.partyInPersonQrRequested === true;
    const partyAdded = complete && autoAdd && neverRemoved && inPersonVerified && consented;
    const summaryData = {
      uid, mentorUid: owner, role: 'mentor', displayName: String(user.data()?.displayName || user.data()?.name || 'New user').slice(0, 120),
      profileComplete: complete, meetupsCompleted: Math.max(0, Number(stats.data()?.completedMeetups) || 0),
      hasConversation: progress.data()?.actions?.chat === true,
      inPersonVerified,
      growthRewardStatus: String(growth.data()?.status || ''),
      partyAdded, rewardCredited: referral.data()?.rewardCredited === true,
    };
    const contactData = {
      mentorUid: owner, role: 'mentor', displayName: String(mentor.data()?.displayName || mentor.data()?.name || 'Your referrer').slice(0, 120),
      partyRequested: autoAdd, partyAdded, inPersonVerified,
    };
    const differs = (old: FirebaseFirestore.DocumentData | undefined, next: Record<string, unknown>) =>
      Object.entries(next).some(([key, value]) => old?.[key] !== value);
    if (differs(summarySnap.data(), summaryData)) tx.set(summary, {...summaryData, updatedAt: now}, {merge: true});
    if (differs(prior.data(), contactData)) tx.set(contact, {...contactData, updatedAt: now}, {merge: true});
    if (partyAdded && c?.status !== 'connected') {
      if (qrVerified) writeVerifiedPartyPair(tx, uid, owner, 'referralInPersonQr',
        {kind: 'referralQr', token: attribution.data()!.token}, now);
      else writeMentorPartyPair(tx, uid, owner, now);
    }
  });
}

export const onReferralMentorAttribution = onDocumentWritten({document: 'referralAttributions/{uid}', retry: true}, async event => {
  await syncReferralMentor(event.params.uid);
});
export const onReferralMentorProfile = onDocumentWritten({document: 'users/{uid}', retry: true}, async event => {
  if (event.data?.after.exists) await syncReferralMentor(event.params.uid);
});
export const onReferralMentorMeetup = onDocumentCreated({document: 'users/{uid}/completedMeetups/{receipt}', retry: true}, async event => {
  await syncReferralMentor(event.params.uid);
});
export const onReferralMentorReward = onDocumentWritten({document: 'users/{owner}/referrals/{uid}', retry: true}, async event => {
  if (event.data?.after.exists) await syncReferralMentor(event.params.uid);
});
export const onReferralMentorProgress = onDocumentWritten({document: 'growthProgress/{uid}', retry: true}, async event => {
  if (event.data?.after.exists) await syncReferralMentor(event.params.uid);
});
export const onReferralMentorGrowthReward = onDocumentWritten({document: 'growthReferrals/{uid}', retry: true}, async event => {
  if (event.data?.after.exists) await syncReferralMentor(event.params.uid);
});
export const onReferralMentorBlock = onDocumentWritten({document: 'users/{uid}/blocks/{otherUid}', retry: true}, async event => {
  await Promise.all([syncReferralMentor(event.params.uid), syncReferralMentor(event.params.otherUid)]);
});
export const onReferralMentorParty = onDocumentWritten({document: 'partyConnections/{connection}', retry: true}, async event => {
  const after = event.data?.after.data();
  const before = event.data?.before.data();
  const members = after?.members || before?.members || [];
  await Promise.all(members.filter(validUid).map((uid: string) => syncReferralMentor(uid)));
});

export async function sendMentorNudge(owner: string, input: Record<string, unknown>) {
  const uid = input.inviteeUid;
  const requestId = input.requestId;
  const kind = input.kind;
  if (!validUid(owner) || !validUid(uid) || uid === owner ||
      typeof requestId !== 'string' || !/^[A-Za-z0-9_-]{16,100}$/.test(requestId) ||
      !['use_app', 'support'].includes(String(kind))) {
    throw new HttpsError('invalid-argument', 'Choose a referral and reminder type.');
  }
  return db.runTransaction(async tx => {
    const ref = db.doc(`users/${owner}/mentorReferrals/${uid}`);
    const eventRef = db.doc(`referralMentorNudges/${owner}_${requestId}`);
    const [user, mentor, attribution, a, b, deleted, mentorDeleted, summary, prior] = await tx.getAll(
      db.doc(`users/${uid}`), db.doc(`users/${owner}`), db.doc(`referralAttributions/${uid}`),
      db.doc(`users/${uid}/blocks/${owner}`), db.doc(`users/${owner}/blocks/${uid}`),
      db.doc(`accountDeletions/${uid}`), db.doc(`accountDeletions/${owner}`), ref, eventRef);
    if (!user.exists || !mentor.exists || user.data()?.disabled === true || mentor.data()?.disabled === true ||
        user.data()?.banned === true || mentor.data()?.banned === true || user.data()?.referrer !== owner ||
        (attribution.exists && attribution.data()?.referrerUid !== owner) ||
        deleted.exists || mentorDeleted.exists || a.exists || b.exists) {
      throw new HttpsError('permission-denied', 'Only the active direct referrer can send a mentor reminder.');
    }
    if (prior.exists) {
      if (prior.data()?.toUid !== uid || prior.data()?.kind !== kind) throw new HttpsError('already-exists', 'This reminder request was already used.');
      return {queued: true, replayed: true};
    }
    const last = summary.data()?.lastReminderAt;
    const now = admin.firestore.Timestamp.now();
    if (last instanceof admin.firestore.Timestamp && now.toMillis() - last.toMillis() < MENTOR_NUDGE_COOLDOWN_MS) {
      throw new HttpsError('resource-exhausted', 'You can nudge this referral once every 12 hours.');
    }
    const body = kind === 'support'
      ? 'Your referrer/mentor suggests contacting Prox support if you need help getting started.'
      : 'Your referrer/mentor is here to help. Complete your profile and arrange a real meetup when you are ready.';
    tx.create(eventRef, {fromUid: owner, toUid: uid, kind, body, status: 'queued', createdAt: now});
    tx.set(ref, {uid, mentorUid: owner, lastReminderAt: now}, {merge: true});
    tx.set(db.doc(`users/${uid}/referralMentor/current`), {
      mentorUid: owner, role: 'mentor', lastNudge: body, lastNudgeKind: kind, lastNudgeAt: now,
    }, {merge: true});
    return {queued: true, replayed: false};
  });
}

export const sendReferralMentorNudge = onCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to send a mentor reminder.');
  if (request.data?.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'Your signed-in account changed.');
  return sendMentorNudge(request.auth.uid, request.data || {});
});

export const refreshReferralMentor = onRecoveryCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to load your mentor.');
  if (request.data?.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'Your signed-in account changed.');
  await syncReferralMentor(request.auth.uid);
  return {synced: true};
});

export async function deliverMentorNudge(eventId: string): Promise<void> {
  const eventRef = db.doc(`referralMentorNudges/${eventId}`);
  const event = (await eventRef.get()).data();
  if (!event || event.status !== 'queued') return;
  const {fromUid, toUid} = event;
  const [user, mentor, a, b, deletion, mentorDeletion] = await db.getAll(db.doc(`users/${toUid}`), db.doc(`users/${fromUid}`),
    db.doc(`users/${toUid}/blocks/${fromUid}`), db.doc(`users/${fromUid}/blocks/${toUid}`),
    db.doc(`accountDeletions/${toUid}`), db.doc(`accountDeletions/${fromUid}`));
  if (!user.exists || !mentor.exists || user.data()?.disabled === true || mentor.data()?.disabled === true ||
      user.data()?.banned === true || mentor.data()?.banned === true ||
      user.data()?.referrer !== fromUid || a.exists || b.exists || deletion.exists || mentorDeletion.exists) {
    await eventRef.update({status: 'cancelled'});
    return;
  }
  const tokens = await db.collection(`users/${toUid}/deviceTokens`).limit(100).get();
  const active = tokens.docs.filter(token => token.data().valid !== false);
  if (!active.length) {
    await eventRef.update({status: 'no_devices'});
    logger.info('mentor.nudge.no_devices', {eventId});
    return;
  }
  const response = await admin.messaging().sendEachForMulticast({
    tokens: active.map(token => token.id),
    notification: {title: 'A nudge from your mentor', body: event.body},
    data: {type: 'mentor_nudge', kind: event.kind, otherUid: fromUid, eventId},
    android: {notification: {channelId: 'chat_alerts', tag: eventId}},
    apns: {headers: {'apns-collapse-id': eventId.slice(0, 64)}, payload: {aps: {sound: 'default'}}},
  });
  const invalid = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);
  await Promise.all(response.responses.map((result, index) =>
    !result.success && invalid.has(result.error?.code || '') ? active[index].ref.delete() : Promise.resolve()));
  if (response.responses.some(result => !result.success && !invalid.has(result.error?.code || ''))) {
    logger.error('mentor.nudge.delivery_failed', {eventId, failures: response.failureCount});
    throw new Error('Mentor notification delivery failed; retry required.');
  }
  await eventRef.update({status: response.successCount ? 'delivered' : 'no_devices', deliveredAt: admin.firestore.FieldValue.serverTimestamp()});
}

export const onReferralMentorNudge = onDocumentCreated({document: 'referralMentorNudges/{eventId}', retry: true}, async event => {
  await deliverMentorNudge(event.params.eventId);
});
