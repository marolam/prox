import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions/v1';
import {createHash, createHmac, randomBytes} from 'node:crypto';
import {HttpsError, onCall, onRecoveryCall} from './lib/active_callable';
import {onDocumentCreated, onDocumentWritten} from 'firebase-functions/v2/firestore';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {claimReward} from './verified_rewards';
import {referralProfileComplete as profileComplete} from './lib/profile_completion';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const DAY = 86400000;
type Data = Record<string, any>;
const hash = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const stamp = (ms = Date.now()) => admin.firestore.Timestamp.fromMillis(ms);
const millis = (v: unknown): number => v instanceof admin.firestore.Timestamp ? v.toMillis() : 0;
const day = (ms = Date.now()) => new Date(ms).toISOString().slice(0, 10);
const month = (ms = Date.now()) => day(ms).slice(0, 7);
const str = (v: unknown, max = 500) => typeof v === 'string' ? v.trim().slice(0, max) : '';
const id = (v: unknown, name = 'requestId'): string => {
  const value = str(v, 121);
  if (!/^[A-Za-z0-9_-]{8,120}$/.test(value)) throw new HttpsError('invalid-argument', `A stable ${name} is required.`);
  return value;
};
const authed = (request: Data): string => {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  if (request.data?.expectedUid && request.data.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'The signed-in account changed. Reopen this screen.');
  return request.auth.uid;
};
const operator = (request: Data): string => {
  const uid = authed(request);
  if (request.auth.token?.admin !== true) throw new HttpsError('permission-denied', 'An administrator account is required.');
  return uid;
};
const dataRef = (collection: string, uid: string) => db.doc(`${collection}/${uid}`);
// Use the same ownership priority as Firestore rules for older canonical tickets.
const supportOwner = (data: Data): string => {
  const key = ['ownerUid', 'userId', 'uid', 'createdBy', 'reporterUid'].find(k => typeof data[k] === 'string');
  const uid = key ? str(data[key], 128) : '';
  return uid && !uid.includes('/') ? uid : '';
};

export const DEFAULT_GROWTH_CONFIG = {
  enabled: true, stage: 'testers', testerCapacity: 20, missionHours: 48,
  welcomePoints: 5, referrerPoints: 10, maxInvitesPerDay: 10,
  maxRewardsPerMonth: 50, maxRewardPointsPerMonth: 100, holdHours: 24,
  maxSupportPerDay: 10, inviteExpiryDays: 7,
};

export function normalizeGrowthConfig(raw: Data = {}) {
  const result = {...DEFAULT_GROWTH_CONFIG};
  result.enabled = raw.enabled !== false;
  result.stage = ['testers', 'referrals', 'support'].includes(raw.stage) ? raw.stage : 'testers';
  for (const [key, min, max] of [
    ['testerCapacity', 10, 20], ['missionHours', 24, 168], ['welcomePoints', 0, 50],
    ['referrerPoints', 0, 100], ['maxInvitesPerDay', 1, 30], ['maxRewardsPerMonth', 1, 100],
    ['maxRewardPointsPerMonth', 1, 1000], ['holdHours', 1, 168], ['maxSupportPerDay', 1, 30],
    ['inviteExpiryDays', 1, 30],
  ] as const) {
    const value = Number(raw[key]);
    if (Number.isInteger(value)) (result as Data)[key] = Math.max(min, Math.min(max, value));
  }
  return result;
}

async function config(tx?: FirebaseFirestore.Transaction) {
  const ref = db.doc('growthOps/config');
  return normalizeGrowthConfig((await (tx ? tx.get(ref) : ref.get())).data());
}

function active(cfg: ReturnType<typeof normalizeGrowthConfig>, referrals = false) {
  if (!cfg.enabled) throw new HttpsError('failed-precondition', 'The tester program is paused.');
  if (referrals && cfg.stage === 'testers') throw new HttpsError('failed-precondition', 'Referrals open after the first tester stage.');
}

/** Auth creation time, never a client-editable profile date, defines signup cohorts. */
export async function ensureGrowthIdentity(uid: string, creationMs?: number): Promise<void> {
  const ref = dataRef('growthProgress', uid);
  if ((await ref.get()).exists) return;
  const registered = creationMs ?? Date.parse((await admin.auth().getUser(uid)).metadata.creationTime);
  await db.runTransaction(async tx => {
    const [prior, deletion] = await tx.getAll(ref, dataRef('accountDeletions', uid));
    if (deletion.exists) throw new HttpsError('failed-precondition', 'This account is being deleted.');
    if (prior.exists) return;
    const now = stamp();
    tx.create(ref, {uid, createdAt: stamp(Number.isFinite(registered) ? registered : Date.now()), trackedAt: now,
      onboarded: false, qualifiedActivation: false, actions: {profile: false, chat: false, meetup: false}, updatedAt: now});
  });
}

export const onGrowthAuthCreate = functions.auth.user().onCreate(async user => {
  if (!(await config()).enabled) return;
  await ensureGrowthIdentity(user.uid, Date.parse(user.metadata.creationTime));
});

/** A chat requires actual text in both directions, not an owner-editable counter. */
async function meaningfulChat(uid: string, afterMs = 0): Promise<{id: string, atMs: number} | null> {
  const chats = await db.collection('chats').where('participants', 'array-contains', uid).limit(100).get();
  let earliest: {id: string, atMs: number} | null = null;
  for (const chat of chats.docs) {
    const d = chat.data();
    const participants = Array.isArray(d.participants) ? d.participants : [];
    if (participants.length !== 2 || d.isGroup === true) continue;
    const peer = participants.find((p: unknown) => typeof p === 'string' && p !== uid);
    if (!peer || peer.includes('/')) continue;
    const [sent, received, blockA, blockB, deletion] = await Promise.all([
      (afterMs ? chat.ref.collection('messages').where('from', '==', uid).orderBy('ts', 'desc') : chat.ref.collection('messages').where('from', '==', uid)).limit(25).get(),
      (afterMs ? chat.ref.collection('messages').where('from', '==', peer).orderBy('ts', 'desc') : chat.ref.collection('messages').where('from', '==', peer)).limit(25).get(),
      db.doc(`users/${uid}/blocks/${peer}`).get(), db.doc(`users/${peer}/blocks/${uid}`).get(),
      dataRef('accountDeletions', peer).get(),
    ]);
    const firstText = (rows: FirebaseFirestore.QuerySnapshot, to: string) => rows.docs.filter(row =>
      row.data().to === to && row.data().kind !== 'system' && str(row.data().text, 10000).length >= 2 &&
      (!afterMs || millis(row.createTime) >= afterMs)).reduce((first, row) => Math.min(first, millis(row.createTime)), Infinity);
    const sentAt = firstText(sent, peer), receivedAt = firstText(received, uid);
    if (!blockA.exists && !blockB.exists && !deletion.exists && Number.isFinite(sentAt) && Number.isFinite(receivedAt)) {
      const atMs = Math.max(sentAt, receivedAt);
      if (!earliest || atMs < earliest.atMs) earliest = {id: chat.id, atMs};
    }
  }
  return earliest;
}

