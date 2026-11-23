import * as admin from 'firebase-admin';
import {randomBytes} from 'node:crypto';
import {onCall, HttpsError} from './lib/active_callable';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {activeEnrolledAccount} from './lib/matching_scope_policy';
import {millis, reciprocalKeywords} from './lib/background_match_policy';
import {publicProfile} from './public_profiles';
import {connectionId, writeVerifiedPartyPair} from './party_connections';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
export const ICEBREAKER_LEASE_MS = 15000;
export const ICEBREAKER_LOCATION_MS = 45000;
export const ICEBREAKER_DISTANCE_M = 30;
export const ICEBREAKER_UNCERTAINTY_M = 45;
const sessions = (uid: string) => db.doc(`icebreakerSessions/${uid}`);
const validUid = (v: unknown): v is string => typeof v === 'string' && /^[^/]{1,128}$/.test(v);
type Data = FirebaseFirestore.DocumentData;

export function icebreakerPoint(data: Data | undefined, now: number) {
  const point = data?.geopoint;
  const captured = millis(data?.locationTs);
  const accuracy = data?.accuracyMeters;
  if (!(point instanceof admin.firestore.GeoPoint) || !captured ||
      captured > now + 5000 || now - captured > ICEBREAKER_LOCATION_MS ||
      millis(data?.expiresAt) <= now || data?.cached !== false ||
      !Number.isFinite(accuracy) || accuracy < 0 || accuracy > 20) return null;
  return {latitude: point.latitude, longitude: point.longitude, accuracyMeters: accuracy as number};
}

export function icebreakerDistance(a: Data, b: Data): number {
  const r = Math.PI / 180;
  const h = Math.sin((b.latitude - a.latitude) * r / 2) ** 2 +
    Math.cos(a.latitude * r) * Math.cos(b.latitude * r) *
    Math.sin((b.longitude - a.longitude) * r / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}

export function icebreakerClose(a: Data, b: Data): boolean {
  const distance = icebreakerDistance(a, b);
  return distance <= ICEBREAKER_DISTANCE_M &&
    distance + a.accuracyMeters + b.accuracyMeters <= ICEBREAKER_UNCERTAINTY_M;
}

function live(session: Data | undefined, now: number): session is Data {
  return !!session && session.active === true && millis(session.expiresAt) > now &&
    now - millis(session.locationAt) <= ICEBREAKER_LOCATION_MS &&
    millis(session.locationAt) <= now + 5000;
}

function band(distance: number) {
  return distance <= 10 ? 'close' : distance <= 20 ? 'near' : 'around';
}

export function icebreakerSignal(a: string, b: string, tokenA: string, tokenB: string, distance: number) {
  const key = connectionId(`${a}:${tokenA}`, `${b}:${tokenB}`);
  return {key, colorIndex: parseInt(key.slice(0, 2), 16) % 8,
    symbolIndex: parseInt(key.slice(2, 4), 16) % 8, mark: key.slice(4, 8).toUpperCase(), band: band(distance)};
}

async function accountRows(tx: FirebaseFirestore.Transaction, uid: string) {
  return tx.getAll(db.doc(`users/${uid}`), db.doc(`accountDeletions/${uid}`),
    db.doc(`accountEnforcements/${uid}`), db.doc(`users/${uid}/settings/matching`),
    db.doc(`users/${uid}/presence/current`), sessions(uid));
}

function requireAccount(rows: admin.firestore.DocumentSnapshot[], now: number) {
  if (!activeEnrolledAccount(rows[0].data()) || rows[1].exists ||
      rows[2].exists && rows[2].data()?.status !== 'active') {
    throw new HttpsError('permission-denied', 'This account is unavailable.');
  }
  if (rows[0].data()?.interactionLock?.busyInMeetup === true ||
      rows[3].data()?.modeKind !== 'icebreaker' || rows[4].data()?.modeKind !== 'icebreaker') {
    throw new HttpsError('failed-precondition', 'Choose Icebreaker and keep Nearby open outside an active meetup.');
  }
  const point = icebreakerPoint(rows[4].data(), now);
  if (!point) throw new HttpsError('failed-precondition',
    'Icebreaker needs a fresh, accurate location. Try outdoors. GPS cannot confirm the same room.');
  return point;
}

async function heartbeat(uid: string, token: string) {
  return db.runTransaction(async tx => {
    const rows = await accountRows(tx, uid);
    const now = Date.now();
    const point = requireAccount(rows, now);
    const previous = rows[5].data();
    if (previous?.token === token && previous.active === false) {
      throw new HttpsError('failed-precondition', 'This Icebreaker session ended. Reopen Nearby.');
    }
    if (live(previous, now) && previous.token !== token) {
      throw new HttpsError('failed-precondition', 'Icebreaker is open on another device. Close it there first.');
    }
    const same = previous?.token === token;
    const code = same ? previous.code : randomBytes(5).toString('hex').toUpperCase();
    const codeRef = db.doc(`icebreakerCodes/${code}`);
    const existingCode = await tx.get(codeRef);
    if (existingCode.exists && existingCode.data()?.uid !== uid) {
      throw new HttpsError('aborted', 'Please reopen Nearby to create a new session.');
    }
    const expiresAt = admin.firestore.Timestamp.fromMillis(now + ICEBREAKER_LEASE_MS);
    const data = {...point, uid, token, code, active: true, expiresAt,
      locationAt: rows[4].data()!.locationTs,
      encounterId: same ? previous.encounterId || null : null};
    if (!same && typeof previous?.code === 'string') tx.delete(db.doc(`icebreakerCodes/${previous.code}`));
    tx.set(sessions(uid), data);
    tx.set(codeRef, {uid, token, expiresAt});
    return data;
  });
}

async function close(uid: string, token: string) {
  await db.runTransaction(async tx => {
    const snap = await tx.get(sessions(uid));
    const data = snap.data();
    if (data && data.token !== token) return;
    // A tombstone prevents a delayed in-flight heartbeat from reopening a closed session.
    tx.set(sessions(uid), {token, active: false,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000)});
    if (typeof data?.code === 'string') tx.delete(db.doc(`icebreakerCodes/${data.code}`));
  });
  return {stopped: true};
}

