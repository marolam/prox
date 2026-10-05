import * as admin from 'firebase-admin';
import {createHash} from 'node:crypto';
import {HttpsError, onCall} from 'firebase-functions/v2/https';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
type Data = Record<string, any>;
export const LEGACY_SUPPORT_COLLECTIONS = ['feedback', 'bugReports', 'support_tickets'] as const;
type LegacyCollection = typeof LEGACY_SUPPORT_COLLECTIONS[number];
const digest = (value: unknown) => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const text = (value: unknown, max = 10000): string => typeof value === 'string' ? value.trim().slice(0, max) : '';
const sourceAllowed = (value: unknown): value is LegacyCollection =>
  typeof value === 'string' && (LEGACY_SUPPORT_COLLECTIONS as readonly string[]).includes(value);

export function legacySupportTicketId(collection: string, sourceId: string): string {
  if (!sourceAllowed(collection) || !sourceId || sourceId.includes('/')) {
    throw new HttpsError('invalid-argument', 'Choose a supported legacy report.');
  }
  return `legacy_${digest([collection, sourceId]).slice(0, 48)}`;
}

function sourceOwner(data: Data): string {
  // Match the ownership priority in Firestore rules, even if a legacy document
  // contains conflicting uid aliases. A secondary alias cannot expose a report.
  const key = ['ownerUid', 'userId', 'uid', 'createdBy', 'reporterUid']
    .find(candidate => typeof data[candidate] === 'string');
  const uid = key ? text(data[key], 128) : '';
  return uid && !uid.includes('/') ? uid : '';
}

function timestamp(value: unknown, fallback: admin.firestore.Timestamp): admin.firestore.Timestamp {
  if (value instanceof admin.firestore.Timestamp) return value;
  if (value instanceof Date && Number.isFinite(value.getTime())) return admin.firestore.Timestamp.fromDate(value);
  if (typeof value === 'string') {
    const ms = Date.parse(value);
    if (Number.isFinite(ms)) return admin.firestore.Timestamp.fromMillis(ms);
  }
  return fallback;
}

function status(value: unknown): string {
  if (typeof value === 'number' || typeof value === 'string' && /^\d$/.test(value)) {
    return ['open', 'in_progress', 'resolved', 'closed'][Number(value)] || 'open';
  }
  const raw = text(value, 50).toLowerCase();
  if (['acknowledged', 'in_progress', 'resolved', 'closed'].includes(raw)) return raw;
  if (['assigned', 'claimed', 'working'].includes(raw)) return 'in_progress';
  if (['fixed', 'complete', 'completed', 'done'].includes(raw)) return 'resolved';
  return 'open';
}

function deleted(data: Data): boolean {
  return data.deleted === true || data.isDeleted === true || data.deletedAt instanceof admin.firestore.Timestamp ||
    ['deleted', 'removed'].includes(text(data.status, 50).toLowerCase());
}

function normalized(collection: LegacyCollection, source: FirebaseFirestore.DocumentSnapshot) {
  const data = source.data() || {};
  const uid = sourceOwner(data);
  const rawCategory = text(data.category || data.type, 50).toLowerCase();
  const category = collection === 'bugReports' ? 'bug' :
    ['bug', 'ux', 'billing', 'feature', 'question'].includes(rawCategory) ? rawCategory :
    rawCategory === 'feedback' || rawCategory === 'suggestion' ? 'feature' : 'question';
  const message = [data.message, data.body, data.description, data.note, data.text, data.detail]
    .map(value => text(value)).find(Boolean) || 'No additional description was included.';
  const subject = text(data.subject || data.title, 200) ||
    `${category === 'bug' ? 'Bug report' : category === 'feature' ? 'Feature suggestion' : 'Support report'}: ${message.split('\n')[0]}`.slice(0, 200);
  const sourceMetadata = data.metadata && typeof data.metadata === 'object' && !Array.isArray(data.metadata) ? data.metadata : {};
  const metadata = Object.fromEntries(Object.entries({
    version: sourceMetadata.version || sourceMetadata.appVersion || data.appVersion,
    build: sourceMetadata.build || sourceMetadata.buildNumber || data.buildNumber,
    platform: sourceMetadata.platform || data.platform,
    device: sourceMetadata.device || data.device,
    os: sourceMetadata.os || sourceMetadata.osVersion || data.osVersion,
  }).map(([key, value]) => [key, text(value, 160)]));
  const createdAt = source.createTime || admin.firestore.Timestamp.now();
  const legacyReportedCreatedAt = timestamp(data.createdAt, createdAt);
  const attachmentPaths = Array.isArray(data.attachmentPaths) ? data.attachmentPaths.filter((path: unknown) =>
    typeof path === 'string' && path.startsWith(`supportAttachments/${uid}/`) &&
      /^supportAttachments\/[^/]+\/[A-Za-z0-9_-]{8,120}\/[A-Za-z0-9_.-]+$/.test(path)).slice(0, 3) : [];
  // Feedback owners can edit the old status field; it is not operator evidence.
  const sourceStatus = collection === 'feedback' ? 'open' : status(data.status);
  const fields = {uid, ownerUid: uid, subject, message, metadata, category, status: sourceStatus,
    createdAt, legacyReportedCreatedAt, sourceCollection: collection, sourceId: source.id,
    source: text(data.source || data.route, 120) || `legacy_${collection}`,
    firstHuhMoment: text(data.firstHuhMoment, 1000), attachmentPaths};
  const fingerprint = digest({...fields, createdAt: createdAt.toMillis(), legacyReportedCreatedAt: legacyReportedCreatedAt.toMillis()});
  return {fields, fingerprint, sourceStatus};
}