// The optional profile snapshot time is supplied only by the trusted trigger.
export async function syncGrowthProgressForUid(uid: string, profileEvidenceAt?: FirebaseFirestore.Timestamp) {
  const [cfg, identity, enrollment] = await Promise.all([config(), dataRef('growthProgress', uid).get(), dataRef('growthMembers', uid).get()]);
  if (!cfg.enabled || !identity.exists) return;
  const [user, chatId, meetups] = await Promise.all([
    db.doc(`users/${uid}`).get(), meaningfulChat(uid), db.collection(`users/${uid}/completedMeetups`).limit(100).get(),
  ]);
  // Older financial receipts keep their historical completedAt. Growth uses the
  // trusted transition timestamp, falling back to server receipt creation time.
  const receiptTime = (row: FirebaseFirestore.QueryDocumentSnapshot) => millis(row.data().verifiedCompletedAt) || millis(row.createTime);
  const firstReceipt = (after = 0) => meetups.docs.map(receiptTime).filter(value => value >= after && value > 0).reduce((first, value) => Math.min(first, value), Infinity);
  const earliestMeetup = firstReceipt();
  const meetupAt = Number.isFinite(earliestMeetup) ? earliestMeetup : 0;
  const actions = {profile: !!profileEvidenceAt || profileComplete(user.data() || {}), chat: !!chatId, meetup: meetupAt > 0};
  const joinedMs = millis(enrollment.data()?.joinedAt);
  const missionChat = joinedMs ? await meaningfulChat(uid, joinedMs) : null;
  const earliestMissionMeetup = joinedMs ? firstReceipt(joinedMs) : Infinity;
  const missionMeetupAt = Number.isFinite(earliestMissionMeetup) ? earliestMissionMeetup : 0;
  await db.runTransaction(async tx => {
    const [fresh, member, deletion] = await tx.getAll(dataRef('growthProgress', uid), dataRef('growthMembers', uid), dataRef('accountDeletions', uid));
    if (deletion.exists || !fresh.exists) return;
    const prior = fresh.data() || {};
    // Completed evidence remains completed if users later edit their profile or remove chat history.
    const merged = Object.fromEntries(Object.keys(actions).map(key => [key, (actions as Data)[key] || prior.actions?.[key] === true]));
    const earliest = (old: unknown, observedMs: number) => {
      const oldMs = millis(old);
      return oldMs && observedMs ? Math.min(oldMs, observedMs) : oldMs || observedMs;
    };
    const actionMs = {
      profile: earliest(prior.actionAt?.profile, actions.profile ? millis(profileEvidenceAt || user.updateTime) : 0),
      chat: earliest(prior.actionAt?.chat, chatId?.atMs || 0),
      meetup: earliest(prior.actionAt?.meetup, meetupAt),
    };
    const timestamps = (values: Record<string, number>) => Object.fromEntries(Object.entries(values).filter(([,value]) => value > 0).map(([key,value]) => [key, stamp(value)]));
    const qualified = merged.profile && (merged.chat || merged.meetup);
    const alternatives = [actionMs.chat, actionMs.meetup].filter(value => value > 0);
    const activationMs = qualified && actionMs.profile && alternatives.length
      ? Math.max(millis(prior.createdAt), actionMs.profile, Math.min(...alternatives)) : 0;
    const now = stamp();
    tx.update(fresh.ref, {actions: merged, actionAt: timestamps(actionMs), onboarded: merged.profile, qualifiedActivation: qualified,
      ...(activationMs ? {activatedAt: stamp(earliest(prior.activatedAt, activationMs)), activationSource: actionMs.chat && (!actionMs.meetup || actionMs.chat <= actionMs.meetup) ? 'reciprocal_chat' : 'completed_meetup_receipt'} : {}), updatedAt: now});
    if (member.exists) {
      const mission = {profile: merged.profile, chat: !!missionChat || member.data()?.actions?.chat === true,
        meetup: missionMeetupAt > 0 || member.data()?.actions?.meetup === true};
      const done = mission.profile && mission.chat && mission.meetup;
      const missionMs = {
        profile: earliest(member.data()?.actionAt?.profile, actionMs.profile ? Math.max(millis(member.data()?.joinedAt), actionMs.profile) : 0),
        chat: earliest(member.data()?.actionAt?.chat, missionChat?.atMs || 0),
        meetup: earliest(member.data()?.actionAt?.meetup, missionMeetupAt),
      };
      const completedMs = done && Object.values(missionMs).every(value => value > 0) ? Math.max(...Object.values(missionMs)) : 0;
      const firstCompleted = earliest(member.data()?.completedAt, completedMs);
      tx.update(member.ref, {actions: mission, actionAt: timestamps(missionMs), completed: done,
        ...(firstCompleted ? {completedAt: stamp(firstCompleted), completedWithin48h: firstCompleted <= millis(member.data()?.deadline)} : {}), updatedAt: now});
    }
  });
  await evaluateGrowthReferral(uid);
}

export const onGrowthProfile = onDocumentWritten('users/{uid}', async event => {
  if (event.data?.after.exists && profileComplete(event.data.after.data() || {})) {
    if (!(await config()).enabled || (await dataRef('accountDeletions', event.params.uid).get()).exists) return;
    await ensureGrowthIdentity(event.params.uid);
    await syncGrowthProgressForUid(event.params.uid, event.data.after.updateTime);
  }
});
export const onGrowthChatMessage = onDocumentCreated('chats/{chatId}/messages/{messageId}', async event => {
  const data = event.data?.data() || {};
  if (data.kind === 'system' || str(data.text).length < 2) return;
  const chat = (await db.doc(`chats/${event.params.chatId}`).get()).data() || {};
  if (Array.isArray(chat.participants) && chat.participants.length === 2) {
    await Promise.all(chat.participants.filter((uid: unknown) => typeof uid === 'string' && !uid.includes('/')).map((uid: string) => syncGrowthProgressForUid(uid)));
  }
});
export const onGrowthMeetupReceipt = onDocumentCreated('users/{uid}/completedMeetups/{receiptId}', async event => {
  await syncGrowthProgressForUid(event.params.uid);
});

export async function joinTesterForUid(uid: string) {
  return db.runTransaction(async tx => {
    const cfg = await config(tx);
    active(cfg);
    const [member, application, deletion, progress, user] = await tx.getAll(dataRef('growthMembers', uid), dataRef('growthTesterApplications', uid),
      dataRef('accountDeletions', uid), dataRef('growthProgress', uid), db.doc(`users/${uid}`));
    if (deletion.exists) throw new HttpsError('failed-precondition', 'This account is being deleted.');
    if (member.exists) return {joined: true, status: 'approved', replayed: true};
    if (!progress.exists) throw new HttpsError('failed-precondition', 'Open the tester hub first.');
    if (application.exists && application.data()?.status !== 'rejected') return {joined: false, status: application.data()?.status, replayed: true};
    if (application.exists) {
      tx.set(application.ref, {uid, displayName: str(user.data()?.displayName || user.data()?.name, 120), status: 'pending', requestedAt: stamp()});
      return {joined: false, status: 'pending', replayed: false};
    }
    tx.create(application.ref, {uid, displayName: str(user.data()?.displayName || user.data()?.name, 120), status: 'pending', requestedAt: stamp()});
    return {joined: false, status: 'pending', replayed: false};
  });
}

