import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

type Status = "" | "requested" | "accepted" | "declined" | "expired" | "live" | "completed" | "auto_closed" | "cancelled";

const STRICT_STEP_RANK: Record<string, number> = {
  requested_waiting_accept: 0,
  accepted_choose_location: 1,
  confirm_location: 2,
  travel_to_meetup: 3,
  waiting_partner_on_my_way: 4,
  verify_and_confirm_arrival: 5,
  waiting_partner_arrival: 6,
  completed: 7,
};

const STATUS_STEP_ALLOWLIST: Record<Status, Set<string>> = {
  "": new Set<string>(),
  requested: new Set<string>(["requested_waiting_accept"]),
  accepted: new Set<string>(["accepted_choose_location"]),
  declined: new Set<string>(),
  expired: new Set<string>(),
  live: new Set<string>([
    "confirm_location",
    "travel_to_meetup",
    "waiting_partner_on_my_way",
    "verify_and_confirm_arrival",
    "waiting_partner_arrival",
  ]),
  completed: new Set<string>(["completed"]),
  auto_closed: new Set<string>(),
  cancelled: new Set<string>(),
};

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
    s === "auto_closed" || s === "cancelled"
  ) {
    return s;
  }
  return "";
}

function normalizeStep(v: unknown): string {
  return String(v ?? "").trim().toLowerCase();
}

function isStrictStep(v: string): boolean {
  return v in STRICT_STEP_RANK;
}

function hasStrictProgressSignals(data: Record<string, unknown>): boolean {
  const step = normalizeStep(data.currentStep);
  const hasStep = step !== "";
  const hasDeadline = tsMs(data.stepDeadlineAt) > 0;
  return hasStep || hasDeadline;
}

function sameStepOrForwardByOne(fromStep: string, toStep: string): boolean {
  if (!isStrictStep(fromStep) || !isStrictStep(toStep)) return true;
  const delta = STRICT_STEP_RANK[toStep] - STRICT_STEP_RANK[fromStep];
  return delta >= 0 && delta <= 1;
}

function stepAllowedForStatus(status: Status, step: string): boolean {
  if (!step) return true;
  const allowed = STATUS_STEP_ALLOWLIST[status];
  if (!allowed || allowed.size === 0) return true;
  if (!isStrictStep(step)) return true;
  return allowed.has(step);
}

function participantSet(data: Record<string, unknown>): Set<string> {
  const out = new Set<string>();
  const aUid = typeof data.aUid === "string" ? data.aUid.trim() : "";
  const bUid = typeof data.bUid === "string" ? data.bUid.trim() : "";
  if (aUid) out.add(aUid);
  if (bUid) out.add(bUid);
  return out;
}

function hasValidActorCancelEvidence(v: unknown): boolean {
  if (typeof v === "string") return v.trim() !== "";
  if (typeof v === "number") return Number.isFinite(v) && v > 0;
  if (!v || typeof v !== "object") return false;

  const evidence = v as Record<string, unknown>;
  const requestId = typeof evidence.requestId === "string" ? evidence.requestId.trim() : "";
  if (requestId) return true;

  return (
    tsMs(evidence.requestedAt) > 0 ||
    tsMs(evidence.confirmedAt) > 0 ||
    tsMs(evidence.ts) > 0 ||
    tsMs(evidence.at) > 0
  );
}

function cancelHandshakeEvidenceByUid(data: Record<string, unknown>): Record<string, unknown> {
  const direct = asMap(data.cancelHandshakeByUid);
  const legacy = asMap(data.cancelHandshake);
  const legacyByUid = asMap(legacy.byUid);
  const legacyParticipants = asMap(legacy.participants);
  return {
    ...legacyParticipants,
    ...legacyByUid,
    ...legacy,
    ...direct,
  };
}

function mutualCancelAgreed(data: Record<string, unknown>): boolean {
  const participants = participantSet(data);
  if (participants.size < 2) return false;

  const evidenceByUid = cancelHandshakeEvidenceByUid(data);
  for (const uid of participants) {
    if (!hasValidActorCancelEvidence(evidenceByUid[uid])) return false;
  }
  return true;
}

function isLegacySafetyCancellation(after: Record<string, unknown>): boolean {
  return normalizeStatus(after.outcome) === "cancelled" &&
    (tsMs(after.cancelledAt) > 0 || tsMs(after.closedAt) > 0);
}

function completedArrivalRequirementMet(after: Record<string, unknown>): boolean {
  return after.aArrived === true && after.bArrived === true;
}

function strictProgressionAllowed(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
  fromStatus: Status,
  toStatus: Status,
): boolean {
  const fromStep = normalizeStep(before.currentStep);
  const toStep = normalizeStep(after.currentStep);

  if (!stepAllowedForStatus(fromStatus, fromStep)) return false;
  if (!stepAllowedForStatus(toStatus, toStep)) return false;

  // Once strict step metadata is present, block skip-ahead status jumps.
  const strictFlow = hasStrictProgressSignals(before) || hasStrictProgressSignals(after);
  if (strictFlow && fromStatus === "requested" && toStatus === "live") return false;
  if (strictFlow && fromStatus === "accepted" && toStatus === "completed") return false;

  if (fromStatus === toStatus && fromStep !== "" && toStep !== "" && !sameStepOrForwardByOne(fromStep, toStep)) {
    return false;
  }

  return true;
}

function allowChatGateTransition(fromStatus: Status, toStatus: Status): boolean {
  if (fromStatus === toStatus) return true;
  if (toStatus === "expired") return true;
  if (fromStatus === "" && toStatus === "requested") return true;
  if (fromStatus === "requested" && (toStatus === "accepted" || toStatus === "declined")) {
    return true;
  }
  return false;
}

