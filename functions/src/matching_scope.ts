import * as admin from 'firebase-admin';
import {createHash} from 'node:crypto';
import {onCall, HttpsError} from './lib/active_callable';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {millis, miles, MINUTE, DAY} from './lib/background_match_policy';
import {activeEnrolledAccount, discoveryScope, publicDiscoveryConfig, publicDiscoveryFingerprint, recentEnrollmentLocation,
  reciprocalScopeAllows, currentPublicReceipt, trustedPartyEdge, Relationship} from './lib/matching_scope_policy';
import {reconcileVerifiedPartyConnection} from './lib/party';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const accessRef = (uid: string) => db.doc(`users/${uid}/matchingAccess/current`);
const connectionId = (a: string, b: string) => createHash('sha256').update(JSON.stringify([a, b].sort())).digest('hex');
const validUid = (uid: unknown): uid is string => typeof uid === 'string' && /^[^/]{1,128}$/.test(uid);
const MAX_DIRECT = 200;
const MAX_TREE = 500;
const MAX_MUTUAL = 3;
type Reader = admin.firestore.Transaction | undefined;
type TreeMatch = {uid: string; mutualUids: string[]; mutualNames: string[]};

async function rows(refs: admin.firestore.DocumentReference[], tx?: Reader) {
  const result: admin.firestore.DocumentSnapshot[] = [];
  for (let offset = 0; offset < refs.length; offset += 300) {
    result.push(...await (tx ? tx.getAll(...refs.slice(offset, offset + 300)) : db.getAll(...refs.slice(offset, offset + 300))));
  }
  return result;
}
const partyQuery = (uid: string) => db.collection(`users/${uid}/party`).where('mutual', '==', true).limit(MAX_DIRECT);
async function partyRows(uid: string, tx?: Reader) {
  const current = await (tx ? tx.get(partyQuery(uid)) : partyQuery(uid).get());
  if (tx) return current;
  const legacy = current.docs.filter(row => row.data().metInPerson !== true && validUid(row.id) && row.id !== uid);
  if (!legacy.length) return current;
  for (let offset = 0; offset < legacy.length; offset += 10) {
    await Promise.all(legacy.slice(offset, offset + 10).map(row => reconcileVerifiedPartyConnection(uid, row.id)));
  }
  return partyQuery(uid).get();
}

const edgeRefs = (a: string, b: string) => [db.doc(`users/${a}/party/${b}`), db.doc(`users/${b}/party/${a}`),
    db.doc(`partyConnections/${connectionId(a, b)}`), db.doc(`users/${a}/blocks/${b}`), db.doc(`users/${b}/blocks/${a}`),
    db.doc(`accountDeletions/${a}`), db.doc(`accountDeletions/${b}`), db.doc(`users/${a}`), db.doc(`users/${b}`)];
function edgeIsProven(a: string, b: string, r: admin.firestore.DocumentSnapshot[]) {
  return !r.slice(3, 7).some(row => row.exists) && activeEnrolledAccount(r[7].data()) && activeEnrolledAccount(r[8].data()) &&
    r[0].data()?.connectionId === connectionId(a, b) &&
    trustedPartyEdge(a, b, r[0].data() || {}, r[1].data() || {}, r[2].data() || {});
}
/** Recheck every hop against server consent, blocks, deletion and enrolled accounts. */
async function provenEdge(a: string, b: string, tx?: Reader): Promise<boolean> {
  if (!validUid(a) || !validUid(b) || a === b) return false;
  return edgeIsProven(a, b, await rows(edgeRefs(a, b), tx));
}
async function provenEdges(edges: [string, string][]) {
  const refs = new Map<string, admin.firestore.DocumentReference>();
  for (const [a, b] of edges) for (const ref of edgeRefs(a, b)) refs.set(ref.path, ref);
  const fetched = new Map((await rows([...refs.values()])).map(row => [row.ref.path, row]));
  return edges.map(([a, b]) => edgeIsProven(a, b, edgeRefs(a, b).map(ref => fetched.get(ref.path)!)));
}