export async function reviewTesterForOperator(operatorUid: string, input: Data) {
  const uid = str(input.uid, 128);
  if (!uid || uid.includes('/') || !['approve', 'reject'].includes(input.decision)) throw new HttpsError('invalid-argument', 'Choose a tester application and decision.');
  const result = await db.runTransaction(async tx => {
    const cfg = await config(tx); active(cfg);
    const [application, member, seats, progress, deletion, operatorDeletion] = await tx.getAll(
      dataRef('growthTesterApplications', uid), dataRef('growthMembers', uid), db.doc('growthOps/cohort'),
      dataRef('growthProgress', uid), dataRef('accountDeletions', uid), dataRef('accountDeletions', operatorUid));
    if (deletion.exists || operatorDeletion.exists || !application.exists || !progress.exists) throw new HttpsError('failed-precondition', 'This application is unavailable.');
    const desired = input.decision === 'approve' ? 'approved' : 'rejected';
    if (application.data()?.status === desired) return {reviewed: true, status: desired, replayed: true};
    if (application.data()?.status !== 'pending' || member.exists) throw new HttpsError('failed-precondition', 'Only pending applications can be reviewed.');
    const members: string[] = Array.isArray(seats.data()?.members) ? seats.data()!.members : [];
    const now = Date.now();
    if (input.decision === 'approve') {
      if (members.length >= cfg.testerCapacity) throw new HttpsError('resource-exhausted', 'The tester cohort is full.');
      tx.create(member.ref, {uid, status: 'approved', joinedAt: stamp(now), deadline: stamp(now + cfg.missionHours * 3600000),
        actions: {profile: progress.data()?.actions?.profile === true, chat: false, meetup: false}, completed: false, updatedAt: stamp(now)});
      tx.set(seats.ref, {members: [...members, uid], updatedAt: stamp(now)});
    }
    tx.update(application.ref, {status: desired, reviewedAt: stamp(now), reviewedBy: operatorUid, note: str(input.note, 1000)});
    tx.create(db.collection('growthOpsAudit').doc(), {operatorUid, targetUid: uid, action: `tester_${input.decision}`, createdAt: stamp(now)});
    return {reviewed: true, status: desired, replayed: false};
  });
  if (input.decision === 'approve') await syncGrowthProgressForUid(uid);
  return result;
}

export async function createGrowthInviteForUid(uid: string, requestId: string, deviceId = '', ip = '') {
  const request = id(requestId);
  const {deviceHash, ipHash} = await signalHashes(str(deviceId, 200), str(ip, 100));
  const receipt = db.doc(`growthRequests/${hash([uid, 'invite', request])}`);
  const code = `PROX-P-${randomBytes(6).toString('hex').toUpperCase()}`;
  return db.runTransaction(async tx => {
    const cfg = await config(tx);
    active(cfg, true);
    const [prior, budget, deletion, user, progress] = await tx.getAll(receipt, db.doc(`growthRateLimits/${hash([uid, 'invites', day()])}`),
      dataRef('accountDeletions', uid), db.doc(`users/${uid}`), dataRef('growthProgress', uid));
    if (deletion.exists || !user.exists) throw new HttpsError('failed-precondition', 'An active account is required.');
    if (user.data()?.referralTrustRequired === true && user.data()?.referralInPersonVerified !== true) {
      throw new HttpsError('failed-precondition', 'Meet your referrer in person and verify their QR before recruiting.');
    }
    if (prior.exists) return {...prior.data()?.result, replayed: true};
    if (Number(budget.data()?.count || 0) >= cfg.maxInvitesPerDay) throw new HttpsError('resource-exhausted', 'Your daily invite limit has been reached.');
    const now = Date.now();
    const expiresAtMs = now + cfg.inviteExpiryDays * DAY;
    const link = `https://www.prox-us.com/referral.html?code=${encodeURIComponent(code)}`;
    const result = {code, link, qrLink: link, expiresAtMs, requestId: request};
    const definition = {referrerUid: uid, rootReferrerUid: str(user.data()?.root_referrer, 128) || uid, active: true, remaining: 1, source: 'growth',
      createdAt: stamp(now), expiresAt: stamp(expiresAtMs), requestId: request, welcomePoints: cfg.welcomePoints, referrerPoints: cfg.referrerPoints};
    tx.create(db.doc(`referralCodes/${code}`), definition);
    tx.create(db.doc(`growthInvites/${code}`), {...definition, code, status: 'issued'});
    tx.set(budget.ref, {uid, kind: 'invites', day: day(now), count: Number(budget.data()?.count || 0) + 1, expiresAt: stamp(now + 40 * DAY)});
    tx.create(receipt, {uid, kind: 'invite', result, createdAt: stamp(now)});
    if (progress.exists && (deviceHash || ipHash)) tx.update(progress.ref, {deviceHash, ipHash});
    return {...result, replayed: false};
  });
}

async function signalHashes(deviceId: string, ip: string) {
  const secret = db.doc('growthPrivate/abuseSalt');
  const salt = await db.runTransaction(async tx => {
    const snapshot = await tx.get(secret);
    if (snapshot.exists) return String(snapshot.data()?.value);
    const value = randomBytes(32).toString('hex');
    tx.create(secret, {value, createdAt: stamp()});
    return value;
  });
  const keyed = (value: string) => createHmac('sha256', salt).update(value).digest('hex');
  return {deviceHash: deviceId ? keyed(`device:${deviceId}`) : '', ipHash: ip ? keyed(`ip:${day()}:${ip}`) : ''};
}

/** Growth reward receipts are distinct from preserved five-meetup milestone rewards. */
function credit(tx: FirebaseFirestore.Transaction, uid: string, points: number, receiptId: string, category: string, inviteeUid: string) {
  const now = stamp();
  tx.create(db.doc(`users/${uid}/rewardClaims/${receiptId}`), {category, points, inviteeUid, createdAt: now});
  tx.set(db.doc(`users/${uid}/meta/points`), {currentPoints: admin.firestore.FieldValue.increment(points),
    totalPoints: admin.firestore.FieldValue.increment(points), updatedAt: now}, {merge: true});
  tx.create(db.doc(`users/${uid}/meta/points/events/${receiptId}`), {eventId: receiptId, amount: points, category, reason: 'Tester referral program', timestamp: now});
}