async function signal(uid: string, own: Data) {
  const now = Date.now();
  const delta = ICEBREAKER_DISTANCE_M / 110000;
  const nearby = await db.collection('icebreakerSessions')
    .where('latitude', '>=', own.latitude - delta).where('latitude', '<=', own.latitude + delta).limit(101).get();
  if (nearby.size > 100) throw new HttpsError('resource-exhausted', 'Icebreaker is crowded here. Try a smaller gathering.');
  const candidates = nearby.docs.filter(doc => doc.id !== uid && live(doc.data(), now) && icebreakerClose(own, doc.data()));
  if (candidates.length > 20) throw new HttpsError('resource-exhausted', 'Icebreaker is crowded here. Try a smaller gathering.');
  const ownUser = await db.doc(`users/${uid}`).get();
  const ownProfile = publicProfile(uid, ownUser.data() || {});
  const signals = [];
  let nearest = Infinity;
  for (const candidate of candidates) {
    const other = candidate.id;
    const rows = await db.getAll(db.doc(`users/${other}`), db.doc(`accountDeletions/${other}`),
      db.doc(`accountEnforcements/${other}`), db.doc(`users/${other}/settings/matching`),
      db.doc(`users/${other}/presence/current`), db.doc(`users/${uid}/blocks/${other}`), db.doc(`users/${other}/blocks/${uid}`));
    if (!activeEnrolledAccount(rows[0].data()) || rows[1].exists ||
        rows[2].exists && rows[2].data()?.status !== 'active' ||
        rows[3].data()?.modeKind !== 'icebreaker' || rows[4].data()?.modeKind !== 'icebreaker' ||
        rows[0].data()?.interactionLock?.busyInMeetup === true || rows[5].exists || rows[6].exists) continue;
    const point = icebreakerPoint(rows[4].data(), now);
    if (!point || !icebreakerClose(own, point)) continue;
    const distance = icebreakerDistance(own, point);
    nearest = Math.min(nearest, distance);
    if (reciprocalKeywords(ownProfile, publicProfile(other, rows[0].data() || {})).compatible) {
      signals.push(icebreakerSignal(uid, other, own.token, candidate.data().token, distance));
    }
  }
  if (signals.length > 8) throw new HttpsError('resource-exhausted', 'Too many shared signals. Try a smaller gathering.');
  signals.sort((a, b) => a.key.localeCompare(b.key));
  return {nearby: Number.isFinite(nearest), band: Number.isFinite(nearest) ? band(nearest) : 'none', signals};
}

