import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

type PolicyDoc = {
  lockUntilEpochMs?: number;
  activePenaltyCount?: number;
  pendingByUid?: Record<string, number>;
};

const SWEEP_BATCH_SIZE = 300;

export type ActiveModeSweepSummary = {
  nowMs: number;
  scanned: number;
  swept: number;
  errors: number;
  source: string;
  requestedByUid?: string;
};

function matchParticipants(data: FirebaseFirestore.DocumentData): string[] {
  if (Array.isArray(data.participants)) {
    return data.participants.map((x: unknown) => String(x)).filter(Boolean);
  }
  if (Array.isArray(data.userIds)) {
    return data.userIds.map((x: unknown) => String(x)).filter(Boolean);
  }
  const a = typeof data.aUid === "string" ? data.aUid : "";
  const b = typeof data.bUid === "string" ? data.bUid : "";
  return [a, b].filter(Boolean);
}

async function isNormalActive(uid: string): Promise<boolean> {
  try {
    const snap = await db.collection("users").doc(uid).collection("settings").doc("matching").get();
    const d = snap.data() || {};
    return d.modeKind === "normal" && d.normalMode === "active";
  } catch {
    return false;
  }
}

function sanitizePending(raw: unknown): Record<string, number> {
  if (!raw || typeof raw !== "object") return {};
  const out: Record<string, number> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (!k || typeof k !== "string") continue;
    if (typeof v === "number" && Number.isFinite(v) && v > 0) {
      out[k] = Math.trunc(v);
    }
  }
  return out;
}

function evaluatePending(policy: PolicyDoc, nowMs: number): {
  remaining: Record<string, number>;
  hadOverdue: boolean;
} {
  const pending = sanitizePending(policy.pendingByUid);
  const remaining: Record<string, number> = {};
  let hadOverdue = false;

  for (const [otherUid, dueMs] of Object.entries(pending)) {
    if (dueMs <= nowMs) {
      hadOverdue = true;
      continue;
    }
    remaining[otherUid] = dueMs;
  }

  return { remaining, hadOverdue };
}

async function upsertPolicyForMatch({ uid, otherUid, nowMs }: { uid: string; otherUid: string; nowMs: number }) {
  const active = await isNormalActive(uid);
  if (!active) return;

  const ref = db.collection("users").doc(uid).collection("meta").doc("matching");
  await db.runTransaction(async (tx) => {
    const [snap, deletion] = await tx.getAll(ref, db.doc(`accountDeletions/${uid}`));
    if (deletion.exists) return;
    const current = (snap.data() || {}) as PolicyDoc;
    const { remaining, hadOverdue } = evaluatePending(current, nowMs);

    remaining[otherUid] = nowMs + 10 * 60 * 1000;

    let lockUntilEpochMs = typeof current.lockUntilEpochMs === "number" ? current.lockUntilEpochMs : 0;
    let activePenaltyCount = typeof current.activePenaltyCount === "number" ? current.activePenaltyCount : 0;

    if (hadOverdue) {
      lockUntilEpochMs = Math.max(lockUntilEpochMs, nowMs + 10 * 60 * 1000);
      activePenaltyCount += 1;
    }

    tx.set(
      ref,
      {
        pendingByUid: remaining,
        lockUntilEpochMs,
        activePenaltyCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtClientMs: nowMs,
      },
      { merge: true },
    );
  });
}

async function resolvePolicyForMessage({ uid, otherUids, nowMs }: { uid: string; otherUids: string[]; nowMs: number }) {
  const ref = db.collection("users").doc(uid).collection("meta").doc("matching");
  await db.runTransaction(async (tx) => {
    const [snap, deletion] = await tx.getAll(ref, db.doc(`accountDeletions/${uid}`));
    if (deletion.exists) return;
    if (!snap.exists) return;

    const current = (snap.data() || {}) as PolicyDoc;
    const { remaining: activePending, hadOverdue } = evaluatePending(current, nowMs);

    const otherSet = new Set(otherUids.filter(Boolean));
    for (const key of Object.keys(activePending)) {
      if (otherSet.has(key)) {
        delete activePending[key];
      }
    }

    let lockUntilEpochMs = typeof current.lockUntilEpochMs === "number" ? current.lockUntilEpochMs : 0;
    let activePenaltyCount = typeof current.activePenaltyCount === "number" ? current.activePenaltyCount : 0;

    if (hadOverdue) {
      lockUntilEpochMs = Math.max(lockUntilEpochMs, nowMs + 10 * 60 * 1000);
      activePenaltyCount += 1;
    }

    tx.set(
      ref,
      {
        pendingByUid: activePending,
        lockUntilEpochMs,
        activePenaltyCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtClientMs: nowMs,
      },
      { merge: true },
    );
  });
}

