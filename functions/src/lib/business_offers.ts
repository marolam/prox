import * as admin from 'firebase-admin';
import {createHash} from 'node:crypto';
import {HttpsError, onCall} from 'firebase-functions/v2/https';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const stamp = () => admin.firestore.FieldValue.serverTimestamp();
const hash = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');
type Data = Record<string, any>;
const cleanId = (value: unknown, name: string): string => {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{8,120}$/.test(value)) throw new HttpsError('invalid-argument', `A stable ${name} is required.`);
  return value;
};
const cleanText = (value: unknown, name: string, max: number, min = 0): string => {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.length < min || text.length > max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(text)) throw new HttpsError('invalid-argument', `Choose a valid ${name}.`);
  return text;
};
const authed = (request: Data): string => {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in to manage offers.');
  if (request.data?.expectedUid && request.data.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'Your account changed. Reopen offers.');
  return request.auth.uid;
};
const operator = (request: Data): string => {
  const uid = authed(request);
  if (request.auth.token?.admin !== true) throw new HttpsError('permission-denied', 'Administrator review is required.');
  return uid;
};
const paidActive = (data: Data, now: number): boolean => data.businessModeActive === true &&
  (data.businessPurchased === true || (data.businessSubscriptionActive === true &&
    data.subscriptionRenewsAt instanceof admin.firestore.Timestamp && data.subscriptionRenewsAt.toMillis() > now));
const revision = (value: unknown): number => {
  if (!Number.isInteger(value) || Number(value) < 0) throw new HttpsError('invalid-argument', 'A current offer revision is required.');
  return Number(value);
};

export function offerContentIssue(data: Data): string | null {
  const content = [data.title, data.description, data.terms, data.locationLabel].join('\n');
  if (/(?:https?:\/\/|www\.|\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b|(?:\+?\d[\s().-]*){7,})/i.test(content)) return 'Keep contact details and external links in your private conversation.';
  if (/\b(?:credit\s*card|bank\s*account|social\s*security|passport\s*number|ssn)\b/i.test(content)) return 'Remove sensitive financial or identity information.';
  if (/\b(?:stolen\s+(?:goods|cards|accounts)|hire\s+(?:a\s+)?(?:hitman|assassin)|sexual\s+(?:services|content\s+with\s+(?:children|minors)))\b/i.test(content)) return 'This offer cannot be submitted.';
  return null;
}

function draft(input: Data): Data {
  const expiresAtMs = Number(input.expiresAtMs);
  if (!Number.isSafeInteger(expiresAtMs) || expiresAtMs <= 0) throw new HttpsError('invalid-argument', 'Choose an expiry date.');
  const discountPercent = input.discountPercent === null || input.discountPercent === undefined ? null : Number(input.discountPercent);
  if (discountPercent !== null && (!Number.isInteger(discountPercent) || discountPercent < 0 || discountPercent > 100)) throw new HttpsError('invalid-argument', 'Discount must be between 0 and 100 percent.');
  if (!['public', 'party'].includes(input.visibility)) throw new HttpsError('invalid-argument', 'Choose Public or confirmed Party visibility.');
  return {title: cleanText(input.title, 'title', 100, 3), description: cleanText(input.description, 'description', 2000, 10),
    terms: cleanText(input.terms, 'terms', 800), locationLabel: cleanText(input.locationLabel, 'broad service area', 100),
    expiresAtMs, discountPercent, visibility: input.visibility};
}

function requireExpiry(data: Data, now: number): void {
  if (data.expiresAtMs < now + 60000 || data.expiresAtMs > now + 30 * 86400000) throw new HttpsError('invalid-argument', 'Expiry must be within the next 30 days.');
}

function requireSafeContent(data: Data): void {
  const issue = offerContentIssue(data);
  if (issue) throw new HttpsError('invalid-argument', issue);
}

async function ownerContext(tx: FirebaseFirestore.Transaction, uid: string) {
  const [user, entitlement, deletion] = await tx.getAll(db.doc(`users/${uid}`), db.doc(`users/${uid}/billing/entitlements`), db.doc(`accountDeletions/${uid}`));
  if (!user.exists || deletion.exists) throw new HttpsError('failed-precondition', 'Account is unavailable or being deleted.');
  return {user, entitlement};
}

function checkOffer(snapshot: FirebaseFirestore.DocumentSnapshot, uid: string, expectedRevision: number): Data {
  if (!snapshot.exists || snapshot.get('uid') !== uid || snapshot.get('status') === 'deleted') throw new HttpsError('not-found', 'Offer is unavailable.');
  if (snapshot.get('revision') !== expectedRevision) throw new HttpsError('aborted', 'This offer changed. Refresh it before saving.');
  return snapshot.data()!;
}