export async function acceptGrowthReferralForUid(uid: string, input: Data, ip = '') {
  const code = str(input.code, 80).toUpperCase();
  if (!/^PROX-P-[A-F0-9]{12}$/.test(code)) throw new HttpsError('invalid-argument', 'Enter a tester referral code.');
  const device = str(input.deviceId, 200);
  const {deviceHash, ipHash} = await signalHashes(device, str(ip, 100));
  const result = await db.runTransaction(async tx => {
    const cfg = await config(tx);
    active(cfg, true);
    const referral = dataRef('growthReferrals', uid);
    const [invite, prior, attribution, user, deletion, progress, welcome] = await tx.getAll(db.doc(`growthInvites/${code}`), referral,
      dataRef('referralAttributions', uid), db.doc(`users/${uid}`), dataRef('accountDeletions', uid),
      dataRef('growthProgress', uid), db.doc(`users/${uid}/rewardClaims/growth_welcome`));
    if (deletion.exists || !user.exists || !progress.exists) throw new HttpsError('failed-precondition', 'An active account is required.');
    if (user.data()?.referralTrustRequired === true && user.data()?.referralInPersonVerified !== true) {
      throw new HttpsError('failed-precondition', 'Verify your direct referrer’s QR in person before accepting a reward invitation.');
    }
    const definition = invite.data() || {};
    const owner = str(definition.referrerUid, 128);
    if (!owner || owner.includes('/') || !invite.exists) throw new HttpsError('not-found', 'This invite is unavailable.');
    if (owner === uid) throw new HttpsError('invalid-argument', 'You cannot refer yourself.');
    if (prior.exists) {
      if (prior.data()?.code !== code) throw new HttpsError('already-exists', 'A referral is already assigned.');
      return {linked: true, referrerUid: owner, replayed: true, welcomeStatus: prior.data()?.welcomeStatus, status: prior.data()?.status};
    }
    const assigned = attribution.data()?.referrerUid || user.data()?.referrer;
    if (assigned && assigned !== owner) throw new HttpsError('already-exists', 'A referral is already assigned.');
    if (definition.status !== 'issued' || millis(definition.expiresAt) <= Date.now()) throw new HttpsError('failed-precondition', 'This invite has expired or was used.');
    if (millis(progress.data()?.createdAt) < Date.now() - 7 * DAY) throw new HttpsError('failed-precondition', 'Welcome rewards are for new accounts in their first seven days.');
    const signals = [deviceHash ? db.doc(`growthIdentitySignals/device_${deviceHash}`) : null,
      ipHash ? db.doc(`growthIdentitySignals/ip_${ipHash}`) : null].filter((ref): ref is FirebaseFirestore.DocumentReference => !!ref);
    const [ownerUser, ownerDeletion, ownerProgress, legacy, ...signalRows] = await tx.getAll(db.doc(`users/${owner}`),
      dataRef('accountDeletions', owner), dataRef('growthProgress', owner), db.doc(`users/${owner}/referrals/${uid}`), ...signals);
    if (!ownerUser.exists || ownerDeletion.exists) throw new HttpsError('failed-precondition', 'This invite is unavailable.');
    const reasons: string[] = [];
    if (!deviceHash) reasons.push('missing_device_signal');
    if (deviceHash && (ownerProgress.data()?.deviceHash === deviceHash || signalRows.some(row => row.id.startsWith('device_') && (row.data()?.uids || []).some((v: string) => v !== uid)))) reasons.push('duplicate_device');
    if (ipHash && (ownerProgress.data()?.ipHash === ipHash || signalRows.some(row => row.id.startsWith('ip_') && (row.data()?.uids || []).filter((v: string) => v !== uid).length >= 3))) reasons.push('shared_ip_pattern');
    const now = Date.now();
    const held = reasons.length > 0;
    const welcomePoints = Number(definition.welcomePoints || 0);
    const row = {uid, inviteeUid: uid, referrerUid: owner, code, deviceHash, ipHash, reasons,
      status: held ? 'held' : 'pending', welcomeStatus: held ? 'held' : 'credited',
      welcomePoints, referrerPoints: Number(definition.referrerPoints || 0), createdAt: stamp(now),
      holdUntil: held ? stamp(now + cfg.holdHours * 3600000) : null, updatedAt: stamp(now)};
    tx.create(referral, row);
    tx.update(invite.ref, {status: 'accepted', inviteeUid: uid, acceptedAt: stamp(now)});
    tx.update(db.doc(`referralCodes/${code}`), {remaining: 0, active: false, updatedAt: stamp(now)});
    const rootReferrerUid = str(ownerUser.data()?.root_referrer, 128) || owner;
    if (!attribution.exists) tx.create(attribution.ref, {referrerUid: owner, rootReferrerUid, code, createdAt: stamp(now), source: 'growth'});
    tx.update(user.ref, {referrer: owner, root_referrer: rootReferrerUid, updatedAt: stamp(now)});
    if (!legacy.exists) tx.create(legacy.ref, {uid, code, status: 'joined', inPersonVerified: false, rewardEligible: false,
      rewardGranted: false, rewardCredited: false, meetupsCompleted: 0, joinedAt: stamp(now), source: 'growth'});
    tx.update(progress.ref, {deviceHash, ipHash, updatedAt: stamp(now)});
    for (const signal of signalRows) tx.set(signal.ref, {uids: [...new Set([...(signal.data()?.uids || []), uid])].slice(-100),
      updatedAt: stamp(now), expiresAt: stamp(now + 40 * DAY)});
    if (!held && !welcome.exists) credit(tx, uid, welcomePoints, 'growth_welcome', 'growth_welcome', uid);
    return {linked: true, referrerUid: owner, replayed: false, welcomeStatus: row.welcomeStatus, status: row.status};
  });
  await syncGrowthProgressForUid(uid);
  return result;
}

export async function evaluateGrowthReferral(uid: string) {
  return db.runTransaction(async tx => {
    const cfg = await config(tx);
    if (!cfg.enabled || cfg.stage === 'testers') return;
    const [referral, progress, deletion, enforcement] = await tx.getAll(dataRef('growthReferrals', uid), dataRef('growthProgress', uid), dataRef('accountDeletions', uid),
      db.doc(`accountEnforcements/${uid}`));
    const row = referral.data() || {};
    if (!referral.exists || deletion.exists || (enforcement.exists && enforcement.data()?.status !== 'active') ||
        progress.data()?.qualifiedActivation !== true) return;
    const meetupReceipts = await tx.get(db.collection(`users/${uid}/completedMeetups`)
      .where('verifiedCompletedAt', '>=', row.createdAt).limit(1));
    if (meetupReceipts.empty) return;
    if (['held', 'rewarded', 'rejected'].includes(row.status)) {
      if (!row.qualifiedAt) tx.update(referral.ref, {qualifiedAt: progress.data()?.activatedAt || stamp()});
      return;
    }
    const owner = row.referrerUid;
    const receiptId = `growth_referral_${hash(uid).slice(0, 32)}`;
    const limit = db.doc(`growthRewardLimits/${hash([owner, month()])}`);
    const [receipt, budget, ownerDeletion, ownerUser, ownerEnforcement] = await tx.getAll(db.doc(`users/${owner}/rewardClaims/${receiptId}`), limit,
      dataRef('accountDeletions', owner), db.doc(`users/${owner}`), db.doc(`accountEnforcements/${owner}`));
    if (ownerDeletion.exists || !ownerUser.exists || ownerUser.data()?.disabled === true || ownerUser.data()?.banned === true ||
        (ownerEnforcement.exists && ownerEnforcement.data()?.status !== 'active')) return;
    const now = stamp();
    if (receipt.exists) {
      tx.update(referral.ref, {status: 'rewarded', updatedAt: now});
      return;
    }
    const count = Number(budget.data()?.count || 0), points = Number(budget.data()?.points || 0);
    if (count >= cfg.maxRewardsPerMonth || points + row.referrerPoints > cfg.maxRewardPointsPerMonth) {
      tx.update(referral.ref, {status: 'held', reasons: ['period_reward_cap'], qualifiedAt: progress.data()?.activatedAt || now,
        holdUntil: stamp(Date.now() + cfg.holdHours * 3600000), updatedAt: now});
      return;
    }
    credit(tx, owner, row.referrerPoints, receiptId, 'growth_referral', uid);
    tx.set(limit, {uid: owner, month: month(), count: count + 1, points: points + row.referrerPoints, updatedAt: now});
    tx.update(referral.ref, {status: 'rewarded', qualifiedAt: progress.data()?.activatedAt || now, rewardedAt: now, updatedAt: now});
  });
}

