import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const SUPPORT_PAYOUT_POINTS_FALLBACK = 1;
const REFERRAL_PAYOUT_POINTS_FALLBACK = 5;

function toTimestamp(value: unknown): FirebaseFirestore.Timestamp | null {
  return value instanceof admin.firestore.Timestamp ? value : null;
}

function toNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return fallback;
}

function normalizeKeyword(raw: unknown): string {
  if (typeof raw !== "string") return "";
  const cleaned = raw.trim().toLowerCase();
  if (!cleaned) return "";
  return cleaned.replace(/\s+/g, " ");
}

function readKeywordList(data: FirebaseFirestore.DocumentData): string[] {
  const active = data.activeKeywords;
  if (Array.isArray(active)) {
    return active.map((k) => normalizeKeyword(k)).filter((k) => k.length > 0);
  }
  const rawGroups = data.keywordGroups ?? data.keywords;
  if (rawGroups && typeof rawGroups === "object") {
    const groups = rawGroups as Record<string, unknown>;
    const lists: unknown[] = [];
    const searching = groups["Searching For"] ?? groups["SearchingFor"] ?? groups["searchingFor"];
    const providing = groups["Can Provide"] ?? groups["CanProvide"] ?? groups["canProvide"];
    if (Array.isArray(searching)) lists.push(...searching);
    if (Array.isArray(providing)) lists.push(...providing);
    return lists.map((k) => normalizeKeyword(k)).filter((k) => k.length > 0);
  }
  return [];
}

export const recomputeDashboardMetrics = functions.pubsub
  .schedule("every 60 minutes")
  .timeZone("UTC")
  .onRun(async () => {
    const start = new Date();
    start.setUTCHours(0, 0, 0, 0);

    const usersSnap = await db.collection("users").get();
    const totalUsers = usersSnap.size;

    let newUsersToday = 0;
    let usersWithBusinessEnabled = 0;
    let usersWithBusinessEnabledToday = 0;

    usersSnap.docs.forEach((doc) => {
      const data = doc.data() || {};
      const createdAt = data.createdAt ?? data.joinedAt;
      if (createdAt instanceof admin.firestore.Timestamp) {
        if (createdAt.toDate() >= start) newUsersToday += 1;
      }

      const isBusinessEnabled = data.businessEnabled === true || data.isBusiness === true;
      if (isBusinessEnabled) {
        usersWithBusinessEnabled += 1;
        const enabledAt = toTimestamp(data.businessModeEnabledAt) ??
          toTimestamp(data.updatedAt) ??
          toTimestamp(data.createdAt) ??
          toTimestamp(data.joinedAt);
        if (enabledAt != null && enabledAt.toDate() >= start) {
          usersWithBusinessEnabledToday += 1;
        }
      }
    });

    const presenceSnap = await db
      .collectionGroup("presence")
      .where("kind", "==", "current")
      .get();
    const geofenceUidSet = new Set<string>();
    presenceSnap.docs.forEach((doc) => {
      const parentUser = doc.ref.parent.parent;
      const uid = (parentUser?.id ?? "").trim();
      if (!uid) return;
      const data = doc.data() || {};
      if (data.geopoint instanceof admin.firestore.GeoPoint) {
        geofenceUidSet.add(uid);
      }
    });
    const geofenceUsersCovered = geofenceUidSet.size;
    const geofenceCoverageRatio =
      totalUsers > 0 ? Math.min(1, geofenceUsersCovered / totalUsers) : 0;

    const referralRewardsSnap = await db
      .collectionGroup("referrals")
      .where("rewardCredited", "==", true)
      .get();
    let totalReferralPointsPaidOut = 0;
    referralRewardsSnap.docs.forEach((doc) => {
      const data = doc.data() || {};
      const payout = Math.max(0, Math.floor(toNumber(data.rewardPoints, REFERRAL_PAYOUT_POINTS_FALLBACK)));
      totalReferralPointsPaidOut += payout;
    });

    const supportRewardsSnap = await db
      .collection("support_tickets")
      .where("payoutCredited", "==", true)
      .get();
    let totalSupportPointsPaidOut = 0;
    supportRewardsSnap.docs.forEach((doc) => {
      const data = doc.data() || {};
      const payout = Math.max(0, Math.floor(toNumber(data.payoutPoints, SUPPORT_PAYOUT_POINTS_FALLBACK)));
      totalSupportPointsPaidOut += payout;
    });
    const totalPointsPaidOut = totalReferralPointsPaidOut + totalSupportPointsPaidOut;

    const businessEntitlementsSnap = await db
      .collectionGroup("entitlements")
      .where("businessModeActive", "==", true)
      .get();
    let businessUsersFromEntitlementsToday = 0;
    businessEntitlementsSnap.docs.forEach((doc) => {
      const data = doc.data() || {};
      const updatedAt = toTimestamp(data.updatedAt);
      if (updatedAt != null && updatedAt.toDate() >= start) {
        businessUsersFromEntitlementsToday += 1;
      }
    });

    const totalBusinessModeUsers = businessEntitlementsSnap.size > 0
      ? businessEntitlementsSnap.size
      : usersWithBusinessEnabled;
    const newBusinessModeUsersToday = businessEntitlementsSnap.size > 0
      ? businessUsersFromEntitlementsToday
      : usersWithBusinessEnabledToday;

    const profilesSnap = await db.collection("profiles").get();
    const counts = new Map<string, number>();

    profilesSnap.docs.forEach((doc) => {
      const data = doc.data() || {};
      const keywords = readKeywordList(data);
      keywords.forEach((k) => {
        counts.set(k, (counts.get(k) ?? 0) + 1);
      });
    });

    const sorted = Array.from(counts.entries()).sort((a, b) => b[1] - a[1]);
    const topKeywords = sorted.slice(0, 8).map(([keyword, count]) => ({ keyword, count }));

    const countsRef = db.collection("dashboard").doc("keywordCounts");
    const prevSnap = await countsRef.get();
    const prevCounts = (prevSnap.data()?.counts as Record<string, number> | undefined) ?? {};

    const deltas: Array<{ keyword: string; delta: number }> = [];
    for (const [keyword, count] of sorted) {
      const prev = prevCounts[keyword] ?? 0;
      const delta = count - prev;
      if (delta > 0) deltas.push({ keyword, delta });
    }

    deltas.sort((a, b) => b.delta - a.delta);
    const trendingKeywords = deltas.slice(0, 6);

    const limitedCounts: Record<string, number> = {};
    sorted.slice(0, 300).forEach(([keyword, count]) => {
      limitedCounts[keyword] = count;
    });

    const metricsRef = db.collection("dashboard").doc("metrics");
    await metricsRef.set(
      {
        totalUsers,
        newUsersToday,
        geofenceUsersCovered,
        geofenceCoverageRatio,
        totalPointsPaidOut,
        totalReferralPointsPaidOut,
        totalSupportPointsPaidOut,
        totalBusinessModeUsers,
        newBusinessModeUsersToday,
        topKeywords,
        trendingKeywords,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await countsRef.set(
      {
        counts: limitedCounts,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return null;
  });