/** Mode-specific deadlines and deliberate renewal of timed-out, unclosed requests. */
export function chatGateTransitionAllowed(before: Record<string, any>, after: Record<string, any>, now = Date.now()): boolean {
  const old = before.chatGate || {};
  const next = after.chatGate || {};
  const from = normalizeStatus(old.status);
  const to = normalizeStatus(next.status);
  const requested = old.requestedAt instanceof admin.firestore.Timestamp ? old.requestedAt.toMillis() : 0;
  const seconds = old.modeKind === 'normal' && old.responseWindowSeconds === 60 ? 60 : 86400;
  if (from === 'expired' && to === 'requested') {
    const renewed = next.requestedAt instanceof admin.firestore.Timestamp ? next.requestedAt.toMillis() : 0;
    return !before.closedAt && !after.closedAt && old.expiredBySystem === true &&
      !old.acceptedAt && !old.declinedAt && !old.acceptedBy && !old.declinedBy &&
      renewed > requested && Array.isArray(after.participants) && after.participants.length === 2 &&
      after.participants.includes(next.requestedBy) && JSON.stringify(before.participants) === JSON.stringify(after.participants);
  }
  if (from === 'requested' && to === 'expired' && !after.closedAt) return requested > 0 && now >= requested + seconds * 1000;
  if (from === 'requested' && ['accepted', 'declined'].includes(to) && requested > 0 && now >= requested + seconds * 1000) return false;
  return allowChatGateTransition(from, to);
}

function allowMeetupTransition(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
  fromStatus: Status,
  toStatus: Status,
): boolean {
  if (!strictProgressionAllowed(before, after, fromStatus, toStatus)) return false;

  if (fromStatus === toStatus) return true;
  if (["requested", "accepted", "live"].includes(fromStatus) && toStatus === "cancelled") {
    // Incremental rollout: allow legacy safety cancellation while enforcing
    // mutual handshake for strict cancel-by-request flows.
    return mutualCancelAgreed(after) || isLegacySafetyCancellation(after);
  }

  // Creation paths used in current app flows.
  if (fromStatus === "" && (toStatus === "requested" || toStatus === "live")) return true;

  // Allow fresh meetup cycles in an existing chat after terminal/request-end states.
  if (
    (fromStatus === "cancelled" || fromStatus === "declined" ||
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
    if (toStatus === "completed") return completedArrivalRequirementMet(after);
    return true;
  }

  if (fromStatus === "live" && (toStatus === "completed" || toStatus === "expired" || toStatus === "auto_closed")) {
    if (toStatus === "completed") return completedArrivalRequirementMet(after);
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

  await admin.firestore().runTransaction(async tx => {
    const userRef = admin.firestore().collection("users").doc(safeUid);
    const [user, deletion] = await tx.getAll(userRef,
      admin.firestore().collection("accountDeletions").doc(safeUid));
    if (!user.exists || deletion.exists) return;
    tx.set(userRef,
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
    );
    tx.set(userRef.collection("presence").doc("current"),
      {
        busyInMeetup: busy,
        interactionStatusTag: statusTag,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
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
    if (chatGateTransitionAllowed(before, after, change.after.updateTime?.toMillis())) return;

    const policy = asMap(after["chatGatePolicy"]);
    if (isRollbackEcho(policy, fromStatus, toStatus)) return;

    const chatId = String(context.params.chatId ?? "");
    functions.logger.warn("[match_dashboard_enforcement] invalid chatGate transition", {
      chatId,
      fromStatus,
      toStatus,
    });

    await admin.firestore().runTransaction(async tx => {
      const current = await tx.get(change.after.ref);
      if (!current.updateTime?.isEqual(change.after.updateTime!)) return;
      tx.set(change.after.ref,
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
  });

export const onMeetupTransitionGuard = functions.firestore
  .document("meetups/{meetupId}")
  .onWrite(async (change, context) => {
    if (!change.before.exists || !change.after.exists) return;

    const before = asMap(change.before.data());
    const after = asMap(change.after.data());

    const fromStatus = normalizeStatus(before["status"]);
    const toStatus = normalizeStatus(after["status"]);

    if (allowMeetupTransition(before, after, fromStatus, toStatus)) {
      if (fromStatus === toStatus) return;
      return;
    }

    const policy = asMap(after["statusPolicy"]);
    if (isRollbackEcho(policy, fromStatus, toStatus)) return;

    const meetupId = String(context.params.meetupId ?? "");
    functions.logger.warn("[match_dashboard_enforcement] invalid meetup transition", {
      meetupId,
      fromStatus,
      toStatus,
    });

    await admin.firestore().runTransaction(async tx => {
      const current = await tx.get(change.after.ref);
      if (!current.updateTime?.isEqual(change.after.updateTime!)) return;
      const rollbackFields: Record<string, unknown> = {
        status: fromStatus,
        statusPolicy: {
          rolledBackByPolicy: true,
          rollbackReason: "invalid_meetup_transition",
          rollbackFromStatus: toStatus,
          rollbackToStatus: fromStatus,
          rollbackAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (Object.prototype.hasOwnProperty.call(before, "currentStep")) {
        rollbackFields.currentStep = before.currentStep;
      }
      if (Object.prototype.hasOwnProperty.call(before, "stepDeadlineAt")) {
        rollbackFields.stepDeadlineAt = before.stepDeadlineAt;
      }
      tx.set(change.after.ref,
      rollbackFields,
      { merge: true },
    );
    });
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