export async function trustedRelationship(a: string, b: string, tx?: Reader): Promise<{relationship: Relationship; mutualUids: string[]}> {
  if (await provenEdge(a, b, tx)) return {relationship: 'direct', mutualUids: []};
  const [pa, pb] = await Promise.all([partyRows(a, tx), partyRows(b, tx)]);
  const other = new Set(pb.docs.filter(row => row.data().metInPerson === true).map(row => row.id));
  const mutualUids: string[] = [];
  for (const bridge of pa.docs.filter(row => row.data().metInPerson === true && other.has(row.id)).map(row => row.id).sort()) {
    if (bridge !== a && bridge !== b && await provenEdge(a, bridge, tx) && await provenEdge(bridge, b, tx)) mutualUids.push(bridge);
    if (mutualUids.length >= 10) break;
  }
  return {relationship: mutualUids.length ? 'tree' : 'none', mutualUids};
}

export async function matchingPairScope(a: string, b: string, settingsA: Record<string, any>, settingsB: Record<string, any>,
  locationA: Record<string, any>, locationB: Record<string, any>, nowMs: number, tx?: Reader) {
  const receipt = await rows([accessRef(a), accessRef(b), db.doc(`users/${a}/blocks/${b}`), db.doc(`users/${b}/blocks/${a}`),
    db.doc(`accountDeletions/${a}`), db.doc(`accountDeletions/${b}`), db.doc(`users/${a}`), db.doc(`users/${b}`), db.doc('matchingConfig/publicDiscovery')], tx);
  if (receipt.slice(2, 6).some(row => row.exists) || !activeEnrolledAccount(receipt[6].data()) || !activeEnrolledAccount(receipt[7].data())) return null;
  const config = publicDiscoveryConfig(receipt[8].data());
  const fingerprint = publicDiscoveryFingerprint(config);
  const accessA = {...settingsA, publicUnlocked: !!config && receipt[0].data()?.publicConfigFingerprint === fingerprint &&
    currentPublicReceipt(receipt[0].data() || {}, locationA, nowMs)};
  const accessB = {...settingsB, publicUnlocked: !!config && receipt[1].data()?.publicConfigFingerprint === fingerprint &&
    currentPublicReceipt(receipt[1].data() || {}, locationB, nowMs)};
  // A public pair needs no private graph scan. Restricted pairs always prove their relationship at the point of use.
  if (reciprocalScopeAllows(accessA, accessB, 'none')) return {relationship: 'none' as Relationship, mutualUids: []};
  const relationship = await trustedRelationship(a, b, tx);
  return reciprocalScopeAllows(accessA, accessB, relationship.relationship) ? relationship : null;
}

export async function matchingGraph(uid: string): Promise<{directUids: string[]; treeMatches: TreeMatch[]; graphTruncated: boolean}> {
  const party = await partyRows(uid);
  const directCandidates = party.docs.filter(row => row.data().metInPerson === true && validUid(row.id) && row.id !== uid).map(row => row.id);
  const directProofs = await provenEdges(directCandidates.map(other => [uid, other]));
  const directUids = directCandidates.filter((_, i) => directProofs[i]);
  directUids.sort();
  const direct = new Set(directUids);
  const bridges = new Map<string, Set<string>>();
  const candidateEdges: [string, string][] = [];
  let graphTruncated = party.size === MAX_DIRECT;
  const branches: admin.firestore.QuerySnapshot[] = [];
  for (let offset = 0; offset < directUids.length; offset += 10) {
    branches.push(...await Promise.all(directUids.slice(offset, offset + 10).map(bridge => partyRows(bridge))));
  }
  for (let branchIndex = 0; branchIndex < directUids.length; branchIndex++) {
    const bridge = directUids[branchIndex];
    const branch = branches[branchIndex];
    graphTruncated ||= branch.size === MAX_DIRECT;
    for (const row of branch.docs) {
      if (row.id === uid || direct.has(row.id) || row.data().metInPerson !== true) continue;
      if (!bridges.has(row.id) && bridges.size >= MAX_TREE) {graphTruncated = true; continue;}
      if (!validUid(row.id)) continue;
      const known = bridges.get(row.id) || new Set<string>();
      if (known.size >= MAX_MUTUAL) continue;
      known.add(bridge);
      bridges.set(row.id, known);
      candidateEdges.push([bridge, row.id]);
    }
  }
  const proofs = await provenEdges(candidateEdges);
  const targetUids = [...bridges.keys()];
  const targetBlocks = await rows(targetUids.flatMap(other => [db.doc(`users/${uid}/blocks/${other}`), db.doc(`users/${other}/blocks/${uid}`)]));
  const blocked = new Set(targetUids.filter((_, i) => targetBlocks[2 * i].exists || targetBlocks[2 * i + 1].exists));
  const provenBridges = new Map<string, Set<string>>();
  candidateEdges.forEach(([bridge, other], i) => {
    if (!proofs[i] || blocked.has(other)) return;
    const known = provenBridges.get(other) || new Set<string>();
    known.add(bridge);
    provenBridges.set(other, known);
  });
  const profiles = directUids.length ? await rows(directUids.map(other => db.doc(`publicProfiles/${other}`))) : [];
  const names = new Map(profiles.map(row => [row.id, typeof row.data()?.displayName === 'string' && row.data()!.displayName.trim()
    ? row.data()!.displayName.trim().slice(0, 120) : 'Your Party connection']));
  const treeMatches = [...provenBridges.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([other, mutual]) => {
    const mutualUids = [...mutual].sort();
    return {uid: other, mutualUids, mutualNames: mutualUids.map(bridge => names.get(bridge) || 'Your Party connection')};
  });
  return {directUids, treeMatches, graphTruncated};
}

