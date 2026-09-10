import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

type Status = "" | "requested" | "accepted" | "declined" | "expired" | "live" | "completed" | "auto_closed";

function asMap(v: unknown): Record<string, unknown> {
  if (v && typeof v === "object") return v as Record<string, unknown>;
  return {};
}

function normalizeStatus(v: unknown): Status {
  const s = String(v ?? "").trim().toLowerCase();
  if (
    s === "requested" ||
    s === "accepted" ||
    s === "declined" ||
    s === "expired" ||
    s === "live" ||
    s === "completed" ||
    s === "auto_closed"
  ) {
    return s;
  }
  return "";
}

function allowChatGateTransition(fromStatus: Status, toStatus: Status): boolean {
  if (fromStatus === toStatus) return true;
  if (fromStatus === "" && toStatus === "requested") return true;
  if (fromStatus === "requested" && (toStatus === "accepted" || toStatus === "declined" || toStatus === "expired")) {
    return true;
  }
  if (fromStatus === "accepted" && toStatus === "expired") return true;
  return false;
}

function allowMeetupTransition(fromStatus: Status, toStatus: Status): boolean {
  if (fromStatus === toStatus) return true;

  // Creation paths used in current app flows.
  if (fromStatus === "" && (toStatus === "requested" || toStatus === "live")) return true;

  // Allow fresh meetup cycles in an existing chat after terminal/request-end states.
  if (
    (fromStatus === "declined" ||
      fromStatus === "expired" ||
      fromStatus === "auto_closed" ||
      fromStatus === "completed") &&
    toStatus === "requested"
  ) {
    return true;
  }

  if (fromStatus === "requested" && (toStatus === "accepted" || toStatus === "declined" || toStatus === "expired" || toStatus === "live" || toStatus === "auto_closed")) {
    return true;
  }

  if (fromStatus === "accepted" && (toStatus === "live" || toStatus === "completed" || toStatus === "expired" || toStatus === "auto_closed")) {
    return true;
  }

  if (fromStatus === "live" && (toStatus === "completed" || toStatus === "expired" || toStatus === "auto_closed")) {
    return true;
  }

  return false;
}

function isRollbackEcho(
  policy: Record<string, unknown>,
  fromStatus: Status,
  toStatus: Status,
): boolean {
  const rollbackFrom = normalizeStatus(policy["rollbackFromStatus"]);
  const rollbackTo = normalizeStatus(policy["rollbackToStatus"]);
  return rollbackFrom === fromStatus && rollbackTo === toStatus;
}

const TERMINAL_MEETUP_STATUSES = new Set<string>([
  "completed",
  "cancelled",
  "expired",
  "declined",
  "auto_closed",
  "purged",
]);

function participantUidSet(data: Record<string, unknown>): Set<string> {
  const out = new Set<string>();
  const a = typeof data.aUid === "string" ? data.aUid.trim() : "";
  const b = typeof data.bUid === "string" ? data.bUid.trim() : "";
  if (a) out.add(a);
  if (b) out.add(b);
  return out;
}

function statusFromData(data: Record<string, unknown>): string {
  return String(data.status ?? "").trim().toLowerCase();
}

function tsMs(v: unknown): number {
  if (v && typeof v === "object" && "toMillis" in (v as object)) {
    try {
      return Number((v as FirebaseFirestore.Timestamp).toMillis()) || 0;
    } catch {
      return 0;
    }
  }
  return 0;
}

function meetupOrderMs(data: Record<string, unknown>): number {
  return (
    tsMs(data.updatedAt) ||
    tsMs(data.completedAt) ||
    tsMs(data.acceptedAt) ||
    tsMs(data.requestedAt) ||
    0
  );
}

