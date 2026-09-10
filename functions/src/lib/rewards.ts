import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

const SUPPORT_CONFIRMED_STATUS = 3;
const SUPPORT_PAYOUT_POINTS = 1;
const REFERRAL_MILESTONE_POINTS = 5;
const MUTUAL_BRIDGE_POINTS = 1;

function tsNow() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function parseStatus(value: unknown): number {
  return typeof value === "number" ? value : Number(value ?? 0);
}

function isTrue(value: unknown): boolean {
  return value === true;
}

function parseBridgeSource(source: unknown): { chatId: string; ownerUid: string } | null {
  const raw = String(source ?? "").trim();
  if (!raw.startsWith("mutualPartyBridge:")) return null;
  const parts = raw.split(":");
  if (parts.length < 3) return null;
  const chatId = String(parts[1] ?? "").trim();
  const ownerUid = String(parts[2] ?? "").trim();
  if (!chatId || !ownerUid) return null;
  return { chatId, ownerUid };
}

function stablePairKey(a: string, b: string): string {
  return [a, b].map((x) => x.trim()).sort().join("__");
}

export const onSupportTicketReward = onDocumentWritten(
  "support_tickets/{ticketId}",
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const data = after.data() ?? {};
    if (!isTrue(data.payoutGranted) || isTrue(data.payoutCredited)) return;

    const technicianId = String(data.technicianId ?? "").trim();
    if (!technicianId) return;

    const status = parseStatus(data.status);
    const thumbsUp = isTrue(data.thumbsUp);
    const doneDealConfirmed = isTrue(data.doneDealConfirmed);
    if (status !== SUPPORT_CONFIRMED_STATUS || !thumbsUp || !doneDealConfirmed) return;

    const db = admin.firestore();
    const ticketRef = after.ref;
    const pointsRef = db.doc(`users/${technicianId}/meta/points`);
    const profileRef = db.doc(`technician_profiles/${technicianId}`);

    await db.runTransaction(async (tx) => {
      const [freshTicket, deletion] = await tx.getAll(ticketRef, db.doc(`accountDeletions/${technicianId}`));
      if (!freshTicket.exists || deletion.exists) return;
      const freshData = freshTicket.data() ?? {};
      if (!isTrue(freshData.payoutGranted) || isTrue(freshData.payoutCredited) || freshData.technicianId !== technicianId || parseStatus(freshData.status) !== SUPPORT_CONFIRMED_STATUS || !isTrue(freshData.doneDealConfirmed) || !isTrue(freshData.thumbsUp)) return;

      tx.set(
        pointsRef,
        {
          totalPoints: admin.firestore.FieldValue.increment(SUPPORT_PAYOUT_POINTS),
          currentPoints: admin.firestore.FieldValue.increment(SUPPORT_PAYOUT_POINTS),
          supportSessions: admin.firestore.FieldValue.increment(1),
          lastActivity: tsNow(),
          updatedAt: tsNow(),
        },
        { merge: true },
      );

      tx.set(
        profileRef,
        {
          ticketsResolved: admin.firestore.FieldValue.increment(1),
          ticketsThumbsUp: admin.firestore.FieldValue.increment(1),
          updatedAt: tsNow(),
        },
        { merge: true },
      );

      tx.set(
        ticketRef,
        {
          payoutCredited: true,
          payoutCreditedAt: tsNow(),
          updatedAt: tsNow(),
        },
        { merge: true },
      );
    });

    logger.info("Support reward credited", {
      ticketId: after.id,
      technicianId,
      points: SUPPORT_PAYOUT_POINTS,
    });
  },
);

