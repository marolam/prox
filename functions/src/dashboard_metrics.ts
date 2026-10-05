import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {publicProfile} from "./public_profiles";

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

export async function recomputeDashboardMetricsSnapshot(options: {
  now?: number; registrationTimes?: Record<string, number>;
} = {}): Promise<Record<string, unknown>> {
    const now = options.now ?? Date.now();
    const start = new Date(now);
    start.setUTCHours(0, 0, 0, 0);
    const end = start.getTime() + 86400000;

    const [usersSnap, deleted] = await Promise.all([db.collection("users").get(), db.collection("accountDeletions").get()]);
    const deletedUids = new Set(deleted.docs.map(doc => doc.id));
    const users = usersSnap.docs.filter(doc => !deletedUids.has(doc.id) && doc.get("deleted") !== true);
    const userIds = new Set(users.map(doc => doc.id));
    const totalUsers = users.length;

    let newUsersToday = 0;
    const registrations = {...options.registrationTimes};
    if (!options.registrationTimes) {
      // Auth timestamps cannot be forged by editing an owner profile's createdAt field.
      const uids = Array.from(userIds);
      for (let i = 0; i < uids.length; i += 100) {
        const batch = await admin.auth().getUsers(uids.slice(i, i + 100).map(uid => ({uid})));
        for (const user of batch.users) registrations[user.uid] = Date.parse(user.metadata.creationTime);
      }
    }
    users.forEach(doc => {
      const registered = registrations[doc.id];
      if (Number.isFinite(registered) && registered >= start.getTime() && registered < end && registered <= now) newUsersToday++;
    });

    const presenceSnap = await db
      .collectionGroup("presence")
      .get();
    const geofenceUidSet = new Set<string>();
    presenceSnap.docs.forEach((doc) => {
      if (!/^users\/[^/]+\/presence\/[^/]+$/.test(doc.ref.path)) return;
      const parentUser = doc.ref.parent.parent;
      const uid = (parentUser?.id ?? "").trim();
      if (!uid || !userIds.has(uid)) return;
      const data = doc.data() || {};
      if (data.kind === "current" && data.geopoint instanceof admin.firestore.GeoPoint) {
        geofenceUidSet.add(uid);
      }
    });
    const geofenceUsersCovered = geofenceUidSet.size;
    const geofenceCoverageRatio =
      totalUsers > 0 ? Math.min(1, geofenceUsersCovered / totalUsers) : 0;

    const referralRewardsSnap = await db
      .collectionGroup("referrals")
      .get();
    let totalReferralPointsPaidOut = 0;
    referralRewardsSnap.docs.forEach((doc) => {
      if (!/^users\/[^/]+\/referrals\/[^/]+$/.test(doc.ref.path) || !userIds.has(doc.ref.path.split("/")[1])) return;
      const data = doc.data() || {};
      if (data.rewardCredited !== true) return;
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
      const owner = data.technicianId || data.technicianUid || data.ownerUid || data.userId || data.uid;
      if (typeof owner === "string" && deletedUids.has(owner)) return;
      const payout = Math.max(0, Math.floor(toNumber(data.payoutPoints, SUPPORT_PAYOUT_POINTS_FALLBACK)));
      totalSupportPointsPaidOut += payout;
    });
    const totalPointsPaidOut = totalReferralPointsPaidOut + totalSupportPointsPaidOut;

    const businessEntitlementsSnap = await db
      .collectionGroup("billing")
      .get();
    const activeBusiness = businessEntitlementsSnap.docs.filter(doc => {
      if (!/^users\/[^/]+\/billing\/entitlements$/.test(doc.ref.path) || !userIds.has(doc.ref.path.split("/")[1])) return false;
      const data = doc.data();
      const expires = toTimestamp(data.subscriptionRenewsAt);
      return data.businessModeActive === true && (data.businessPurchased === true ||
        (data.businessSubscriptionActive === true && expires !== null && expires.toMillis() > now));
    });
    let businessUsersFromEntitlementsToday = 0;
    let businessActivationDatesKnown = 0;
    activeBusiness.forEach((doc) => {
      const data = doc.data() || {};
      const enabledAt = toTimestamp(data.businessModeEnabledAt);
      if (enabledAt) businessActivationDatesKnown++;
      if (enabledAt != null && enabledAt.toMillis() >= start.getTime() && enabledAt.toMillis() < end && enabledAt.toMillis() <= now) {
        businessUsersFromEntitlementsToday += 1;
      }
    });

    const totalBusinessModeUsers = activeBusiness.length;

    const profilesSnap = await db.collection("profiles").get();
    const legacyProfiles = new Map(profilesSnap.docs.map(doc => [doc.id, doc.data()]));
    const counts = new Map<string, number>();

    users.forEach((doc) => {
      const data = doc.data() || {};
      const modern = ["keywords", "keywordGroups", "SearchingFor", "CanProvide", "Searching For", "Can Provide"]
        .some(key => Object.prototype.hasOwnProperty.call(data, key));
      const keywords = modern ? readKeywordList(publicProfile(doc.id, data))
        : readKeywordList(legacyProfiles.get(doc.id) || data);
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
    const metrics = {
        totalUsers,
        newUsersToday,
        geofenceUsersCovered,
        geofenceCoverageRatio,
        totalPointsPaidOut,
        totalReferralPointsPaidOut,
        totalSupportPointsPaidOut,
        totalBusinessModeUsers,
        newBusinessModeUsersToday: businessActivationDatesKnown === totalBusinessModeUsers
          ? businessUsersFromEntitlementsToday : admin.firestore.FieldValue.delete(),
        businessActivationDatesKnown,
        businessActivationDatesUnknown: totalBusinessModeUsers - businessActivationDatesKnown,
        topKeywords,
        trendingKeywords,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
    const batch = db.batch();
    batch.set(metricsRef, metrics, {merge: true});
    batch.set(countsRef,
      {
        counts: limitedCounts,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await batch.commit();
    return metrics;
}

export const recomputeDashboardMetrics = functions.region("us-central1").runWith({timeoutSeconds: 300}).pubsub
  .schedule("every 60 minutes")
  .timeZone("UTC")
  .onRun(async () => {
    await recomputeDashboardMetricsSnapshot();
    return null;
  });
