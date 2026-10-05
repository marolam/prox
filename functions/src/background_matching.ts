import * as admin from 'firebase-admin';
import {createHash, randomUUID} from 'node:crypto';
import {onDocumentWritten, onDocumentCreated} from 'firebase-functions/v2/firestore';
import {onCall, HttpsError} from 'firebase-functions/v2/https';
import {alertAllowed, DAY, liveLocation, matchesCriteria, miles, millis, MINUTE, quietNow, reciprocalKeywords} from './lib/background_match_policy';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const hash = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const validUid = (uid: unknown): uid is string => typeof uid === 'string' && /^[^/]{1,128}$/.test(uid);
const prefs = (uid: string) => db.doc(`users/${uid}/settings/backgroundMatching`);
const presence = (uid: string) => db.doc(`users/${uid}/backgroundPresence/current`);
const profile = (uid: string) => db.doc(`publicProfiles/${uid}`);
const mode = (uid: string) => db.doc(`users/${uid}/settings/matching`);
const requiresParty = (s: Record<string, any>) => ['partyOnly', 'tree', 'extendedOnly'].includes(s.partyScope);
const radius = (s: Record<string, any>) => Math.max(.1, Math.min(10, Number(s.radiusMiles) || 2));

// Canonical ordering is shared by creation, delivery, and opening an opportunity.
const pairRefs = (a: string, b: string) => [prefs(a), prefs(b), presence(a), presence(b), profile(a), profile(b), mode(a), mode(b),
  db.doc(`accountDeletions/${a}`), db.doc(`accountDeletions/${b}`),
  db.doc(`users/${a}/blocks/${b}`), db.doc(`users/${b}/blocks/${a}`),
  db.doc(`users/${a}/party/${b}`), db.doc(`users/${b}/party/${a}`)];

function eligiblePair(rows: admin.firestore.DocumentSnapshot[], nowMs: number) {
  if (rows.slice(8, 12).some(row => row.exists) || !rows[4].exists || !rows[5].exists) return null;
  const data = rows.map(row => row.data() || {});
  const [pa, pb, la, lb, ua, ub, sa, sb] = data;
  if (pa.enabled !== true || pb.enabled !== true || !liveLocation(la, nowMs) || !liveLocation(lb, nowMs) ||
      !pa.deviceId || !pb.deviceId || la.deviceId !== pa.deviceId || lb.deviceId !== pb.deviceId ||
      ua.busyInMeetup || ub.busyInMeetup) return null;
  const kind = sa.modeKind || 'normal';
  if (kind !== (sb.modeKind || 'normal') || !['normal', 'listen', 'travel'].includes(kind)) return null;
  const distance = miles(la, lb);
  const uncertainty = (la.accuracyMeters + lb.accuracyMeters) / 1609.344;
  const maximum = Math.min(radius(sa), radius(sb));
  if (distance + uncertainty > maximum) return null;
  if (kind === 'travel') {
    const moving = (p: Record<string, any>) => nowMs - millis(p.locationAt) <= 90 * 1000 && p.speedMps >= .6 && p.speedMps <= 100;
    if (!moving(la) || !moving(lb)) return null;
    const movementMiles = (la.speedMps * Math.max(0, nowMs - millis(la.locationAt)) +
      lb.speedMps * Math.max(0, nowMs - millis(lb.locationAt))) / 1000 / 1609.344;
    if (distance + uncertainty + movementMiles > maximum) return null;
  }
  const fit = reciprocalKeywords(ua, ub);
  if (kind !== 'listen' && (!matchesCriteria(sa, ub, fit) ||
      !matchesCriteria(sb, ua, {forA: fit.forB, forB: fit.forA, significant: fit.significant, compatible: fit.compatible}) ||
      (requiresParty(sa) && data[12].mutual !== true) || (requiresParty(sb) && data[13].mutual !== true))) return null;
  return {data, kind, fit, significant: kind === 'normal' && fit.significant};
}