function receiptRef(uid: string, requestId: string) { return db.doc(`businessOfferRequests/${hash([uid, requestId])}`); }
function replay(receipt: FirebaseFirestore.DocumentSnapshot, fingerprint: string): Data | null {
  if (!receipt.exists) return null;
  if (receipt.get('fingerprint') !== fingerprint) throw new HttpsError('already-exists', 'This request ID was used for a different offer action.');
  return {...receipt.get('result'), replayed: true};
}

export async function saveBusinessOfferForUid(uid: string, input: Data): Promise<Data> {
  const offerId = cleanId(input.offerId, 'offer ID');
  const requestId = cleanId(input.requestId, 'request ID');
  const expected = revision(input.expectedRevision);
  const normalized = draft(input.draft || {});
  if (typeof input.submitForReview !== 'boolean') throw new HttpsError('invalid-argument', 'Choose whether to submit for review.');
  const fingerprint = hash(['save', offerId, expected, normalized, input.submitForReview]);
  const source = db.doc(`businessOffers/${offerId}`);
  const receipt = receiptRef(uid, requestId);
  const now = Date.now();
  return db.runTransaction(async tx => {
    const context = await ownerContext(tx, uid);
    const [prior, claimed, budget, owned, tombstone] = await Promise.all([tx.get(source), tx.get(receipt),
      tx.get(db.doc(`businessOfferBudgets/${hash([uid, new Date(now).toISOString().slice(0, 10)])}`)),
      tx.get(db.collection('businessOffers').where('uid', '==', uid)), tx.get(db.doc(`businessOfferTombstones/${offerId}`))]);
    const duplicate = replay(claimed, fingerprint);
    if (duplicate) return duplicate;
    if (tombstone.exists) throw new HttpsError('not-found', 'This offer was deleted. Create a new one.');
    if (!paidActive(context.entitlement.data() || {}, now)) throw new HttpsError('permission-denied', 'Active paid Pro access is required to create or edit an offer.');
    requireExpiry(normalized, now);
    if (input.submitForReview) requireSafeContent(normalized);
    if (prior.exists) checkOffer(prior, uid, expected);
    else if (expected !== 0) throw new HttpsError('aborted', 'This offer is no longer available.');
    const existing = owned.docs.filter(doc => doc.get('status') !== 'deleted');
    if (!prior.exists && existing.length >= 20) throw new HttpsError('resource-exhausted', 'Keep up to 20 saved offers. Delete an older offer first.');
    const requests = Number(budget.get('writes') || 0);
    const creates = Number(budget.get('creates') || 0);
    if (requests >= 100 || (!prior.exists && creates >= 20)) throw new HttpsError('resource-exhausted', 'Today’s offer editing limit has been reached.');
    const result = {offerId, revision: expected + 1, status: input.submitForReview ? 'pending_review' : 'draft', replayed: false};
    tx.set(source, {...normalized, expiresAt: admin.firestore.Timestamp.fromMillis(normalized.expiresAtMs), uid, ownerUid: uid,
      ...result, moderationStatus: input.submitForReview ? 'pending' : 'unreviewed', moderationReason: '',
      createdAt: prior.exists ? prior.get('createdAt') || stamp() : stamp(), updatedAt: stamp()});
    tx.delete(db.doc(`publicBusinessOffers/${offerId}`));
    tx.set(budget.ref, {uid, writes: requests + 1, creates: creates + (prior.exists ? 0 : 1), updatedAt: stamp()}, {merge: true});
    tx.create(receipt, {uid, offerId, fingerprint, result, createdAt: stamp()});
    return result;
  });
}