/** Retain the latest observed location, independent of online presence's short TTL, for 30-day enrollment density. */
export async function projectMatchingLocation(uid: string, nowMs = Date.now()) {
  const sources = await rows([db.doc(`users/${uid}/presence/current`), db.doc(`users/${uid}/backgroundPresence/current`),
    db.doc(`users/${uid}`), db.doc(`accountDeletions/${uid}`)]);
  const target = db.doc(`matchingLocations/${uid}`);
  if (!activeEnrolledAccount(sources[2].data()) || sources[3].exists) {await target.delete(); return null;}
  const locations = sources.slice(0, 2).map(row => {
    const d = row.data() || {};
    const geopoint = d.geopoint instanceof admin.firestore.GeoPoint ? d.geopoint : null;
    return {uid, latitude: geopoint?.latitude ?? d.latitude, longitude: geopoint?.longitude ?? d.longitude,
      lastSeenAt: d.ts || d.receivedAt};
  }).filter(value => recentEnrollmentLocation(value, nowMs)).sort((a, b) => millis(b.lastSeenAt) - millis(a.lastSeenAt));
  if (locations.length) {
    const value = locations[0];
    await db.runTransaction(async tx => {
      const old = await tx.get(target);
      if (millis(old.data()?.lastSeenAt) <= millis(value.lastSeenAt)) tx.set(target, {...value,
        expiresAt: admin.firestore.Timestamp.fromMillis(millis(value.lastSeenAt) + 30 * DAY)});
    });
    return value;
  }
  const previous = (await target.get()).data();
  return previous && recentEnrollmentLocation(previous, nowMs) ? previous : null;
}

function nearbyQuery(collection: admin.firestore.CollectionReference, local: Record<string, any>, radiusMiles: number) {
  const latitudeDelta = radiusMiles / 69;
  const longitudeDelta = Math.min(180, latitudeDelta / Math.max(.01, Math.cos(local.latitude * Math.PI / 180)));
  const west = local.longitude - longitudeDelta;
  const east = local.longitude + longitudeDelta;
  const longitude = west < -180
    ? admin.firestore.Filter.or(admin.firestore.Filter.where('longitude', '>=', west + 360), admin.firestore.Filter.where('longitude', '<=', east))
    : east > 180
    ? admin.firestore.Filter.or(admin.firestore.Filter.where('longitude', '>=', west), admin.firestore.Filter.where('longitude', '<=', east - 360))
    : admin.firestore.Filter.and(admin.firestore.Filter.where('longitude', '>=', west), admin.firestore.Filter.where('longitude', '<=', east));
  return collection.where(admin.firestore.Filter.and(admin.firestore.Filter.where('latitude', '>=', Math.max(-90, local.latitude - latitudeDelta)),
    admin.firestore.Filter.where('latitude', '<=', Math.min(90, local.latitude + latitudeDelta)), longitude))
    .orderBy('latitude').orderBy('longitude');
}