async function codeAttempt(uid: string) {
  await db.runTransaction(async tx => {
    const ref = db.doc(`icebreakerRateLimits/${uid}`);
    const previous = (await tx.get(ref)).data();
    const minute = Math.floor(Date.now() / 60000);
    const count = previous?.minute === minute ? Number(previous.count) : 0;
    if (count >= 10) throw new HttpsError('resource-exhausted', 'Too many code attempts. Wait a minute.');
    tx.set(ref, {minute, count: count + 1, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000)});
  });
}

async function join(uid: string, token: string, rawCode: unknown) {
  const code = typeof rawCode === 'string' ? rawCode.toUpperCase().replace(/[\s-]/g, '') : '';
  if (!/^[A-F0-9]{10}$/.test(code)) throw new HttpsError('invalid-argument', 'Enter their 10-character Icebreaker code.');
  await codeAttempt(uid);
  await db.runTransaction(async tx => {
    const target = await tx.get(db.doc(`icebreakerCodes/${code}`));
    const other = target.data()?.uid;
    if (!validUid(other) || other === uid) throw new HttpsError('failed-precondition', 'Ask them to show their current Icebreaker code.');
    const a = await accountRows(tx, uid);
    const b = await accountRows(tx, other);
    const blocks = await tx.getAll(db.doc(`users/${uid}/blocks/${other}`), db.doc(`users/${other}/blocks/${uid}`));
    const now = Date.now();
    const pointA = requireAccount(a, now), pointB = requireAccount(b, now);
    const sa = a[5].data(), sb = b[5].data();
    if (blocks.some(row => row.exists)) throw new HttpsError('permission-denied', 'This encounter is unavailable.');
    if (!live(sa, now) || !live(sb, now) || sa.token !== token ||
        sb.token !== target.data()?.token || millis(target.data()?.expiresAt) <= now) {
      throw new HttpsError('failed-precondition', 'Both people should keep Nearby open and use the current code.');
    }
    if (!icebreakerClose(pointA, pointB)) throw new HttpsError('failed-precondition', 'Stand together with an accurate location before confirming.');
    const id = connectionId(`${uid}:${sa.token}`, `${other}:${sb.token}`);
    const ref = db.doc(`icebreakerEncounters/${id}`);
    const previous = await tx.get(ref);
    if (sa.encounterId && sa.encounterId !== id || sb.encounterId && sb.encounterId !== id) {
      throw new HttpsError('failed-precondition', 'Finish or cancel the current encounter first.');
    }
    if (!previous.exists) tx.set(ref, {members: [uid, other].sort(),
      tokens: {[uid]: sa.token, [other]: sb.token}, reveal: {}, add: {},
      expiresAt: admin.firestore.Timestamp.fromMillis(now + 5 * 60000), connected: false});
    tx.update(sessions(uid), {encounterId: id});
    tx.update(sessions(other), {encounterId: id});
  });
}