export async function reviewGrowthRewardForUid(operatorUid: string, input: Data) {
  const uid = str(input.inviteeUid, 128);
  if (!uid || uid.includes('/') || !['release', 'reject'].includes(input.decision) || str(input.note).length < 3) throw new HttpsError('invalid-argument', 'Choose a reward decision and explain it.');
  await db.runTransaction(async tx => {
    const cfg = await config(tx);
    active(cfg, true);
    const [row, deletion, welcome, operatorDeletion] = await tx.getAll(dataRef('growthReferrals', uid), dataRef('accountDeletions', uid), db.doc(`users/${uid}/rewardClaims/growth_welcome`), dataRef('accountDeletions', operatorUid));
    if (!row.exists || deletion.exists || operatorDeletion.exists) throw new HttpsError('not-found', 'The referral is unavailable.');
    const d = row.data() || {};
    if (d.status !== 'held') throw new HttpsError('failed-precondition', 'Only held referrals can be reviewed.');
    if (input.decision === 'release' && millis(d.holdUntil) > Date.now()) throw new HttpsError('failed-precondition', 'The suspicious-account delay has not elapsed.');
    if (input.decision === 'release' && d.welcomeStatus === 'held' && !welcome.exists) credit(tx, uid, d.welcomePoints, 'growth_welcome', 'growth_welcome', uid);
    tx.update(row.ref, {status: input.decision === 'release' ? 'pending' : 'rejected',
      welcomeStatus: d.welcomeStatus === 'credited' ? 'credited' : input.decision === 'release' ? 'credited' : 'rejected',
      reviewedBy: operatorUid, reviewNote: str(input.note, 1000), reviewedAt: stamp(), updatedAt: stamp()});
    tx.create(db.collection('growthOpsAudit').doc(), {operatorUid, targetUid: uid, action: `reward_${input.decision}`, note: str(input.note, 1000), createdAt: stamp()});
  });
  await evaluateGrowthReferral(uid);
  return {reviewed: true};
}

export async function growthStatusForUid(uid: string) {
  const [cfg, progress, member, referral, invites, application, grants] = await Promise.all([config(), dataRef('growthProgress', uid).get(),
    dataRef('growthMembers', uid).get(), dataRef('growthReferrals', uid).get(), db.collection('growthInvites').where('referrerUid', '==', uid).limit(100).get(),
    dataRef('growthTesterApplications', uid).get(), db.collection(`users/${uid}/rewardClaims`).where('category', 'in', ['growth_welcome', 'growth_referral']).limit(200).get()]);
  const p = progress.data() || {}, t = member.data(), r = referral.data();
  return {config: cfg,
    progress: {onboarded: p.onboarded === true, qualifiedActivation: p.qualifiedActivation === true,
      actions: p.actions || {profile: false, chat: false, meetup: false}, activatedAtMs: millis(p.activatedAt) || null},
    tester: t ? {status: 'approved', actions: t.actions, completed: t.completed === true, joinedAtMs: millis(t.joinedAt), deadlineMs: millis(t.deadline), completedAtMs: millis(t.completedAt) || null}
      : application.exists ? {status: application.data()?.status, requestedAtMs: millis(application.data()?.requestedAt), actions: p.actions || {profile: false, chat: false, meetup: false}, completed: false, joinedAtMs: null, deadlineMs: null} : null,
    referral: r ? {referrerUid: r.referrerUid, status: r.status, welcomeStatus: r.welcomeStatus,
      welcomePoints: r.welcomePoints, referrerPoints: r.referrerPoints, reasons: r.reasons || [], holdUntilMs: millis(r.holdUntil) || null} : null,
    invites: invites.docs.map(row => ({code: row.id, status: row.data().status, claimed: row.data().status !== 'issued', requestId: row.data().requestId,
      createdAtMs: millis(row.data().createdAt), expiresAtMs: millis(row.data().expiresAt)})),
    rewards: {pointsCredited: grants.docs.reduce((sum, row) => sum + Number(row.data().points || 0), 0), grants: grants.size,
      welcomePoints: grants.docs.filter(row => row.data().category === 'growth_welcome').reduce((sum, row) => sum + Number(row.data().points || 0), 0),
      referralPoints: grants.docs.filter(row => row.data().category === 'growth_referral').reduce((sum, row) => sum + Number(row.data().points || 0), 0)},
  };
}

export async function recordGrowthSessionForUid(uid: string, input: Data) {
  const sessionId = id(input.sessionId, 'sessionId');
  if (!['start', 'error', 'end'].includes(input.event)) throw new HttpsError('invalid-argument', 'Unsupported session event.');
  if (input.event === 'error' && input.diagnosticsConsent !== true) return {recorded: false, consentRequired: true};
  const source = str(input.source, 81);
  if (input.event === 'error' && !/^[A-Za-z0-9_.:-]{1,80}$/.test(source)) throw new HttpsError('invalid-argument', 'Use an operation name without error text.');
  const requestId = input.event === 'error' ? id(input.requestId) : input.event;
  const ref = db.doc(`growthSessions/${hash([uid, sessionId])}`);
  return db.runTransaction(async tx => {
    const cfg = await config(tx);
    if (!cfg.enabled) return {recorded: false, paused: true};
    const [session, receipt, deletion, budget] = await tx.getAll(ref, db.doc(`growthSessionEvents/${hash([uid, sessionId, requestId])}`),
      dataRef('accountDeletions', uid), db.doc(`growthRateLimits/${hash([uid, 'session_events', day()])}`));
    if (deletion.exists) throw new HttpsError('failed-precondition', 'This account is being deleted.');
    if (receipt.exists) return {recorded: true, replayed: true};
    if (Number(budget.data()?.count || 0) >= 500) throw new HttpsError('resource-exhausted', 'Session reporting limit reached.');
    if (!session.exists && input.event !== 'start') throw new HttpsError('failed-precondition', 'Start the session before reporting its outcome.');
    const old = session.data() || {}, now = Date.now();
    if (session.exists && input.event === 'start') return {recorded: true, replayed: true};
    const errors = {...old.errors};
    if (input.event === 'error') errors[source] = Number(errors[source] || 0) + 1;
    const metadata = sanitizeMetadata(input.metadata);
    tx.set(ref, {uid, sessionId, startedAt: old.startedAt || stamp(now), day: old.day || day(now),
      diagnosticsConsent: old.diagnosticsConsent === true || input.diagnosticsConsent === true,
      ended: old.ended === true || input.event === 'end' || (input.event === 'error' && input.fatal === true),
      fatal: old.fatal === true || (input.event === 'error' && input.fatal === true), errors,
      metadata: old.metadata || metadata, updatedAt: stamp(now), expiresAt: stamp(now + 90 * DAY)});
    tx.create(receipt.ref, {uid, sessionId, event: input.event, createdAt: stamp(now), expiresAt: stamp(now + 90 * DAY)});
    tx.set(budget.ref, {uid, kind: 'session_events', day: day(now), count: Number(budget.data()?.count || 0) + 1, expiresAt: stamp(now + 40 * DAY)});
    tx.set(db.doc(`growthActivity/${hash([uid, day(now)])}`), {uid, day: day(now), activeAt: stamp(now), expiresAt: stamp(now + 120 * DAY)});
    return {recorded: true, replayed: false};
  });
}