export async function changeBusinessOfferForUid(uid: string, input: Data): Promise<Data> {
  const offerId = cleanId(input.offerId, 'offer ID'), requestId = cleanId(input.requestId, 'request ID');
  const expected = revision(input.expectedRevision);
  if (!['withdraw', 'delete', 'submit'].includes(input.action)) throw new HttpsError('invalid-argument', 'Choose a valid offer action.');
  const fingerprint = hash(['change', offerId, expected, input.action]);
  const source = db.doc(`businessOffers/${offerId}`), receipt = receiptRef(uid, requestId);
  const budgetRef = db.doc(`businessOfferBudgets/${hash([uid, new Date().toISOString().slice(0, 10)])}`);
  return db.runTransaction(async tx => {
    const context = await ownerContext(tx, uid);
    const [prior, claimed, budget] = await tx.getAll(source, receipt, budgetRef);
    const duplicate = replay(claimed, fingerprint);
    if (duplicate) return duplicate;
    const data = checkOffer(prior, uid, expected);
    if (input.action === 'submit') {
      if (!paidActive(context.entitlement.data() || {}, Date.now())) throw new HttpsError('permission-denied', 'Active paid Pro access is required to publish an offer.');
      requireExpiry(data, Date.now()); requireSafeContent(data);
      if (Number(budget.get('writes') || 0) >= 100) throw new HttpsError('resource-exhausted', 'Today’s offer editing limit has been reached.');
    }
    const status = input.action === 'submit' ? 'pending_review' : input.action === 'delete' ? 'deleted' : 'paused';
    const result = {offerId, revision: expected + 1, status, replayed: false};
    if (status === 'deleted') {
      tx.delete(source);
      tx.set(db.doc(`businessOfferTombstones/${offerId}`), {uid, offerId, revision: result.revision, deletedAt: stamp()});
    }
    else tx.update(source, {...result, ...(status === 'pending_review' ? {moderationStatus: 'pending', moderationReason: ''} : {}), updatedAt: stamp()});
    tx.delete(db.doc(`publicBusinessOffers/${offerId}`));
    if (input.action === 'submit') tx.set(budgetRef, {uid, writes: Number(budget.get('writes') || 0) + 1, updatedAt: stamp()}, {merge: true});
    tx.create(receipt, {uid, offerId, fingerprint, result, createdAt: stamp()});
    return result;
  });
}

export async function reviewBusinessOfferForOperator(operatorUid: string, input: Data): Promise<Data> {
  const offerId = cleanId(input.offerId, 'offer ID'), requestId = cleanId(input.requestId, 'request ID');
  const expected = revision(input.expectedRevision);
  if (!['approve', 'reject'].includes(input.decision)) throw new HttpsError('invalid-argument', 'Choose approval or rejection.');
  const reason = cleanText(input.reason, 'review note', 800, input.decision === 'reject' ? 5 : 0);
  const fingerprint = hash(['review', offerId, expected, input.decision, reason]);
  const source = db.doc(`businessOffers/${offerId}`), receipt = receiptRef(operatorUid, requestId);
  return db.runTransaction(async tx => {
    await ownerContext(tx, operatorUid);
    const [prior, claimed] = await tx.getAll(source, receipt);
    const duplicate = replay(claimed, fingerprint);
    if (duplicate) return duplicate;
    if (!prior.exists || prior.get('status') !== 'pending_review' || prior.get('revision') !== expected) throw new HttpsError('aborted', 'Offer changed or is no longer awaiting review.');
    const data = prior.data()!;
    const context = await ownerContext(tx, data.uid);
    const owned = await tx.get(db.collection('businessOffers').where('uid', '==', data.uid));
    if (input.decision === 'approve') {
      if (!paidActive(context.entitlement.data() || {}, Date.now())) throw new HttpsError('failed-precondition', 'Owner no longer has active paid Pro access.');
      requireExpiry(data, Date.now()); requireSafeContent(data);
      if (owned.docs.filter(doc => doc.id !== offerId && doc.get('status') === 'active' && Number(doc.get('expiresAtMs')) > Date.now()).length >= 5) throw new HttpsError('resource-exhausted', 'Owner already has five live offers.');
    }
    const status = input.decision === 'approve' ? 'active' : 'rejected';
    const result = {offerId, revision: expected + 1, status, replayed: false};
    tx.update(source, {...result, moderationStatus: input.decision === 'approve' ? 'approved' : 'rejected',
      moderationReason: reason, reviewedBy: operatorUid, reviewedAt: stamp(), updatedAt: stamp()});
    const projection = db.doc(`publicBusinessOffers/${offerId}`);
    const rawName = String(context.user.get('displayName') || context.user.get('name') || 'Pro').trim().slice(0, 120);
    const ownerName = offerContentIssue({title: rawName}) || /[\u0000-\u001f]/.test(rawName) ? 'Pro' : rawName;
    if (status === 'active') tx.set(projection, {offerId, uid: data.uid, ownerUid: data.uid, ownerName,
      title: data.title, description: data.description, terms: data.terms, locationLabel: data.locationLabel,
      discountPercent: data.discountPercent, visibility: data.visibility, expiresAt: data.expiresAt,
      expiresAtMs: data.expiresAtMs, revision: result.revision, status: 'active', approvedAt: stamp()});
    else tx.delete(projection);
    tx.create(receipt, {uid: operatorUid, ownerUid: data.uid, offerId, fingerprint, result, createdAt: stamp()});
    return result;
  });
}