export async function localEnrollmentCount(local: Record<string, any>, config: {minimumUsers: number; radiusMiles: number; activeWithinDays?: number}, nowMs = Date.now()) {
  const base = nearbyQuery(db.collection('matchingLocations'), local, config.radiusMiles);
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
  let count = 0;
  // At most 5,000 geographically bounded rows; hitting the cap can only delay unlocking.
  for (let page = 0; page < 10 && count < config.minimumUsers; page++) {
    const batch = await (cursor ? base.startAfter(cursor) : base).limit(500).get();
    const candidates = batch.docs.filter(row => validUid(row.id) && recentEnrollmentLocation(row.data(), nowMs, config.activeWithinDays ?? 30) && miles(local, row.data()) <= config.radiusMiles);
    if (candidates.length) {
      const state = await rows(candidates.flatMap(row => [db.doc(`users/${row.id}`), db.doc(`accountDeletions/${row.id}`)]));
      for (let i = 0; i < candidates.length; i++) if (activeEnrolledAccount(state[2 * i].data()) && !state[2 * i + 1].exists) count++;
    }
    if (batch.size < 500) break;
    cursor = batch.docs[batch.docs.length - 1];
  }
  return count;
}

export async function refreshMatchingAccess(uid: string, includeGraph = true, nowMs = Date.now()) {
  if (!validUid(uid)) throw new HttpsError('invalid-argument', 'Invalid account.');
  const local = await projectMatchingLocation(uid, nowMs);
  const config = publicDiscoveryConfig((await db.doc('matchingConfig/publicDiscovery').get()).data());
  const publicUnlocked = !!(local && config && await localEnrollmentCount(local, config, nowMs) >= config.minimumUsers);
  const graphVersion = includeGraph ? Number((await accessRef(uid).get()).data()?.graphVersion || 0) : 0;
  const graph = includeGraph ? await matchingGraph(uid) : null;
  return db.runTransaction(async tx => {
    const reference = accessRef(uid);
    const settingRef = db.doc(`users/${uid}/settings/matching`);
    const [previous, settings, account, deletion] = await tx.getAll(reference, settingRef, db.doc(`users/${uid}`), db.doc(`accountDeletions/${uid}`));
    if (!activeEnrolledAccount(account.data()) || deletion.exists) throw new HttpsError('failed-precondition', 'This account is unavailable.');
    const old = previous.data() || {};
    const freshGraph = graph && Number(old.graphVersion || 0) === graphVersion ? graph : null;
    const firstUnlock = publicUnlocked && !millis(old.publicUnlockedAt);
    let partyScope = discoveryScope(settings.data()?.partyScope);
    if (firstUnlock && partyScope !== 'partyOnly') {
      partyScope = 'public';
      tx.set(settingRef, {partyScope}, {merge: true});
    }
    const next = {publicUnlocked, partyScope, publicUnlockedAt: firstUnlock ? admin.firestore.Timestamp.fromMillis(nowMs) : old.publicUnlockedAt || null,
      publicConfigFingerprint: publicDiscoveryFingerprint(config),
      publicUnlockNotifiedAt: old.publicUnlockNotifiedAt || null, checkedAt: admin.firestore.Timestamp.fromMillis(nowMs),
      latitude: local?.latitude ?? null, longitude: local?.longitude ?? null,
      ...(freshGraph ? {...freshGraph, graphInvalidated: false, graphCheckedAt: admin.firestore.Timestamp.fromMillis(nowMs)} : {})};
    tx.set(reference, next, {merge: true});
    return {...old, ...next};
  });
}

function authenticatedUid(request: {auth?: {uid: string}; data?: any}) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to view matching access.');
  if (request.data?.expectedUid != null && request.data.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'The signed-in account changed.');
  return request.auth.uid;
}

export const getMatchingAccess = onCall(async request => {
  const data: Record<string, any> = await refreshMatchingAccess(authenticatedUid(request));
  return {publicUnlocked: data.publicUnlocked === true, partyScope: data.partyScope,
    checkedAt: millis(data.checkedAt) || null, latitude: Number.isFinite(data.latitude) ? data.latitude : null,
    longitude: Number.isFinite(data.longitude) ? data.longitude : null,
    publicUnlockedAt: millis(data.publicUnlockedAt) || null, publicUnlockNotifiedAt: millis(data.publicUnlockNotifiedAt) || null,
    directUids: data.directUids || [], treeMatches: data.treeMatches || [], graphTruncated: data.graphTruncated === true,
    graphInvalidated: data.graphInvalidated === true};
});