export function sanitizeMetadata(raw: Data = {}) {
  raw = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  const keys = {version: raw.version || raw.appVersion, build: raw.build || raw.buildNumber,
    platform: raw.platform, os: raw.os || raw.osVersion, device: raw.device};
  return Object.fromEntries(Object.entries(keys).map(([k, v]) => [k, str(String(v ?? ''), k === 'device' ? 160 : 80)]));
}

const CATEGORIES = ['bug', 'ux', 'billing', 'feature', 'question'];
const STATUSES = ['open', 'acknowledged', 'in_progress', 'resolved', 'closed'];

export async function submitGrowthSupportForUid(uid: string, input: Data) {
  if (input.expectedUid && input.expectedUid !== uid) throw new HttpsError('failed-precondition', 'The signed-in account changed. Reopen your saved draft.');
  const ticketId = id(input.requestId || input.ticketId);
  const subject = str(input.subject, 201), message = str(input.message, 10001);
  if (!subject || subject.length > 200 || !message || message.length > 10000 || !CATEGORIES.includes(input.category)) throw new HttpsError('invalid-argument', 'Choose a category, subject and a useful description.');
  const paths: string[] = input.attachmentPaths || (input.attachmentPath ? [input.attachmentPath] : []);
  if (!Array.isArray(paths) || paths.length > 3 || paths.some(path => typeof path !== 'string' || !path.startsWith(`supportAttachments/${uid}/${ticketId}/`) || !/^supportAttachments\/[^/]+\/[A-Za-z0-9_-]+\/[A-Za-z0-9_.-]+$/.test(path))) throw new HttpsError('invalid-argument', 'Attachments must belong to this ticket.');
  // Never store a public download token or accept a URL supplied by the client.
  for (const path of paths) {
    let metadata: Data;
    try { [metadata] = await admin.storage().bucket().file(path).getMetadata(); }
    catch { throw new HttpsError('failed-precondition', 'Upload the screenshot before submitting.'); }
    if (Number(metadata.size) > 5 * 1024 * 1024 || !['image/png', 'image/jpeg', 'image/webp'].includes(metadata.contentType)) throw new HttpsError('invalid-argument', 'Attach an image smaller than 5 MB.');
  }
  const normalized = {subject, message, category: input.category, source: str(input.source, 120),
    firstHuhMoment: str(input.firstHuhMoment, 1000), metadata: sanitizeMetadata(input.metadata), attachmentPaths: paths};
  const result = await db.runTransaction(async tx => {
    const cfg = await config(tx);
    const [ticket, deletion, budget] = await tx.getAll(db.doc(`supportTickets/${ticketId}`), dataRef('accountDeletions', uid), db.doc(`growthRateLimits/${hash([uid, 'support', day()])}`));
    if (deletion.exists) throw new HttpsError('failed-precondition', 'This account is being deleted.');
    if (ticket.exists) {
      if (ticket.data()?.uid !== uid || ticket.data()?.submissionHash !== hash({subject, message, category: input.category})) throw new HttpsError('already-exists', 'This request ID has already been used.');
      return {ticketId, replayed: true, submitted: true};
    }
    if (Number(budget.data()?.count || 0) >= cfg.maxSupportPerDay) throw new HttpsError('resource-exhausted', 'Daily support submission limit reached.');
    const now = Date.now();
    tx.create(ticket.ref, {uid, ownerUid: uid, ...normalized, submissionHash: hash({subject, message, category: input.category}), status: 'open', severity: 'P2',
      labels: [input.category], acknowledgement: 'Received. Your report is in the support queue.', acknowledgedAutomaticallyAt: stamp(now),
      responseDueAt: stamp(now + DAY), createdAt: stamp(now), updatedAt: stamp(now), workflow: 'growth'});
    tx.set(budget.ref, {uid, kind: 'support', day: day(now), count: Number(budget.data()?.count || 0) + 1, expiresAt: stamp(now + 40 * DAY)});
    return {ticketId, replayed: false, submitted: true};
  });
  // Preserve the existing detailed-feedback reward, sharing its one-per-day
  // limit and receipt. Ticket submission stays successful if the reward is unavailable.
  const stored = (await db.doc(`supportTickets/${ticketId}`).get()).data() || {};
  if (stored.source === 'settings_support_feedback' && str(stored.message, 10000).length >= 20) {
    try {return {...result, reward: await claimReward(uid, 'feedback', ticketId)};}
    catch (error) {
      console.warn('Growth feedback reward unavailable', {uid, ticketId, error});
      return {...result, reward: {awarded: false, points: 0, unavailable: true}};
    }
  }
  return result;
}

export async function replyToSupportForUid(uid: string, input: Data) {
  const ticketId = id(input.ticketId, 'ticketId'), requestId = id(input.requestId);
  const message = str(input.message, 10001);
  if (!message || message.length > 10000) throw new HttpsError('invalid-argument', 'A reply is required.');
  return db.runTransaction(async tx => {
    const [ticket, reply, deletion, budget] = await tx.getAll(db.doc(`supportTickets/${ticketId}`), db.doc(`supportTickets/${ticketId}/replies/${requestId}`), dataRef('accountDeletions', uid),
      db.doc(`growthRateLimits/${hash([uid, 'support_replies', day()])}`));
    if (deletion.exists || supportOwner(ticket.data() || {}) !== uid) throw new HttpsError('permission-denied', 'Only the reporter can add details.');
    if (reply.exists) {
      if (reply.data()?.uid !== uid || reply.data()?.message !== message) throw new HttpsError('already-exists', 'This reply ID is already used.');
      return {replied: true, replayed: true};
    }
    if (Number(budget.data()?.count || 0) >= 100) throw new HttpsError('resource-exhausted', 'Daily support reply limit reached.');
    tx.create(reply.ref, {uid, author: 'user', message, createdAt: stamp()});
    tx.set(budget.ref, {uid, kind: 'support_replies', count: Number(budget.data()?.count || 0) + 1, expiresAt: stamp(Date.now() + 40 * DAY)});
    tx.update(ticket.ref, {updatedAt: stamp(), status: ticket.data()?.status === 'closed' ? 'open' : ticket.data()?.status || 'open'});
    return {replied: true, replayed: false};
  });
}