async function recomputeInteractionLockForUser(uid: string): Promise<void> {
  const safeUid = uid.trim();
  if (!safeUid) return;

  const [asA, asB] = await Promise.all([
    admin.firestore().collection("meetups").where("aUid", "==", safeUid).limit(200).get(),
    admin.firestore().collection("meetups").where("bUid", "==", safeUid).limit(200).get(),
  ]);

  let activeMeetupId = "";
  let activeMeetupOtherUid = "";
  let bestTs = -1;

  const merged = new Map<string, Record<string, unknown>>();
  for (const d of asA.docs) merged.set(d.id, d.data() as Record<string, unknown>);
  for (const d of asB.docs) merged.set(d.id, d.data() as Record<string, unknown>);

  for (const [meetupId, data] of merged.entries()) {
    const status = statusFromData(data);
    if (TERMINAL_MEETUP_STATUSES.has(status)) continue;

    const orderMs = meetupOrderMs(data);
    if (orderMs < bestTs) continue;

    const aUid = typeof data.aUid === "string" ? data.aUid.trim() : "";
    const bUid = typeof data.bUid === "string" ? data.bUid.trim() : "";
    const other = aUid === safeUid ? bUid : bUid === safeUid ? aUid : "";

    bestTs = orderMs;
    activeMeetupId = meetupId;
    activeMeetupOtherUid = other;
  }

  const busy = activeMeetupId !== "";
  const statusTag = busy ? "In active meetup" : "";

  await Promise.all([
    admin.firestore().collection("users").doc(safeUid).set(
      {
        interactionLock: {
          busyInMeetup: busy,
          activeMeetupId: busy ? activeMeetupId : "",
          activeMeetupOtherUid: busy ? activeMeetupOtherUid : "",
          statusTag,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true },
    ),
    admin.firestore().collection("users").doc(safeUid).collection("presence").doc("current").set(
      {
        busyInMeetup: busy,
        interactionStatusTag: statusTag,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    ),
  ]);
}

export const onChatGateTransitionGuard = functions.firestore
  .document("chats/{chatId}")
  .onWrite(async (change, context) => {
    if (!change.before.exists || !change.after.exists) return;

    const before = asMap(change.before.data());
    const after = asMap(change.after.data());

    const beforeGate = asMap(before["chatGate"]);
    const afterGate = asMap(after["chatGate"]);

    const fromStatus = normalizeStatus(beforeGate["status"]);
    const toStatus = normalizeStatus(afterGate["status"]);

    if (fromStatus === toStatus) return;
    if (allowChatGateTransition(fromStatus, toStatus)) return;

    const policy = asMap(after["chatGatePolicy"]);
    if (isRollbackEcho(policy, fromStatus, toStatus)) return;

    const chatId = String(context.params.chatId ?? "");
    functions.logger.warn("[match_dashboard_enforcement] invalid chatGate transition", {
      chatId,
      fromStatus,
      toStatus,
    });

    await change.after.ref.set(
      {
        chatGate: {
          status: fromStatus,
          rolledBackByPolicy: true,
          rolledBackAt: admin.firestore.FieldValue.serverTimestamp(),
          rollbackReason: "invalid_chat_gate_transition",
        },
        chatGatePolicy: {
          rollbackFromStatus: toStatus,
          rollbackToStatus: fromStatus,
          rollbackAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

export const onMeetupTransitionGuard = functions.firestore
  .document("meetups/{meetupId}")
  .onWrite(async (change, context) => {
    if (!change.before.exists || !change.after.exists) return;

    const before = asMap(change.before.data());
    const after = asMap(change.after.data());

    const fromStatus = normalizeStatus(before["status"]);
    const toStatus = normalizeStatus(after["status"]);

    if (fromStatus === toStatus) return;
    if (allowMeetupTransition(fromStatus, toStatus)) return;

    const policy = asMap(after["statusPolicy"]);
    if (isRollbackEcho(policy, fromStatus, toStatus)) return;

    const meetupId = String(context.params.meetupId ?? "");
    functions.logger.warn("[match_dashboard_enforcement] invalid meetup transition", {
      meetupId,
      fromStatus,
      toStatus,
    });

    await change.after.ref.set(
      {
        status: fromStatus,
        statusPolicy: {
          rolledBackByPolicy: true,
          rollbackReason: "invalid_meetup_transition",
          rollbackFromStatus: toStatus,
          rollbackToStatus: fromStatus,
          rollbackAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

export const onMeetupInteractionLockProjection = functions.firestore
  .document("meetups/{meetupId}")
  .onWrite(async (change) => {
    const uids = new Set<string>();

    if (change.before.exists) {
      for (const uid of participantUidSet(asMap(change.before.data()))) {
        uids.add(uid);
      }
    }

    if (change.after.exists) {
      for (const uid of participantUidSet(asMap(change.after.data()))) {
        uids.add(uid);
      }
    }

    if (uids.size === 0) return;

    await Promise.all(
      Array.from(uids).map((uid) => recomputeInteractionLockForUser(uid)),
    );
  });