export const onReferralMilestoneReward = onDocumentWritten(
  "users/{referrerUid}/referrals/{inviteeUid}",
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const data = after.data() ?? {};
    if (!isTrue(data.rewardGranted) || isTrue(data.rewardCredited)) return;

    const referrerUid = String(event.params.referrerUid ?? "").trim();
    if (!referrerUid) return;

    const db = admin.firestore();
    const referralRef = after.ref;
    const pointsRef = db.doc(`users/${referrerUid}/meta/points`);

    await db.runTransaction(async (tx) => {
      const [freshReferral, deletion] = await tx.getAll(referralRef, db.doc(`accountDeletions/${referrerUid}`));
      if (!freshReferral.exists || deletion.exists) return;
      const freshData = freshReferral.data() ?? {};
      if (!isTrue(freshData.rewardGranted) || isTrue(freshData.rewardCredited) || !isTrue(freshData.inPersonVerified) || !isTrue(freshData.rewardEligible) || Number(freshData.meetupsCompleted || 0) < 5) return;

      tx.set(
        pointsRef,
        {
          totalPoints: admin.firestore.FieldValue.increment(REFERRAL_MILESTONE_POINTS),
          currentPoints: admin.firestore.FieldValue.increment(REFERRAL_MILESTONE_POINTS),
          referrals: admin.firestore.FieldValue.increment(1),
          lastActivity: tsNow(),
          updatedAt: tsNow(),
        },
        { merge: true },
      );

      tx.set(
        referralRef,
        {
          rewardCredited: true,
          rewardCreditedAt: tsNow(),
          updatedAt: tsNow(),
        },
        { merge: true },
      );
    });

    logger.info("Referral milestone reward credited", {
      referralDocId: after.id,
      referrerUid,
      points: REFERRAL_MILESTONE_POINTS,
    });
  },
);

export const onMutualPartyBridgeReward = onDocumentWritten(
  "users/{uid}/party/{otherUid}",
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const uid = String(event.params.uid ?? "").trim();
    const otherUid = String(event.params.otherUid ?? "").trim();
    if (!uid || !otherUid) return;

    const data = after.data() ?? {};
    if (!isTrue(data.mutual)) return;

    const source = parseBridgeSource(data.source);
    if (!source) return;

    const { chatId, ownerUid } = source;
    if (!chatId || !ownerUid) return;
    if (ownerUid === uid || ownerUid === otherUid) return;

    const db = admin.firestore();
    const pairKey = stablePairKey(uid, otherUid);
    const rewardRef = db.doc(`chats/${chatId}/bridgeRewards/${pairKey}`);
    const chatRef = db.doc(`chats/${chatId}`);
    const ownerPointsRef = db.doc(`users/${ownerUid}/meta/points`);

    await db.runTransaction(async (tx) => {
      const lifetimeReward = db.doc(`users/${ownerUid}/rewardClaims/bridge_${pairKey}`);
      const [existingReward, lifetime, deletion] = await tx.getAll(rewardRef, lifetimeReward, db.doc(`accountDeletions/${ownerUid}`));
      if (existingReward.exists || lifetime.exists || deletion.exists) return;

      const reciprocal = await tx.get(db.doc(`users/${otherUid}/party/${uid}`));
      if (!reciprocal.exists || reciprocal.data()?.mutual !== true) return;
      const chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) return;
      const chat = chatSnap.data() ?? {};
      const chatOwner = String(chat.ownerUid ?? chat.moderatorUid ?? "").trim();
      if (!chatOwner || chatOwner !== ownerUid) return;

      const participants = Array.isArray(chat.participants)
        ? chat.participants.map((x: unknown) => String(x || "").trim()).filter(Boolean)
        : [];
      if (!participants.includes(uid) || !participants.includes(otherUid)) return;

      tx.create(lifetimeReward, {category: 'mutual_party_bridge', pairKey, chatId, points: MUTUAL_BRIDGE_POINTS, createdAt: tsNow()});

      tx.set(
        ownerPointsRef,
        {
          totalPoints: admin.firestore.FieldValue.increment(MUTUAL_BRIDGE_POINTS),
          currentPoints: admin.firestore.FieldValue.increment(MUTUAL_BRIDGE_POINTS),
          trustBridges: admin.firestore.FieldValue.increment(1),
          lastActivity: tsNow(),
          updatedAt: tsNow(),
        },
        { merge: true },
      );

      tx.set(
        rewardRef,
        {
          chatId,
          ownerUid,
          uid,
          otherUid,
          pairKey,
          points: MUTUAL_BRIDGE_POINTS,
          createdAt: tsNow(),
          updatedAt: tsNow(),
        },
        { merge: true },
      );
    });

    logger.info("Mutual party bridge reward evaluated", {
      chatId,
      ownerUid,
      uid,
      otherUid,
      points: MUTUAL_BRIDGE_POINTS,
    });
  },
);