/** Only legacy source paths invoke this projection; canonical replies never do. */
export async function syncLegacySupport(collection: string, sourceId: string) {
  const ticketId = legacySupportTicketId(collection, sourceId);
  const sourceRef = db.collection(collection).doc(sourceId);
  const ticketRef = db.doc(`supportTickets/${ticketId}`);
  const outcome = await db.runTransaction(async tx => {
    const [source, ticket] = await tx.getAll(sourceRef, ticketRef);
    const data = source.data() || {};
    const uid = sourceOwner(data);
    if (ticket.exists && ticket.data()?.uid !== uid && source.exists && uid) {
      // Do not transfer an existing report if a historic source's ownership
      // aliases are changed. New rules also prohibit this client mutation.
      return {ticketId, projected: false, ownerMismatch: true};
    }
    const deletion = uid ? await tx.get(db.doc(`accountDeletions/${uid}`)) : null;
    if (!source.exists || deleted(data) || !uid || deletion?.exists) {
      if (ticket.exists && ticket.data()?.sourceCollection === collection && ticket.data()?.sourceId === sourceId) {
        tx.delete(ticketRef);
      }
      return {ticketId, projected: false, deleted: true};
    }
    const {fields, fingerprint, sourceStatus} = normalized(collection as LegacyCollection, source);
    if (ticket.exists && (ticket.data()?.sourceCollection !== collection || ticket.data()?.sourceId !== sourceId)) {
      throw new HttpsError('already-exists', 'The canonical report ID is already used.');
    }
    const prior = ticket.data() || {};
    if (prior.legacyFingerprint === fingerprint) return {ticketId, projected: false, unchanged: true};
    const now = admin.firestore.Timestamp.now();
    if (!ticket.exists) {
      tx.create(ticketRef, {...fields, workflow: 'growth', severity: 'P2', labels: [fields.category],
        legacyFingerprint: fingerprint, legacySourceStatus: sourceStatus, legacySourceCategory: fields.category,
        acknowledgement: 'Received. This earlier report is now in the Prox support queue.',
        acknowledgedAutomaticallyAt: now, responseDueAt: admin.firestore.Timestamp.fromMillis(fields.createdAt.toMillis() + 86400000),
        projectedAt: now, updatedAt: now});
    } else {
      // Only source content changes propagate. Operator status/category changes,
      // response timestamps, fixed builds, and conversations remain authoritative.
      const {status: ignoredStatus, category: ignoredCategory, ...content} = fields;
      void ignoredStatus; void ignoredCategory;
      const preserveStatus = prior.status !== prior.legacySourceStatus || !!prior.firstResponseAt || !!prior.acknowledgedAt || !!prior.fixedVersion;
      const preserveCategory = prior.category !== prior.legacySourceCategory || !!prior.firstResponseAt || !!prior.acknowledgedAt;
      tx.update(ticketRef, {...content,
        ...(!preserveStatus ? {status: sourceStatus} : {}),
        ...(!preserveCategory ? {category: fields.category, labels: [fields.category]} : {}),
        legacyFingerprint: fingerprint, legacySourceStatus: sourceStatus, legacySourceCategory: fields.category,
        updatedAt: now});
    }
    return {ticketId, projected: true};
  });
  if (outcome.deleted) {
    // The parent was deleted transactionally, which makes further callable
    // replies fail. Purge orphaned replies without deleting a newly recreated
    // canonical parent if a source ID is deliberately reused later.
    for (;;) {
      if ((await ticketRef.get()).exists) break;
      const page = await ticketRef.collection('replies').limit(100).get();
      if (page.empty) break;
      const batch = db.batch();
      for (const reply of page.docs) batch.delete(reply.ref);
      await batch.commit();
    }
  }
  return outcome;
}