export const acknowledgePublicMatchingUnlock = onCall(async request => {
  const uid = authenticatedUid(request);
  return db.runTransaction(async tx => {
    const [access, deletion] = await tx.getAll(accessRef(uid), db.doc(`accountDeletions/${uid}`));
    const d = access.data();
    if (deletion.exists || !d?.publicUnlockedAt) throw new HttpsError('failed-precondition', 'Public matching has not opened for this account.');
    if (!d.publicUnlockNotifiedAt) tx.update(access.ref, {publicUnlockNotifiedAt: admin.firestore.Timestamp.now()});
    return {acknowledged: true};
  });
});

export const onMatchingForegroundPresence = onDocumentWritten({document: 'users/{uid}/presence/current', retry: true}, async event => {
  if (!event.data?.after.exists) return;
  // Coordinate projection writes trigger again; only a fresh presence timestamp merits a new density scan.
  if (millis(event.data.before.data()?.ts) === millis(event.data.after.data()?.ts)) return;
  const prior = await accessRef(event.params.uid).get();
  const local = event.data.after.data()?.geopoint;
  const old = prior.data() || {};
  await projectMatchingLocation(event.params.uid);
  if (Date.now() - millis(old.checkedAt) < MINUTE && local instanceof admin.firestore.GeoPoint &&
      Number.isFinite(old.latitude) && Number.isFinite(old.longitude) && miles(old, local) <= .1) return;
  try {await refreshMatchingAccess(event.params.uid, false);}
  catch (error) {if (!(error instanceof HttpsError) || error.code !== 'failed-precondition') throw error;}
});

export const onMatchingScopeChanged = onDocumentWritten({document: 'users/{uid}/settings/matching', retry: true}, async event => {
  if (!event.data?.after.exists || event.data.before.data()?.partyScope === event.data.after.data()?.partyScope) return;
  await db.runTransaction(async tx => {
    const [receipt, current] = await tx.getAll(accessRef(event.params.uid), db.doc(`users/${event.params.uid}/settings/matching`));
    if (receipt.exists && current.exists && receipt.data()?.partyScope !== discoveryScope(current.data()?.partyScope)) {
      tx.update(receipt.ref, {partyScope: discoveryScope(current.data()?.partyScope)});
    }
  });
});

/** Clear all affected two-hop receipts before rebuilding. Neighbors refresh their invalidated graph through the callable. */
export async function invalidateMatchingGraphs(a: string, b: string) {
  if (!validUid(a) || !validUid(b) || a === b) return;
  const [pa, pb] = await Promise.all([partyRows(a), partyRows(b)]);
  const affected = [...new Set([a, b, ...pa.docs.map(row => row.id), ...pb.docs.map(row => row.id)])].filter(validUid);
  const receipts = await rows(affected.map(accessRef));
  const batch = db.batch();
  for (const receipt of receipts) if (receipt.exists) batch.update(receipt.ref, {
    directUids: [], treeMatches: [], graphInvalidated: true, graphCheckedAt: null, graphVersion: admin.firestore.FieldValue.increment(1),
  });
  await batch.commit();
  for (const uid of [a, b]) {
    const [account, deleted, receipt] = await rows([db.doc(`users/${uid}`), db.doc(`accountDeletions/${uid}`), accessRef(uid)]);
    if (!receipt.exists || deleted.exists || !activeEnrolledAccount(account.data())) continue;
    const graph = await matchingGraph(uid);
    // The callable and change triggers always rebuild from current consent; old event payloads never restore memberships.
    await db.runTransaction(async tx => {
      const current = await tx.get(receipt.ref);
      if (current.exists && Number(current.data()?.graphVersion || 0) === Number(receipt.data()?.graphVersion || 0)) {
        tx.set(receipt.ref, {...graph, graphInvalidated: false, graphCheckedAt: admin.firestore.Timestamp.now()}, {merge: true});
      }
    });
  }
}

export const onMatchingPartyChanged = onDocumentWritten({document: 'users/{uid}/party/{friendUid}', retry: true}, async event => {
  const before = event.data?.before.data() || {};
  const after = event.data?.after.data() || {};
  if (['mutual', 'metInPerson', 'connectionId'].every(key => before[key] === after[key]) &&
      event.data?.before.exists === event.data?.after.exists) return;
  await invalidateMatchingGraphs(event.params.uid, event.params.friendUid);
});

export const onMatchingBlockChanged = onDocumentWritten({document: 'users/{uid}/blocks/{otherUid}', retry: true}, async event => {
  if (event.data?.before.exists === event.data?.after.exists) return;
  await invalidateMatchingGraphs(event.params.uid, event.params.otherUid);
});