/** Revalidate both people inside the same transaction that reserves notification budgets. */
export async function recordBackgroundOpportunity(a: string, b: string, nowMs = Date.now()) {
  if (!validUid(a) || !validUid(b) || a === b) return false;
  const id = hash([a, b].sort());
  const now = admin.firestore.Timestamp.fromMillis(nowMs);
  return db.runTransaction(async tx => {
    const refs = [...pairRefs(a, b),
      db.doc(`users/${a}/backgroundAlertState/current`), db.doc(`users/${b}/backgroundAlertState/current`),
      db.doc(`users/${a}/backgroundAlertPairs/${id}`), db.doc(`users/${b}/backgroundAlertPairs/${id}`)];
    const rows = await tx.getAll(...refs);
    const eligible = eligiblePair(rows, nowMs);
    if (!eligible) return false;
    const {data, kind, fit, significant} = eligible;
    const [, , la, lb] = data;
    // The minimum keyword strength is not purchasable and cannot be reduced by a client setting.
    const expiresAt = admin.firestore.Timestamp.fromMillis(nowMs + 30 * MINUTE);
    for (const [i, uid, other] of [[0, a, b], [1, b, a]] as const) {
      const pref = data[i];
      const history = Array.isArray(data[14 + i].sentAt) ? data[14 + i].sentAt.filter((t: unknown) => typeof t === 'number') : [];
      tx.set(db.doc(`users/${uid}/backgroundOpportunities/${id}`), {
        otherUid: other, modeKind: kind, significant, updatedAt: now, expiresAt,
        forYou: i === 0 ? fit.forA : fit.forB, forThem: i === 0 ? fit.forB : fit.forA,
      });
      // Do not encourage an interruption while either device reports driving speed.
      if (!significant || la.speedMps >= 7 || lb.speedMps >= 7 ||
          !alertAllowed({...pref, utcOffsetMinutes: data[2 + i].utcOffsetMinutes}, history,
            millis(data[16 + i].lastSentAt), nowMs)) continue;
      tx.set(refs[14 + i], {sentAt: [...history.filter((t: number) => nowMs - t < DAY), nowMs]});
      tx.set(refs[16 + i], {otherUid: other, lastSentAt: now,
        expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + 8 * DAY)});
      tx.create(db.doc(`users/${uid}/backgroundAlertOutbox/${randomUUID()}`), {
        otherUid: other, opportunityId: id, createdAt: now, expiresAt, state: 'pending',
        forYouCount: i === 0 ? fit.forA.length : fit.forB.length,
        forThemCount: i === 0 ? fit.forB.length : fit.forA.length,
      });
    }
    return true;
  });
}

/** Bounded geographic scan on a location update, never a global user scan or phone-side live query. */
export async function scanBackgroundMatches(uid: string, nowMs = Date.now()) {
  if (!validUid(uid)) return;
  const [p, l, s, deleted, mine] = await db.getAll(prefs(uid), presence(uid), mode(uid), db.doc(`accountDeletions/${uid}`), profile(uid));
  const local = l.data() || {};
  const settings = s.data() || {};
  if (!p.data()?.enabled || deleted.exists || !mine.exists || !liveLocation(local, nowMs) ||
      local.deviceId !== p.data()?.deviceId || ['off', 'treasureHunt'].includes(settings.modeKind)) return;
  const gate = db.doc(`users/${uid}/backgroundScanState/current`);
  const admitted = await db.runTransaction(async tx => {
    const old = await tx.get(gate);
    const interval = settings.modeKind === 'travel' ? MINUTE : 5 * MINUTE;
    if (nowMs - millis(old.data()?.scannedAt) < interval) return false;
    tx.set(gate, {scannedAt: admin.firestore.Timestamp.fromMillis(nowMs)});
    return true;
  });
  if (!admitted) return;
  const latitudeDelta = radius(settings) / 69;
  const longitudeDelta = Math.min(180, latitudeDelta / Math.max(.01, Math.cos(local.latitude * Math.PI / 180)));
  const west = local.longitude - longitudeDelta;
  const east = local.longitude + longitudeDelta;
  const longitude = west < -180
    ? admin.firestore.Filter.or(admin.firestore.Filter.where('longitude', '>=', west + 360), admin.firestore.Filter.where('longitude', '<=', east))
    : east > 180
    ? admin.firestore.Filter.or(admin.firestore.Filter.where('longitude', '>=', west), admin.firestore.Filter.where('longitude', '<=', east - 360))
    : admin.firestore.Filter.and(admin.firestore.Filter.where('longitude', '>=', west), admin.firestore.Filter.where('longitude', '<=', east));
  const candidates = await db.collectionGroup('backgroundPresence').where(admin.firestore.Filter.and(
    admin.firestore.Filter.where('enabled', '==', true),
    admin.firestore.Filter.where('latitude', '>=', Math.max(-90, local.latitude - latitudeDelta)),
    admin.firestore.Filter.where('latitude', '<=', Math.min(90, local.latitude + latitudeDelta)), longitude,
  )).orderBy('latitude').orderBy('longitude').limit(80).get();
  const peers = candidates.docs.filter(doc => doc.id === 'current' && doc.ref.parent.parent?.id !== uid &&
      liveLocation(doc.data(), nowMs) && miles(local, doc.data()) <= radius(settings))
    .sort((a, b) => miles(local, a.data()) - miles(local, b.data())).slice(0, 24);
  if (!peers.length) return;
  const profiles = await db.getAll(...peers.map(doc => profile(doc.ref.parent.parent!.id)));
  const ranked = profiles.filter(doc => doc.exists).map(doc => ({uid: doc.id, fit: reciprocalKeywords(mine.data()!, doc.data()!)}))
    .filter(item => settings.modeKind === 'listen' || item.fit.compatible)
    .sort((a, b) => Number(b.fit.significant) - Number(a.fit.significant) ||
      (b.fit.forA.length + b.fit.forB.length) - (a.fit.forA.length + a.fit.forB.length));
  let recorded = 0;
  for (const peer of ranked.slice(0, 8)) {
    if (await recordBackgroundOpportunity(uid, peer.uid, nowMs)) recorded++;
    if (recorded >= 3) break;
  }
}

export const onBackgroundPresence = onDocumentWritten({document: 'users/{uid}/backgroundPresence/current', retry: true}, async event => {
  if (event.data?.after.exists) await scanBackgroundMatches(event.params.uid);
});