export const onLegacyFeedbackSupport = onDocumentWritten({document: 'feedback/{sourceId}', retry: true},
  async event => { await syncLegacySupport('feedback', event.params.sourceId); });
export const onLegacyBugReportSupport = onDocumentWritten({document: 'bugReports/{sourceId}', retry: true},
  async event => { await syncLegacySupport('bugReports', event.params.sourceId); });
export const onLegacySupportTicket = onDocumentWritten({document: 'support_tickets/{sourceId}', retry: true},
  async event => { await syncLegacySupport('support_tickets', event.params.sourceId); });

type Cursor = {version: number; collection: number; after: string};
const encodeCursor = (cursor: Cursor) => Buffer.from(JSON.stringify(cursor)).toString('base64url');
function decodeCursor(raw: unknown): Cursor {
  if (raw == null || raw === '') return {version: 1, collection: 0, after: ''};
  if (typeof raw !== 'string' || raw.length > 4096) throw new HttpsError('invalid-argument', 'The backfill cursor is invalid.');
  try {
    const cursor = JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
    if (cursor.version !== 1 || !Number.isInteger(cursor.collection) || cursor.collection < 0 || cursor.collection >= LEGACY_SUPPORT_COLLECTIONS.length ||
      typeof cursor.after !== 'string' || cursor.after.includes('/') || cursor.after.length > 1500) throw new Error('invalid');
    return cursor;
  } catch (_) { throw new HttpsError('invalid-argument', 'The backfill cursor is invalid.'); }
}

export async function backfillLegacySupportForOperator(operatorUid: string, input: Data = {}) {
  if (!operatorUid || operatorUid.includes('/')) throw new HttpsError('unauthenticated', 'Sign in as an administrator.');
  if ((await db.doc(`accountDeletions/${operatorUid}`).get()).exists) throw new HttpsError('permission-denied', 'This administrator account is being deleted.');
  const numericLimit = Number(input.limit);
  const limit = Number.isInteger(numericLimit) ? Math.max(1, Math.min(100, numericLimit)) : 25;
  const cursor = decodeCursor(input.cursor);
  let remaining = limit, processed = 0, projected = 0, removed = 0;
  while (cursor.collection < LEGACY_SUPPORT_COLLECTIONS.length && remaining > 0) {
    if ((await db.doc(`accountDeletions/${operatorUid}`).get()).exists) throw new HttpsError('permission-denied', 'This administrator account is being deleted.');
    const collection = LEGACY_SUPPORT_COLLECTIONS[cursor.collection];
    let query = db.collection(collection).orderBy(admin.firestore.FieldPath.documentId()).limit(remaining + 1);
    if (cursor.after) query = query.startAfter(cursor.after);
    const page = await query.get();
    const rows = page.docs.slice(0, remaining);
    for (const source of rows) {
      const result = await syncLegacySupport(collection, source.id);
      processed++; if (result.projected) projected++; if (result.deleted) removed++;
      remaining--; cursor.after = source.id;
    }
    if (page.size > rows.length) break;
    cursor.collection++; cursor.after = '';
  }
  const done = cursor.collection >= LEGACY_SUPPORT_COLLECTIONS.length;
  return {processed, projected, removed, done, nextCursor: done ? null : encodeCursor(cursor)};
}

/** Explicit operator action only; deploying this callable does not run a backfill. */
export const backfillLegacySupport = onCall({region: 'us-central1', timeoutSeconds: 120}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in as an administrator.');
  if (request.auth.token?.admin !== true) throw new HttpsError('permission-denied', 'An administrator account is required.');
  if (request.data?.expectedUid && request.data.expectedUid !== request.auth.uid) throw new HttpsError('failed-precondition', 'The signed-in account changed.');
  return backfillLegacySupportForOperator(request.auth.uid, request.data || {});
});