export async function updateSupportForOperator(operatorUid: string, input: Data) {
  const ticketId = id(input.ticketId, 'ticketId'), requestId = id(input.requestId);
  if (input.status && !STATUSES.includes(input.status) || input.severity && !['P0', 'P1', 'P2'].includes(input.severity) || input.category && !CATEGORIES.includes(input.category)) throw new HttpsError('invalid-argument', 'Choose a valid status, severity and category.');
  const reply = str(input.reply, 10000);
  const fixedVersion = str(input.fixedVersion, 30), fixedBuild = str(String(input.fixedBuild ?? ''), 30);
  if (!!fixedVersion !== !!fixedBuild || fixedVersion && (!/^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$/.test(fixedVersion) || !/^\d+$/.test(fixedBuild))) throw new HttpsError('invalid-argument', 'A valid app version and numeric build are required together.');
  const receipt = db.doc(`growthRequests/${hash([operatorUid, 'triage', requestId])}`);
  return db.runTransaction(async tx => {
    const [ticket, prior] = await tx.getAll(db.doc(`supportTickets/${ticketId}`), receipt);
    if (!ticket.exists) throw new HttpsError('not-found', 'The ticket is unavailable.');
    const fingerprint = hash(input);
    if (prior.exists) {
      if (prior.data()?.fingerprint !== fingerprint) throw new HttpsError('already-exists', 'This operation ID is already used.');
      return {updated: true, replayed: true};
    }
    const d = ticket.data() || {};
    const reporterUid = supportOwner(d);
    if (!reporterUid) throw new HttpsError('failed-precondition', 'This ticket is missing a valid reporter.');
    const [deletion, operatorDeletion] = await tx.getAll(dataRef('accountDeletions', reporterUid), dataRef('accountDeletions', operatorUid));
    if (deletion.exists || operatorDeletion.exists) throw new HttpsError('failed-precondition', 'The account is being deleted.');
    const category = input.category || (CATEGORIES.includes(d.category) ? d.category : 'question');
    if (input.status === 'resolved' && category === 'bug' && !fixedVersion && !d.fixedVersion) throw new HttpsError('failed-precondition', 'Record the app version and build that fixed this bug.');
    const message = reply || (fixedVersion ? `Fixed in Prox ${fixedVersion}, build ${fixedBuild}. Thank you for reporting it.` : '');
    const now = stamp();
    const patch: Data = {updatedAt: now, labels: [category], category,
      status: input.status || (STATUSES.includes(d.status) ? d.status : 'open'),
      severity: input.severity || (['P0', 'P1', 'P2'].includes(d.severity) ? d.severity : 'P2'),
      ...(fixedVersion ? {fixedVersion, fixedBuild} : {}),
      ...(message && !d.firstResponseAt ? {firstResponseAt: now} : {}),
      ...(message ? {lastReply: message, lastReplyAt: now} : {}),
      ...(input.status === 'acknowledged' ? {acknowledgedAt: now} : {}),
      ...(input.status === 'resolved' || input.status === 'closed' ? {resolvedAt: now} : {}),
    };
    tx.update(ticket.ref, patch);
    if (message) tx.create(ticket.ref.collection('replies').doc(`support_${hash([operatorUid, requestId]).slice(0, 40)}`),
      {author: 'support', uid: operatorUid, message, createdAt: now, ...(fixedVersion ? {fixedVersion, fixedBuild} : {})});
    tx.create(receipt, {uid: operatorUid, targetUid: reporterUid, fingerprint, kind: 'triage', createdAt: now});
    tx.create(db.collection('growthOpsAudit').doc(), {operatorUid, targetUid: reporterUid, ticketId, action: 'support_triage', status: patch.status || d.status,
      severity: patch.severity || d.severity, category, fixedVersion, fixedBuild, createdAt: now});
    return {updated: true, replayed: false};
  });
}

const ratio = (n: number, d: number) => d ? n / d : null;
const median = (values: number[]) => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b), middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};

/** Pilot-sized bounded queries; the UI exposes truncation rather than inventing precision. */
export async function computeGrowthMetrics(days = 14, nowMs = Date.now()) {
  const length = Math.min(30, Math.max(1, Math.trunc(days) || 14));
  const startMs = Date.parse(`${day(nowMs - (length - 1) * DAY)}T00:00:00Z`);
  const before = stamp(startMs);
  const [users, activity, invites, referrals, sessions, tickets] = await Promise.all([
    db.collection('growthProgress').where('createdAt', '>=', before).limit(2000).get(),
    db.collection('growthActivity').where('activeAt', '>=', before).limit(10000).get(),
    db.collection('growthInvites').where('createdAt', '>=', before).limit(2000).get(),
    db.collection('growthReferrals').where('createdAt', '>=', before).limit(2000).get(),
    db.collection('growthSessions').where('startedAt', '>=', before).limit(10000).get(),
    db.collection('supportTickets').where('createdAt', '>=', before).limit(2000).get(),
  ]);
  const activityKeys = new Set(activity.docs.map(row => `${row.data().uid}:${row.data().day}`));
  const truncated = users.size === 2000 || activity.size === 10000 || invites.size === 2000 || referrals.size === 2000 || sessions.size === 10000 || tickets.size === 2000;
  const rows: Data[] = [];
  for (let offset = length - 1; offset >= 0; offset--) {
    const date = day(nowMs - offset * DAY), dateMs = Date.parse(`${date}T00:00:00Z`);
    const cohort = users.docs.map(d => d.data()).filter(u => day(millis(u.createdAt)) === date);
    const mature = cohort.filter(u => millis(u.createdAt) + DAY <= nowMs);
    const activated = mature.filter(u => u.qualifiedActivation === true && millis(u.activatedAt) >= millis(u.createdAt) && millis(u.activatedAt) <= millis(u.createdAt) + DAY).length;
    const retained = (n: number) => {
      // UTC calendar-day retention: a cohort matures only after its target day ends.
      const eligible = dateMs + (n + 1) * DAY <= nowMs ? cohort : [];
      const next = day(dateMs + n * DAY);
      return {eligible: eligible.length, returned: eligible.filter(u => activityKeys.has(`${u.uid}:${next}`)).length};
    };
    const d1 = retained(1), d7 = retained(7);
    const issued = invites.docs.filter(d => day(millis(d.data().createdAt)) === date);
    const codes = new Set(issued.map(d => d.id));
    const activatedReferrals = referrals.docs.filter(d => codes.has(d.data().code) && !!d.data().qualifiedAt).length;
    const dailySessions = sessions.docs.map(d => d.data()).filter(s => s.day === date);
    // A known fatal report is a completed failure even if its end event never
    // arrives. Healthy active sessions remain unclassified until they end.
    const observed = dailySessions.filter(s => s.diagnosticsConsent === true && (s.ended === true || s.fatal === true));
    const errors: Data = {};
    for (const s of dailySessions.filter(s => s.diagnosticsConsent === true)) for (const [source, count] of Object.entries(s.errors || {})) errors[source] = (errors[source] || 0) + Number(count);
    const dailyTickets = tickets.docs.map(d => d.data()).filter(t => day(millis(t.createdAt)) === date);
    const responseTimes = dailyTickets.filter(t => millis(t.firstResponseAt) >= millis(t.createdAt) && !!t.firstResponseAt).map(t => (millis(t.firstResponseAt) - millis(t.createdAt)) / 60000);
    rows.push({day: date, newUsers: cohort.length, activationEligible: mature.length, activatedWithin24h: activated,
      activationRate: ratio(activated, mature.length), invitesSent: issued.length, referredActivated: activatedReferrals,
      referralConversion: ratio(activatedReferrals, issued.length), day1Retention: ratio(d1.returned, d1.eligible), day7Retention: ratio(d7.returned, d7.eligible),
      day1Eligible: d1.eligible, day7Eligible: d7.eligible, day1Returned: d1.returned, day7Returned: d7.returned,
      medianFirstResponseMinutes: median(responseTimes), supportReports: dailyTickets.length, supportResponded: responseTimes.length,
      supportAwaitingResponse: dailyTickets.length - responseTimes.length,
      crashFreeSessions: ratio(observed.filter(s => !s.fatal).length, observed.length),
      topErrors: Object.entries(errors).sort((a, b) => Number(b[1]) - Number(a[1])).slice(0, 3).map(([source, count]) => ({source, count})),
      coverage: {sessions: dailySessions.length, optedInSessions: dailySessions.filter(s => s.diagnosticsConsent).length,
        completedDiagnosticSessions: dailySessions.filter(s => s.diagnosticsConsent === true && s.ended === true).length,
        observedDiagnosticSessions: observed.length, reportedFatalSessions: observed.filter(s => s.fatal).length,
        crashDetection: 'reported_fatal_errors', cohort: 'tracked_authenticated_accounts', referralDenominator: 'generated_single_use_invites', truncated}});
  }
  return rows;
}

