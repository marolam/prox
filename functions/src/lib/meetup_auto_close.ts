import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

const PENDING_AUTO_CLOSE_MS = 12 * 60 * 60 * 1000; // 12h
const LIVE_AUTO_CLOSE_MS = 24 * 60 * 60 * 1000; // 24h
const QUERY_LIMIT = 300;

function toDate(v: unknown): Date | null {
  if (v instanceof admin.firestore.Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  return null;
}

function ageMs(now: Date, base: Date | null): number {
  if (!base) return 0;
  return now.getTime() - base.getTime();
}

async function sweepStatus(status: string, now: Date): Promise<number> {
  const snap = await db
    .collection("meetups")
    .where("status", "==", status)
    .limit(QUERY_LIMIT)
    .get();

  if (snap.empty) return 0;

  const batch = db.batch();
  let closed = 0;

  for (const doc of snap.docs) {
    const d = doc.data() as Record<string, unknown>;

    const base =
      toDate(d["startedAt"]) ??
      toDate(d["requestedAt"]) ??
      toDate(d["createdAt"]) ??
      toDate(d["updatedAt"]);

    if (!base) continue;

    const ttl = status === "live" ? LIVE_AUTO_CLOSE_MS : PENDING_AUTO_CLOSE_MS;
    if (ageMs(now, base) <= ttl) continue;

    batch.set(
      doc.ref,
      {
        status: "auto_closed",
        autoClosedAt: admin.firestore.FieldValue.serverTimestamp(),
        autoClosedFromStatus: status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    closed += 1;
  }

  if (closed > 0) {
    await batch.commit();
  }

  return closed;
}

export const sweepMeetupAutoClose = functions.pubsub
  .schedule("every 15 minutes")
  .timeZone("UTC")
  .onRun(async () => {
    const now = new Date();

    const [requestedClosed, acceptedClosed, liveClosed] = await Promise.all([
      sweepStatus("requested", now),
      sweepStatus("accepted", now),
      sweepStatus("live", now),
    ]);

    const totalClosed = requestedClosed + acceptedClosed + liveClosed;

    await db.collection("dashboard").doc("meetupAutoCloseSweep").set(
      {
        lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
        requestedClosed,
        acceptedClosed,
        liveClosed,
        totalClosed,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    functions.logger.info("sweepMeetupAutoClose completed", {
      requestedClosed,
      acceptedClosed,
      liveClosed,
      totalClosed,
    });

    return null;
  });