async function encounter(uid: string, token: string, action: string) {
  return db.runTransaction(async tx => {
    const own = await tx.get(sessions(uid));
    if (own.data()?.token !== token) throw new HttpsError('permission-denied', 'This Icebreaker session is unavailable.');
    const id = own.data()?.encounterId;
    if (!id) {
      if (action === 'observe' || action === 'cancel') return null;
      throw new HttpsError('failed-precondition', 'Confirm your encounter first.');
    }
    const ref = db.doc(`icebreakerEncounters/${id}`);
    const snap = await tx.get(ref);
    const data = snap.data();
    if (!data && action === 'cancel') {
      tx.update(own.ref, {encounterId: null});
      return null;
    }
    const other = Array.isArray(data?.members) ? data.members.find((member: string) => member !== uid) : null;
    if (!data || !validUid(other) || !data.members.includes(uid) || data.tokens?.[uid] !== token) {
      throw new HttpsError('permission-denied', 'This encounter is unavailable.');
    }
    const a = await accountRows(tx, uid), b = await accountRows(tx, other);
    const blocks = await tx.getAll(db.doc(`users/${uid}/blocks/${other}`), db.doc(`users/${other}/blocks/${uid}`));
    if (action === 'cancel') {
      tx.delete(ref);
      for (const rows of [a, b]) if (rows[5].data()?.encounterId === id) tx.update(rows[5].ref, {encounterId: null});
      return null;
    }
    const now = Date.now();
    const pointA = requireAccount(a, now), pointB = requireAccount(b, now);
    if (millis(data.expiresAt) <= now || blocks.some(row => row.exists) ||
        !live(a[5].data(), now) || !live(b[5].data(), now) ||
        a[5].data()?.token !== data.tokens[uid] || b[5].data()?.token !== data.tokens[other] ||
        !icebreakerClose(pointA, pointB)) {
      throw new HttpsError('failed-precondition', 'The encounter ended. Both people must stay together with Nearby open.');
    }
    const reveal: Record<string, boolean> = {...data.reveal};
    const add: Record<string, boolean> = {...data.add};
    if (action === 'reveal') reveal[uid] = true;
    const revealed = reveal[uid] === true && reveal[other] === true;
    if (action === 'add') {
      if (!revealed) throw new HttpsError('failed-precondition', 'Both people must agree to reveal keywords before choosing Party.');
      add[uid] = true;
    }
    const connected = data.connected === true || add[uid] === true && add[other] === true;
    if (connected && !data.connected) {
      writeVerifiedPartyPair(tx, uid, other, 'icebreaker',
        {kind: 'icebreaker', encounterId: id, verifiedAt: admin.firestore.Timestamp.fromMillis(now)});
    }
    if (action === 'reveal' || action === 'add') tx.update(ref, {reveal, add, connected});
    const fit = reciprocalKeywords(publicProfile(uid, a[0].data() || {}), publicProfile(other, b[0].data() || {}));
    return {myReveal: reveal[uid] === true, revealed, myAdd: add[uid] === true, connected,
      expiresAtMs: millis(data.expiresAt),
      ...(revealed ? {peerName: publicProfile(other, b[0].data() || {}).displayName,
        keywords: [...new Set([...fit.forA, ...fit.forB])].sort()} : {})};
  });
}

export async function icebreakerAction(uid: string, input: Record<string, unknown>) {
  const token = input.token;
  const action = input.action;
  if (!validUid(uid) || typeof token !== 'string' || !/^[a-f0-9]{32}$/.test(token) ||
      typeof action !== 'string' || !['observe', 'stop', 'join', 'reveal', 'add', 'cancel'].includes(action)) {
    throw new HttpsError('invalid-argument', 'Choose a valid Icebreaker action.');
  }
  if (action === 'stop') return close(uid, token);
  if (action === 'join') await join(uid, token, input.code);
  if (action !== 'observe') return {encounter: await encounter(uid, token, action === 'join' ? 'observe' : action)};
  const own = await heartbeat(uid, token);
  const result = await signal(uid, own);
  const paired = await encounter(uid, token, 'observe');
  const current = (await sessions(uid).get()).data();
  if (!live(current, Date.now()) || current.token !== token) {
    throw new HttpsError('failed-precondition', 'This Icebreaker session ended.');
  }
  return {...result, code: own.code, validUntilMs: Math.min(millis(current.expiresAt),
    millis(current.locationAt) + ICEBREAKER_LOCATION_MS), encounter: paired};
}

export const icebreaker = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to use Icebreaker.');
  if (request.data?.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'Your signed-in account changed.');
  return icebreakerAction(request.auth.uid, request.data || {});
});

export const sweepIcebreaker = onSchedule('every 15 minutes', async () => {
  for (const collection of ['icebreakerSessions', 'icebreakerCodes', 'icebreakerEncounters', 'icebreakerRateLimits']) {
    const expired = await db.collection(collection).where('expiresAt', '<=', admin.firestore.Timestamp.now()).limit(500).get();
    if (expired.empty) continue;
    const batch = db.batch();
    for (const row of expired.docs) batch.delete(row.ref);
    await batch.commit();
  }
});