async function sweepPolicyRef(ref: FirebaseFirestore.DocumentReference, nowMs: number): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const [snap, deletion] = await tx.getAll(ref, db.doc(`accountDeletions/${ref.parent.parent!.id}`));
    if (deletion.exists) return false;
    if (!snap.exists) return false;

    const current = (snap.data() || {}) as PolicyDoc;
    const { remaining, hadOverdue } = evaluatePending(current, nowMs);
    if (!hadOverdue) return false;

    let lockUntilEpochMs = typeof current.lockUntilEpochMs === "number" ? current.lockUntilEpochMs : 0;
    let activePenaltyCount = typeof current.activePenaltyCount === "number" ? current.activePenaltyCount : 0;

    lockUntilEpochMs = Math.max(lockUntilEpochMs, nowMs + 10 * 60 * 1000);
    activePenaltyCount += 1;

    tx.set(
      ref,
      {
        pendingByUid: remaining,
        lockUntilEpochMs,
        activePenaltyCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAtClientMs: nowMs,
      },
      { merge: true },
    );

    return true;
  });
}

export const sweepActiveModePolicies = functions.pubsub
  .schedule("every 10 minutes")
  .timeZone("UTC")
  .onRun(async () => {
    const summary = await runActiveModePolicySweep({ source: "schedule" });

    functions.logger.info("sweepActiveModePolicies completed", summary);
    return null;
  });

export async function runActiveModePolicySweep(opts?: {
  source?: string;
  requestedByUid?: string;
}): Promise<ActiveModeSweepSummary> {
    const nowMs = Date.now();
    let scanned = 0;
    let swept = 0;
    let errors = 0;
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    const source = opts?.source || "manual";
    const requestedByUid = opts?.requestedByUid;

    for (;;) {
      let query: FirebaseFirestore.Query = db.collectionGroup("meta").limit(SWEEP_BATCH_SIZE);
      if (cursor) {
        query = query.startAfter(cursor);
      }

      const page = await query.get();
      if (page.empty) break;

      for (const docSnap of page.docs) {
        scanned += 1;

        // Filter to users/{uid}/meta/matching and ignore users/{uid}/settings/matching.
        if (docSnap.id !== "matching" || docSnap.ref.parent.parent?.parent.id !== "users") continue;

        const data = (docSnap.data() || {}) as PolicyDoc;
        const pending = sanitizePending(data.pendingByUid);
        if (Object.keys(pending).length === 0) continue;

        try {
          if (await sweepPolicyRef(docSnap.ref, nowMs)) {
            swept += 1;
          }
        } catch (err) {
          errors += 1;
          functions.logger.warn("sweepActiveModePolicies item failed", {
            path: docSnap.ref.path,
            nowMs,
            err,
          });
        }
      }

      cursor = page.docs[page.docs.length - 1];
      if (page.size < SWEEP_BATCH_SIZE) break;
    }

    const payload: Record<string, unknown> = {
      lastRunAt: admin.firestore.FieldValue.serverTimestamp(),
      lastRunMs: nowMs,
      lastScanned: scanned,
      lastSwept: swept,
      lastErrors: errors,
      lastSource: source,
      totalRuns: admin.firestore.FieldValue.increment(1),
      totalScanned: admin.firestore.FieldValue.increment(scanned),
      totalSwept: admin.firestore.FieldValue.increment(swept),
      totalErrors: admin.firestore.FieldValue.increment(errors),
    };
    if (requestedByUid) {
      payload.lastRequestedByUid = requestedByUid;
    }

    await db.collection("dashboard").doc("activeModePolicySweep").set(payload, { merge: true });

    return {
      nowMs,
      scanned,
      swept,
      errors,
      source,
      requestedByUid,
    };
}

export const onMatchPolicySeed = functions.firestore
  .document("matches/{matchId}")
  .onCreate(async (snap) => {
    const data = snap.data() || {};
    const users = Array.from(new Set(matchParticipants(data)));
    if (users.length < 2) return;

    const nowMs = Date.now();
    await Promise.all(
      users.map(async (uid) => {
        const others = users.filter((u) => u !== uid);
        for (const otherUid of others) {
          await upsertPolicyForMatch({ uid, otherUid, nowMs });
        }
      }),
    );
  });

export const onMessagePolicyResolve = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const chatId = context.params.chatId as string;
    const msg = snap.data() || {};
    const senderUid = typeof msg.from === "string" ? msg.from : "";
    if (!senderUid) return;

    const chatSnap = await db.collection("chats").doc(chatId).get();
    if (!chatSnap.exists) return;

    const chat = chatSnap.data() || {};
    const participants = Array.isArray(chat.participants)
      ? chat.participants.map((x: unknown) => String(x)).filter(Boolean)
      : [];

    const others = participants.filter((uid: string) => uid && uid !== senderUid);
    if (others.length === 0) return;

    await resolvePolicyForMessage({ uid: senderUid, otherUids: others, nowMs: Date.now() });
  });
