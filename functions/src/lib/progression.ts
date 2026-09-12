import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

const LEVEL_THRESHOLDS = [0, 15, 35, 60, 90, 130, 180, 240, 315, 400];

type UnlockPolicy = {
  minLevel: number;
  minTotalPoints: number;
  minAccountAgeDays: number;
};

const UNLOCK_POLICIES: Record<string, UnlockPolicy> = {
  referrals: { minLevel: 2, minTotalPoints: 15, minAccountAgeDays: 1 },
  supportMode: { minLevel: 3, minTotalPoints: 30, minAccountAgeDays: 3 },
  treeMode: { minLevel: 3, minTotalPoints: 30, minAccountAgeDays: 3 },
  publicMode: { minLevel: 4, minTotalPoints: 50, minAccountAgeDays: 7 },
  supportTechnician: { minLevel: 5, minTotalPoints: 75, minAccountAgeDays: 14 },
  businessMode: { minLevel: 6, minTotalPoints: 100, minAccountAgeDays: 21 },
};

function levelFromTotalPoints(totalPoints: number): number {
  const points = Number.isFinite(totalPoints) ? Math.max(0, Math.floor(totalPoints)) : 0;

  for (let i = LEVEL_THRESHOLDS.length - 1; i >= 0; i--) {
    if (points >= LEVEL_THRESHOLDS[i]) {
      return i + 1;
    }
  }
  return 1;
}

function readNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return fallback;
}

function toAccountAgeDays(joinedAt: unknown, now: Date): number {
  if (!(joinedAt instanceof admin.firestore.Timestamp)) return 0;
  const diffMs = now.getTime() - joinedAt.toDate().getTime();
  if (!Number.isFinite(diffMs) || diffMs <= 0) return 0;
  return Math.max(0, Math.floor(diffMs / (24 * 60 * 60 * 1000)));
}

export const onPointsProgressionWrite = onDocumentWritten(
  "users/{uid}/meta/points",
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const uid = String(event.params.uid ?? "").trim();
    if (!uid) return;

    const pointsData = after.data() ?? {};
    const totalPoints = Math.max(0, Math.floor(readNumber(pointsData.totalPoints, 0)));
    const level = levelFromTotalPoints(totalPoints);

    const db = admin.firestore();
    const userSnap = await db.doc(`users/${uid}`).get();
    if (!userSnap.exists || (await db.doc(`accountDeletions/${uid}`).get()).exists) return;
    const userData = userSnap.data() ?? {};

    const now = new Date();
    const accountAgeDays = toAccountAgeDays(userData.joinedAt, now);

    const unlocks: Record<string, boolean> = {};
    for (const [feature, req] of Object.entries(UNLOCK_POLICIES)) {
      unlocks[feature] =
        level >= req.minLevel &&
        totalPoints >= req.minTotalPoints &&
        accountAgeDays >= req.minAccountAgeDays;
    }

    const progressionRef = db.doc(`users/${uid}/meta/progression`);
    const progressionSnap = await progressionRef.get();
    const previousLevel = readNumber(progressionSnap.data()?.level, 1);

    const payload: Record<string, unknown> = {
      level,
      totalPoints,
      accountAgeDays,
      unlocks,
      unlockedFeatures: Object.entries(unlocks)
        .filter(([, enabled]) => enabled)
        .map(([feature]) => feature),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (level > previousLevel) {
      payload.lastLevelUpAt = admin.firestore.FieldValue.serverTimestamp();
      payload.lastLevelDelta = level - previousLevel;
    }

    await progressionRef.set(payload, { merge: true });
  },
);