export async function growthOpsSnapshot(days = 14) {
  const [cfg, metrics, tickets, held, testers, applications] = await Promise.all([config(), computeGrowthMetrics(days),
    db.collection('supportTickets').orderBy('createdAt', 'desc').limit(100).get(),
    db.collection('growthReferrals').where('status', '==', 'held').limit(100).get(),
    db.collection('growthMembers').limit(20).get(), db.collection('growthTesterApplications').where('status', '==', 'pending').limit(100).get()]);
  return {config: cfg, metrics,
    tickets: tickets.docs.map(row => {const t = row.data(); const uid = supportOwner(t); return {id: row.id, subject: str(t.subject || t.title, 200) || 'Support report', uid,
      category: CATEGORIES.includes(t.category) ? t.category : 'question', severity: ['P0', 'P1', 'P2'].includes(t.severity) ? t.severity : 'P2',
      status: STATUSES.includes(t.status) ? t.status : 'open', message: str(t.message || t.body, 10000),
      source: t.source || '', firstHuhMoment: t.firstHuhMoment || '', acknowledgement: t.acknowledgement || '',
      metadata: sanitizeMetadata(t.metadata), attachmentPaths: Array.isArray(t.attachmentPaths) ? t.attachmentPaths.filter((path: unknown) => typeof path === 'string' && path.startsWith(`supportAttachments/${uid}/`) && /^supportAttachments\/[^/]+\/[A-Za-z0-9_-]{8,120}\/[A-Za-z0-9_.-]+$/.test(path)).slice(0, 3) : [], createdAtMs: millis(t.createdAt),
      firstResponseAtMs: millis(t.firstResponseAt) || null, lastReply: t.lastReply || '', fixedVersion: t.fixedVersion || '',
      fixedBuild: t.fixedBuild || '', responseDueAtMs: millis(t.responseDueAt) || null};}),
    heldRewards: held.docs.map(row => {const r = row.data(); return {inviteeUid: row.id, referrerUid: r.referrerUid, code: r.code,
      reasons: r.reasons || [], status: r.status, welcomeStatus: r.welcomeStatus, welcomePoints: r.welcomePoints,
      referrerPoints: r.referrerPoints, createdAtMs: millis(r.createdAt), holdUntilMs: millis(r.holdUntil)};}),
    testers: testers.docs.map(row => {const t = row.data(); return {uid: row.id, actions: t.actions || {}, completed: t.completed === true,
      joinedAtMs: millis(t.joinedAt), deadlineMs: millis(t.deadline), completedWithin48h: t.completedWithin48h === true};}),
    applications: applications.docs.map(row => ({uid: row.id, displayName: row.data().displayName || '', status: row.data().status, requestedAtMs: millis(row.data().requestedAt)})),
  };
}

export const getGrowthStatus = onRecoveryCall({region: 'us-central1'}, async request => {
  const uid = authed(request);
  if ((await config()).enabled) {await ensureGrowthIdentity(uid); await syncGrowthProgressForUid(uid);}
  return growthStatusForUid(uid);
});
export const joinTesterCohort = onCall({region: 'us-central1'}, async request => {
  const uid = authed(request); await ensureGrowthIdentity(uid); const result = await joinTesterForUid(uid);
  await syncGrowthProgressForUid(uid); return result;
});
export const createGrowthInvite = onCall({region: 'us-central1'}, async request => {
  const uid = authed(request); await ensureGrowthIdentity(uid);
  return createGrowthInviteForUid(uid, request.data?.requestId, request.data?.deviceId, request.rawRequest?.ip || '');
});
export const acceptGrowthReferral = onCall({region: 'us-central1'}, async request => {
  const uid = authed(request); await ensureGrowthIdentity(uid);
  return acceptGrowthReferralForUid(uid, request.data || {}, request.rawRequest?.ip || '');
});
export const syncGrowthProgress = onCall({region: 'us-central1'}, async request => {
  const uid = authed(request); await ensureGrowthIdentity(uid); await syncGrowthProgressForUid(uid); return growthStatusForUid(uid);
});
export const recordGrowthSession = onCall({region: 'us-central1'}, async request => {
  const uid = authed(request); if ((await config()).enabled) await ensureGrowthIdentity(uid);
  return recordGrowthSessionForUid(uid, request.data || {});
});
export const submitGrowthSupport = onRecoveryCall({region: 'us-central1'}, async request => submitGrowthSupportForUid(authed(request), request.data || {}));
export const replyToSupportTicket = onRecoveryCall({region: 'us-central1'}, async request => replyToSupportForUid(authed(request), request.data || {}));
export const updateSupportTicket = onCall({region: 'us-central1'}, async request => updateSupportForOperator(operator(request), request.data || {}));
export const getGrowthOps = onCall({region: 'us-central1', timeoutSeconds: 120}, async request => {
  const uid = operator(request);
  if ((await dataRef('accountDeletions', uid).get()).exists) throw new HttpsError('permission-denied', 'This account is being deleted.');
  return growthOpsSnapshot(request.data?.days);
});
export const reviewGrowthReward = onCall({region: 'us-central1'}, async request => reviewGrowthRewardForUid(operator(request), request.data || {}));
export const reviewTesterApplication = onCall({region: 'us-central1'}, async request => reviewTesterForOperator(operator(request), request.data || {}));
export const updateGrowthConfig = onCall({region: 'us-central1'}, async request => {
  const uid = operator(request);
  const patch = request.data?.config || {};
  const cfg = await db.runTransaction(async tx => {
    const before = await config(tx);
    const next = normalizeGrowthConfig({...before, ...patch});
    const deletion = await tx.get(dataRef('accountDeletions', uid));
    if (deletion.exists) throw new HttpsError('permission-denied', 'This account is being deleted.');
    tx.set(db.doc('growthOps/config'), {...next, updatedAt: stamp(), updatedBy: uid});
    tx.create(db.collection('growthOpsAudit').doc(), {operatorUid: uid, action: 'configure', before, after: next, createdAt: stamp()});
    return next;
  });
  return {updated: true, config: cfg};
});
export const recomputeGrowthDailyMetrics = onSchedule({schedule: 'every 60 minutes', region: 'us-central1'}, async () => {
  if (!(await config()).enabled) return;
  const metrics = await computeGrowthMetrics(14);
  const batch = db.batch();
  for (const row of metrics) batch.set(db.doc(`growthDailyMetrics/${row.day}`), {...row, updatedAt: stamp()});
  await batch.commit();
});