async function visibleOffer(viewerUid: string, snapshot: FirebaseFirestore.DocumentSnapshot, now: number): Promise<Data | null> {
  const data = snapshot.data()!;
  const uid = typeof data.uid === 'string' && !data.uid.includes('/') ? data.uid : '';
  if (!uid || data.status !== 'active' || !Number.isSafeInteger(data.expiresAtMs) || data.expiresAtMs <= now || !['party', 'public'].includes(data.visibility)) return null;
  const [owner, entitlement, deleted, blockA, blockB, partyA, partyB, canonical] = await db.getAll(db.doc(`users/${uid}`), db.doc(`users/${uid}/billing/entitlements`), db.doc(`accountDeletions/${uid}`),
    db.doc(`users/${uid}/blocks/${viewerUid}`), db.doc(`users/${viewerUid}/blocks/${uid}`), db.doc(`users/${uid}/party/${viewerUid}`), db.doc(`users/${viewerUid}/party/${uid}`), db.doc(`businessOffers/${snapshot.id}`));
  if (!owner.exists || deleted.exists || !paidActive(entitlement.data() || {}, now) || blockA.exists || blockB.exists) return null;
  if (!canonical.exists || canonical.get('uid') !== uid || canonical.get('status') !== 'active' ||
      canonical.get('moderationStatus') !== 'approved' || canonical.get('revision') !== data.revision) return null;
  if (data.visibility === 'party' && uid !== viewerUid && (partyA.get('mutual') !== true || partyB.get('mutual') !== true)) return null;
  // Structured private fields are never copied. Free text also requires human review;
  // the operator must reject exact addresses and contacts rather than treating regex as moderation.
  return {offerId: snapshot.id, ownerUid: uid, ownerName: String(data.ownerName || 'Pro'), title: data.title,
    description: data.description, terms: data.terms, locationLabel: data.locationLabel, discountPercent: data.discountPercent,
    visibility: data.visibility, expiresAtMs: data.expiresAtMs, revision: data.revision};
}

export async function listPublicBusinessOffersForUid(uid: string, input: Data = {}): Promise<Data> {
  const limit = Number(input.limit ?? 20);
  if (!Number.isInteger(limit) || limit < 1 || limit > 30) throw new HttpsError('invalid-argument', 'Offer page size must be between 1 and 30.');
  let query = db.collection('publicBusinessOffers').orderBy(admin.firestore.FieldPath.documentId()).limit(limit);
  if (input.cursor) query = query.startAfter(cleanId(input.cursor, 'cursor'));
  await db.runTransaction(tx => ownerContext(tx, uid));
  const page = await query.get();
  const offers: Data[] = [];
  for (const item of page.docs) {
    const offer = await visibleOffer(uid, item, Date.now());
    if (offer) offers.push(offer);
  }
  // A page can be empty after safety filters and still have a cursor; clients can continue to the next bounded page.
  if ((await db.doc(`accountDeletions/${uid}`).get()).exists) throw new HttpsError('failed-precondition', 'Account is being deleted.');
  return {offers, nextCursor: page.size === limit ? page.docs[page.size - 1].id : null};
}

export async function eraseDeletedOwnerOffers(uid: string): Promise<void> {
  if (!(await db.doc(`accountDeletions/${uid}`).get()).exists) return;
  for (const collection of ['businessOffers', 'publicBusinessOffers', 'businessOfferRequests', 'businessOfferBudgets', 'businessOfferTombstones']) {
    for (const field of collection === 'businessOfferRequests' ? ['uid', 'ownerUid'] : ['uid']) {
      let page: FirebaseFirestore.QuerySnapshot;
      do {
        page = await db.collection(collection).where(field, '==', uid).limit(100).get();
        const batch = db.batch();
        for (const doc of page.docs) batch.delete(doc.ref);
        if (!page.empty) await batch.commit();
      } while (!page.empty);
    }
  }
}

export const upsertBusinessOffer = onCall({region: 'us-central1'}, request => saveBusinessOfferForUid(authed(request), request.data || {}));
export const changeBusinessOfferState = onCall({region: 'us-central1'}, request => changeBusinessOfferForUid(authed(request), request.data || {}));
export const reviewBusinessOffer = onCall({region: 'us-central1'}, request => reviewBusinessOfferForOperator(operator(request), request.data || {}));
export const listPublicBusinessOffers = onCall({region: 'us-central1', timeoutSeconds: 60}, request => listPublicBusinessOffersForUid(authed(request), request.data || {}));
export const onBusinessOfferAccountDeleted = onDocumentWritten({document: 'accountDeletions/{uid}', region: 'us-central1', retry: true}, async event => {
  if (event.data?.after.exists) await eraseDeletedOwnerOffers(event.params.uid);
});