/** A claim is durable BEFORE FCM. Ambiguous delivery is not retried: fewer alerts beats duplicate interruptions. */
export async function dispatchBackgroundAlert(uid: string, alertId: string,
  send = (message: admin.messaging.MulticastMessage) => admin.messaging().sendEachForMulticast(message)) {
  const ref = db.doc(`users/${uid}/backgroundAlertOutbox/${alertId}`);
  const claimed = await db.runTransaction(async tx => {
    const alert = await tx.get(ref);
    const d = alert.data();
    if (!d || d.state !== 'pending') return null;
    const now = Date.now();
    const other = d.otherUid;
    if (!validUid(other)) return null;
    const rows = await tx.getAll(...pairRefs(uid, other));
    const eligible = eligiblePair(rows, now);
    const r = rows.map(row => row.data() || {});
    const allowed = millis(d.expiresAt) > now && eligible?.significant === true &&
      r[0].notificationsEnabled === true && r[2].speedMps < 7 && r[3].speedMps < 7 &&
      !quietNow({...r[0], utcOffsetMinutes: r[2].utcOffsetMinutes}, now);
    tx.update(ref, {state: allowed ? 'attempted' : 'suppressed', attemptedAt: admin.firestore.Timestamp.now()});
    return allowed ? {...d, opportunityId: String(d.opportunityId), soundEnabled: r[0].soundEnabled !== false} : null;
  });
  if (!claimed) return;
  const tokens = await db.collection(`users/${uid}/deviceTokens`).limit(20).get();
  const valid = tokens.docs.filter(doc => doc.data().valid !== false &&
    (!doc.data().expiresAt || millis(doc.data().expiresAt) > Date.now()));
  if (!valid.length) return;
  const eventId = hash([uid, alertId]);
  const response = await send({tokens: valid.map(doc => doc.id),
    notification: {title: 'Significant match nearby', body: 'Multiple interests match in both directions. Open Prox to see why this connection stands out.'},
    data: {type: 'significant_match', eventId, opportunityId: claimed.opportunityId},
    android: {priority: 'high', ttl: 10 * MINUTE, notification: {channelId: claimed.soundEnabled ? 'significant_matches' : 'significant_matches_silent', tag: eventId}},
    apns: {headers: {'apns-priority': '10', 'apns-expiration': String(Math.floor((Date.now() + 10 * MINUTE) / 1000)), 'apns-collapse-id': eventId},
      payload: {aps: {...(claimed.soundEnabled ? {sound: 'default'} : {}), 'thread-id': 'significant-matches'}}},
  });
  await Promise.all(response.responses.map((result, i) => !result.success &&
    ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(result.error?.code || '')
    ? valid[i].ref.delete() : Promise.resolve()));
  await ref.update({state: 'sent', deliveredDevices: response.successCount});
}
export const onBackgroundMatchAlert = onDocumentCreated({document: 'users/{uid}/backgroundAlertOutbox/{alertId}', retry: true}, async event => {
  await dispatchBackgroundAlert(event.params.uid, event.params.alertId);
});

/** Snapshot receipts disclose neither location nor a stale or newly blocked profile. */
export async function readBackgroundOpportunity(uid: string, id: string) {
  const row = await db.doc(`users/${uid}/backgroundOpportunities/${id}`).get();
  const d = row.data();
  const now = Date.now();
  if (!d || millis(d.expiresAt) <= now || !validUid(d.otherUid)) return {available: false};
  const rows = await db.getAll(...pairRefs(uid, d.otherUid));
  const eligible = eligiblePair(rows, now);
  if (!eligible || eligible.kind !== d.modeKind) return {available: false};
  const {data, fit, significant, kind} = eligible;
  return {available: true, opportunityId: id, otherUid: d.otherUid, modeKind: kind,
    significant, forYou: fit.forA, forThem: fit.forB,
    displayName: typeof data[5].displayName === 'string' ? data[5].displayName : 'Nearby Prox user'};
}

export const getBackgroundOpportunity = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to view this opportunity.');
  if (request.data?.expectedUid != null && request.data.expectedUid !== request.auth.uid) {
    throw new HttpsError('failed-precondition', 'The signed-in account changed.');
  }
  const id = request.data?.opportunityId;
  if (typeof id !== 'string' || !/^[a-f0-9]{64}$/.test(id)) throw new HttpsError('invalid-argument', 'Invalid opportunity.');
  return readBackgroundOpportunity(request.auth.uid, id);
});

export const listBackgroundOpportunities = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to view opportunities.');
  if (request.data?.expectedUid != null && request.data.expectedUid !== request.auth.uid) {
    throw new HttpsError('failed-precondition', 'The signed-in account changed.');
  }
  const uid = request.auth.uid;
  const recent = await db.collection(`users/${uid}/backgroundOpportunities`).orderBy('updatedAt', 'desc').limit(12).get();
  const opportunities = await Promise.all(recent.docs.map(row => readBackgroundOpportunity(uid, row.id)));
  return {opportunities: opportunities.filter(row => row.available)};
});
