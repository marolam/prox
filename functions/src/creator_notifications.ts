import * as admin from "firebase-admin";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

function toUserIdFromEntitlementPath(path: string): string {
  // users/{uid}/billing/entitlements
  const parts = path.split("/");
  if (parts.length >= 2 && parts[0] === "users") {
    return parts[1] || "";
  }
  return "";
}

async function listTokensForUser(uid: string): Promise<string[]> {
  if (!uid.trim()) return [];
  const snap = await db.collection("users").doc(uid).collection("deviceTokens").limit(40).get();
  return snap.docs
    .filter((d) => d.data()?.valid !== false)
    .map((d) => d.id)
    .filter((t) => typeof t === "string" && t.trim().length > 0);
}

async function listAudienceTokens(audience: string, createdByUid: string): Promise<string[]> {
  if (audience === "self") {
    return listTokensForUser(createdByUid);
  }

  if (audience === "business_only") {
    const entSnap = await db
      .collectionGroup("billing")
      .where("businessSubscriptionActive", "==", true)
      .limit(1500)
      .get();

    const uids = Array.from(new Set(entSnap.docs
      .filter((d) => d.id === "entitlements")
      .map((d) => toUserIdFromEntitlementPath(d.ref.path))
      .filter((u) => u.trim().length > 0)));

    const tokenSets = await Promise.all(uids.map((uid) => listTokensForUser(uid)));
    return Array.from(new Set(tokenSets.flat()));
  }

  const tokenSnap = await db.collectionGroup("deviceTokens").limit(3500).get();
  return Array.from(new Set(tokenSnap.docs
    .filter((d) => d.data()?.valid !== false)
    .map((d) => d.id)
    .filter((t) => typeof t === "string" && t.trim().length > 0)));
}

async function sendMulticast(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ success: number; failure: number }> {
  if (!tokens.length) return { success: 0, failure: 0 };

  let success = 0;
  let failure = 0;

  for (const bucket of chunk(tokens, 500)) {
    const resp = await admin.messaging().sendEachForMulticast({
      tokens: bucket,
      notification: { title, body },
      data,
    });
    success += resp.successCount;
    failure += resp.failureCount;
  }

  return { success, failure };
}

export const onDashboardAnnouncementCreate = onDocumentCreated(
  "dashboard/announcements/items/{announcementId}",
  async (event) => {
    const after = event.data;
    if (!after?.exists) return;

    const d = after.data() ?? {};
    const active = d.active !== false;
    const broadcast = d.broadcast === true;

    if (!active || !broadcast) return;

    const title = (d.title ?? "Announcement").toString();
    const body = (d.body ?? "Open HQ for details.").toString();
    const audience = (d.audience ?? "all").toString().trim() || "all";
    const createdByUid = (d.createdBy ?? "").toString().trim();

    const tokens = await listAudienceTokens(audience, createdByUid);
    const res = await sendMulticast(tokens, title, body, {
      type: "announcement",
      audience,
      announcementId: event.params.announcementId,
      ts: String(Date.now()),
    });

    await after.ref.set(
      {
        broadcastAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
        broadcastAudience: audience,
        broadcastTokenCount: tokens.length,
        broadcastSuccessCount: res.success,
        broadcastFailureCount: res.failure,
      },
      { merge: true },
    );

    logger.info("announcement broadcast complete", {
      id: event.params.announcementId,
      audience,
      tokens: tokens.length,
      success: res.success,
      failure: res.failure,
    });
  },
);

export const onBusinessSubscriptionCongratsParty = onDocumentUpdated(
  "users/{uid}/billing/entitlements",
  async (event) => {
    const before = event.data?.before;
    const after = event.data?.after;
    if (!before?.exists || !after?.exists) return;

    const b = before.data() ?? {};
    const a = after.data() ?? {};

    const wasActive = b.businessSubscriptionActive === true;
    const isActive = a.businessSubscriptionActive === true;
    if (wasActive || !isActive) return;

    const uid = event.params.uid;
    if (!uid) return;

    const userSnap = await db.collection("users").doc(uid).get();
    const userData = userSnap.data() ?? {};
    const displayName = (userData.displayName ?? userData.name ?? "Your party member").toString();

    const partySnap = await db.collection("users").doc(uid).collection("party").limit(200).get();
    const partyUids = partySnap.docs
      .map((d) => d.id)
      .filter((id) => id && id !== uid);

    if (!partyUids.length) return;

    const tokenSets = await Promise.all(partyUids.map((partyUid) => listTokensForUser(partyUid)));
    const tokens = Array.from(new Set(tokenSets.flat()));

    const title = "Party upgrade unlocked";
    const body = `${displayName} subscribed to Business Mode. Reach out now and switch on business-only matches for immediate pairing.`;

    const res = await sendMulticast(tokens, title, body, {
      type: "party_business_congrats",
      sourceUid: uid,
      ts: String(Date.now()),
    });

    await db.collection("users").doc(uid).collection("meta").doc("businessCongrats").set(
      {
        lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
        recipients: partyUids.length,
        tokenCount: tokens.length,
        success: res.success,
        failure: res.failure,
      },
      { merge: true },
    );

    logger.info("party congrats sent", {
      uid,
      recipients: partyUids.length,
      tokenCount: tokens.length,
      success: res.success,
      failure: res.failure,
    });
  },
);
