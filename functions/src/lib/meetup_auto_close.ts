import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions/v1';
import {ACTIVE_MEETUP_STATUSES} from '../safety_sessions';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const REQUEST_PHASE_STEPS = new Set<string>(['requested_waiting_accept']);
const ARRIVAL_PHASE_STEPS = new Set<string>(['verify_and_confirm_arrival', 'waiting_partner_arrival']);

function tsMs(value: unknown): number {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value && typeof value === 'object' && 'toMillis' in (value as object)) {
    try {
      return Number((value as FirebaseFirestore.Timestamp).toMillis()) || 0;
    } catch {
      return 0;
    }
  }
  return 0;
}

function normalizeStep(value: unknown): string {
  return String(value ?? '').trim().toLowerCase();
}

export function classifyUnresolvedOutcome(
  data: FirebaseFirestore.DocumentData,
  nowMs = Date.now(),
): 'unanswered' | 'unfinished' | 'no_show' {
  const status = String(data.status ?? '').trim().toLowerCase();
  const step = normalizeStep(data.currentStep);
  const stepDeadlineMs = tsMs(data.stepDeadlineAt);
  const aArrived = data.aArrived === true;
  const bArrived = data.bArrived === true;

  if (status === 'requested' || REQUEST_PHASE_STEPS.has(step)) return 'unanswered';
  if (aArrived !== bArrived) return 'no_show';

  // If we timed out during an arrival-waiting step, treat one-sided arrival as no-show.
  if (stepDeadlineMs > 0 && nowMs >= stepDeadlineMs && ARRIVAL_PHASE_STEPS.has(step) && aArrived !== bArrived) {
    return 'no_show';
  }

  return 'unfinished';
}

export function meetupDeadline(data: FirebaseFirestore.DocumentData, createdAt: admin.firestore.Timestamp): number {
  const hasExpiresAt = data.expiresAt instanceof admin.firestore.Timestamp;
  const hasStepDeadline = data.stepDeadlineAt instanceof admin.firestore.Timestamp;
  const expiresAtMs = tsMs(data.expiresAt);
  const stepDeadlineMs = tsMs(data.stepDeadlineAt);
  if (hasExpiresAt && hasStepDeadline) return Math.min(expiresAtMs, stepDeadlineMs);
  if (hasExpiresAt) return expiresAtMs;
  if (hasStepDeadline) return stepDeadlineMs;
  const base = data.status === 'requested' ? data.requestedAt : data.startedAt ?? data.acceptedAt;
  const timestamp = base instanceof admin.firestore.Timestamp ? base : createdAt;
  return timestamp.toMillis() + (data.status === 'requested' ? 5 * 60000 : 12 * 3600000);
}

export async function closeExpiredMeetup(ref: FirebaseFirestore.DocumentReference, now = admin.firestore.Timestamp.now()): Promise<boolean> {
  return db.runTransaction(async tx => {
    const doc = await tx.get(ref);
    const data = doc.data();
    if (!data || !ACTIVE_MEETUP_STATUSES.has(data.status) || meetupDeadline(data, doc.createTime!) > now.toMillis()) return false;
    // Re-read so a stale sweep cannot overwrite a terminal outcome.
    const completed = data.aArrived === true && data.bArrived === true;
    tx.update(ref, completed ? {
      status: 'completed', outcome: 'completed', completedAt: now, updatedAt: now,
      ratingStartedAt: now, ratingExpiresAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + 24 * 3600000),
    } : {
      status: 'auto_closed', outcome: classifyUnresolvedOutcome(data, now.toMillis()),
      autoClosedAt: now, closedAt: now, autoClosedFromStatus: data.status,
      updatedAt: now, expiresAt: admin.firestore.FieldValue.delete(),
    });
    return true;
  });
}

export async function sweepExpiredMeetups(now = admin.firestore.Timestamp.now()): Promise<number> {
  let closed = 0;
  for (const status of ACTIVE_MEETUP_STATUSES) {
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    do {
      let query = db.collection('meetups').where('status', '==', status)
        .orderBy(admin.firestore.FieldPath.documentId()).limit(300);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      for (let i = 0; i < page.docs.length; i += 20) {
        const results = await Promise.all(page.docs.slice(i, i + 20).map(doc => closeExpiredMeetup(doc.ref, now)));
        closed += results.filter(Boolean).length;
      }
      cursor = page.size === 300 ? page.docs[page.docs.length - 1] : undefined;
    } while (cursor);
  }
  return closed;
}

export const sweepMeetupAutoClose = functions.runWith({timeoutSeconds: 540}).pubsub
  .schedule('every 5 minutes').timeZone('UTC').onRun(async () => {
    const totalClosed = await sweepExpiredMeetups();
    await db.doc('dashboard/meetupAutoCloseSweep').set({totalClosed,
      lastRunAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
  });
