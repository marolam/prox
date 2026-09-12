import * as admin from "firebase-admin";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { randomBytes } from "crypto";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const DEFAULT_PUBLIC_APK_URL =
  "https://github.com/marolam/prox/releases/latest/download/app-release.apk";
const DEFAULT_REFERRAL_DOWNLOAD_URL =
  "https://us-central1-prox-42bef.cloudfunctions.net/referralApkDownload";
const SINGLE_USE_TTL_MINUTES = 20;

function parseTruthy(v: unknown): boolean {
  const s = String(v ?? "").trim().toLowerCase();
  return s === "1" || s === "true" || s === "yes" || s === "on";
}

function normalizeCode(raw: string): string {
  return raw.trim().toUpperCase().replace(/[^A-Z0-9\-_]/g, "");
}

function readPublicApkUrl(): string {
  return String(process.env.PROX_PUBLIC_APK_URL ?? "").trim();
}

function readFallbackApkUrl(): string {
  const fromEnv = String(process.env.PROX_PUBLIC_APK_FALLBACK_URL ?? "").trim();
  if (fromEnv) return fromEnv;
  return DEFAULT_PUBLIC_APK_URL;
}

function isAllowedApkUrl(raw: string): boolean {
  const s = raw.trim();
  if (!s) return false;
  let parsed: URL;
  try {
    parsed = new URL(s);
  } catch (_) {
    return false;
  }
  if (parsed.protocol !== "https:") return false;
  const path = parsed.pathname.toLowerCase();
  return parsed.hostname === 'github.com' && path.startsWith('/marolam/prox/releases/') && path.endsWith('.apk');
}

function readForwardedIp(req: { get: (name: string) => string | undefined }): string {
  const xf = String(req.get("x-forwarded-for") ?? "").trim();
  if (!xf) return "";
  return xf.split(",")[0].trim();
}

function parseAuthBearer(req: { get: (name: string) => string | undefined }): string {
  const auth = String(req.get("authorization") ?? req.get("Authorization") ?? "").trim();
  if (!auth.toLowerCase().startsWith("bearer ")) return "";
  return auth.slice(7).trim();
}

async function requireAuthedUid(req: { get: (name: string) => string | undefined }): Promise<string> {
  const token = parseAuthBearer(req);
  if (!token) {
    throw new Error("missing_auth");
  }
  const decoded = await admin.auth().verifyIdToken(token, true);
  const uid = String(decoded.uid ?? "").trim();
  if (!uid) {
    throw new Error("invalid_auth");
  }
  return uid;
}

function parseFinite(value: unknown): number | null {
  if (value == null || value === '' || typeof value === 'boolean') return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

function clampAccuracyMeters(value: number | null): number {
  if (value == null) return 100;
  if (value < 1) return 1;
  if (value > 1000) return 1000;
  return value;
}

function haversineDistanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const r = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return 2 * r * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function createSingleUseTokenId(): string {
  return `T-${randomBytes(9).toString("hex").toUpperCase()}`;
}

function buildReferralDownloadLinkWithToken(token: string): string {
  const root = String(process.env.PROX_REFERRAL_DOWNLOAD_URL ?? "").trim() || DEFAULT_REFERRAL_DOWNLOAD_URL;
  const url = new URL(root);
  url.searchParams.set("t", token);
  return url.toString();
}

type ResLike = {
  status: (code: number) => ResLike;
  json: (payload: unknown) => void;
  set: (header: string, value: string) => void;
  redirect: (status: number, url: string) => void;
};

export const createReferralSingleUseToken = onRequest(async (req, res: ResLike) => {
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "method_not_allowed" });
    return;
  }

  let uid = "";
  try {
    uid = await requireAuthedUid(req);
  } catch (_) {
    res.status(401).json({ ok: false, error: "unauthenticated" });
    return;
  }

  const body = (typeof req.body === "object" && req.body !== null) ? req.body as Record<string, unknown> : {};
  const lat = parseFinite(body.latitude);
  const lng = parseFinite(body.longitude);
  const accuracyM = clampAccuracyMeters(parseFinite(body.accuracyM));

  const token = createSingleUseTokenId();
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + SINGLE_USE_TTL_MINUTES * 60 * 1000,
  );

  const tokenRef = db.collection("referralSingleUseTokens").doc(token);
  await tokenRef.set({
    token,
    referrerUid: uid,
    status: "new",
    singleUse: true,
    createdAt: now,
    updatedAt: now,
    expiresAt,
    referrerLocation: (lat != null && lng != null) ? {
      latitude: lat,
      longitude: lng,
      accuracyM,
      capturedAt: now,
    } : null,
  }, { merge: true });

  const qrLink = buildReferralDownloadLinkWithToken(token);
  res.status(200).json({
    ok: true,
    token,
    qrLink,
    expiresAt: expiresAt.toDate().toISOString(),
  });
});

export const referralApkDownload = onRequest(async (req, res: ResLike) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.status(405).json({ ok: false, error: "method_not_allowed" });
    return;
  }

  const singleUseToken = String(req.query.t ?? req.query.token ?? "").trim();
  if (singleUseToken && !/^T-[A-F0-9]{18}$/.test(singleUseToken)) {
    res.status(400).json({ok: false, error: 'invalid_token'});
    return;
  }
  const code = normalizeCode(String(req.query.code ?? req.query.referral ?? req.query.invite ?? ""));
  const referrerHint = String(req.query.ref ?? req.query.referrer ?? "").trim();
  const inPersonQrRequested =
    parseTruthy(req.query.party) || parseTruthy(req.query.inperson) || parseTruthy(req.query.partyJoin);

  if (!singleUseToken && !code) {
    res.status(400).json({ ok: false, error: "missing_code" });
    return;
  }

  let owner = "";
  let root = "";
  let normalizedCode = code;

  if (singleUseToken) {
    const tokenRef = db.collection("referralSingleUseTokens").doc(singleUseToken);
    const tokenSnap = await tokenRef.get();
    if (!tokenSnap.exists) {
      res.status(404).json({ ok: false, error: "invalid_token" });
      return;
    }

    const tokenData = tokenSnap.data() ?? {};
    owner = String(tokenData.referrerUid ?? "").trim();
    root = String(tokenData.rootReferrerUid ?? owner).trim() || owner;
    const status = String(tokenData.status ?? "new").trim();
    const expiresAtRaw = tokenData.expiresAt;
    const expiresAt = expiresAtRaw instanceof admin.firestore.Timestamp
      ? expiresAtRaw.toDate().getTime()
      : 0;

    if (!owner) {
      res.status(403).json({ ok: false, error: "token_unavailable" });
      return;
    }
    if (expiresAt > 0 && Date.now() > expiresAt) {
      await tokenRef.set({
        status: "expired",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      res.status(410).json({ ok: false, error: "token_expired" });
      return;
    }
    if (status !== "new") {
      res.status(409).json({ ok: false, error: "token_already_used" });
      return;
    }
  } else {
    const codeRef = db.collection("referralCodes").doc(code);
    const codeSnap = await codeRef.get();
    if (!codeSnap.exists) {
      res.status(404).json({ ok: false, error: "invalid_code" });
      return;
    }

    const data = codeSnap.data() ?? {};
    const active = data.active !== false;
    const blocked = data.blocked === true;
    const flagged = data.flagged === true;
    owner = String(data.referrerUid ?? "").trim();
    root = String(data.rootReferrerUid ?? owner).trim();

    if (!active || blocked || flagged || !owner) {
      res.status(403).json({ ok: false, error: "code_unavailable" });
      return;
    }
  }

  const apkHint = String(req.query.apk ?? "").trim();
  const apkUrl =
    readPublicApkUrl() ||
    (isAllowedApkUrl(apkHint) ? apkHint : "") ||
    readFallbackApkUrl();
  if (!apkUrl) {
    logger.error("referralApkDownload missing apk target", {
      hasHint: apkHint.length > 0,
    });
    res.status(503).json({ ok: false, error: "apk_url_not_configured" });
    return;
  }
  if (req.method === 'HEAD') {
    res.set('Cache-Control', 'no-store');
    res.redirect(302, apkUrl);
    return;
  }

  const now = admin.firestore.FieldValue.serverTimestamp();
  const clickRef = db.collection("referralDownloadClicks").doc();
  const ownerLeadRef = db
    .collection("users")
    .doc(owner)
    .collection("referralDownloadLeads")
    .doc(clickRef.id);

  const ua = String(req.get("user-agent") ?? "").slice(0, 400);
  const ip = readForwardedIp(req);

  await db.runTransaction(async (tx) => {
    if (singleUseToken) {
      const tokenRef = db.collection("referralSingleUseTokens").doc(singleUseToken);
      const tokenSnap = await tx.get(tokenRef);
      if (!tokenSnap.exists) {
        throw new Error("invalid_token");
      }
      const tokenData = tokenSnap.data() ?? {};
      const status = String(tokenData.status ?? "new").trim();
      const expiresAtRaw = tokenData.expiresAt;
      const expiresAt = expiresAtRaw instanceof admin.firestore.Timestamp
        ? expiresAtRaw.toDate().getTime()
        : 0;
      if (status !== "new") {
        throw new Error("token_already_used");
      }
      if (expiresAt > 0 && Date.now() > expiresAt) {
        tx.set(tokenRef, {
          status: "expired",
          updatedAt: now,
        }, { merge: true });
        throw new Error("token_expired");
      }
      tx.set(tokenRef, {
        status: "claimed",
        claimedAt: now,
        claimedByIp: ip,
        claimedUserAgent: ua,
        clickId: clickRef.id,
        updatedAt: now,
      }, { merge: true });
    }

    tx.set(clickRef, {
      code,
      token: singleUseToken || null,
      referrerUid: owner,
      rootReferrerUid: root,
      referrerHint,
      inPersonQrRequested,
      source: "apk_redirect",
      userAgent: ua,
      ip,
      createdAt: now,
    });

    tx.set(
      ownerLeadRef,
      {
        code,
        token: singleUseToken || null,
        status: "apk_download_started",
        source: "apk_redirect",
        inPersonQrRequested,
        referrerHint,
        clickId: clickRef.id,
        createdAt: now,
        updatedAt: now,
      },
      { merge: true },
    );
  });

  if (singleUseToken) {
    normalizedCode = "";
  }

  const redirectUrl = new URL(apkUrl);
  redirectUrl.searchParams.set("ref", owner);
  if (normalizedCode) {
    redirectUrl.searchParams.set("code", normalizedCode);
  }
  if (singleUseToken) {
    redirectUrl.searchParams.set("t", singleUseToken);
  }
  if (inPersonQrRequested) {
    redirectUrl.searchParams.set("party", "1");
    redirectUrl.searchParams.set("inperson", "1");
  }

  res.set("Cache-Control", "no-store");
  res.redirect(302, redirectUrl.toString());
});

export const finalizeReferralSingleUseToken = onRequest(async (req, res: ResLike) => {
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "method_not_allowed" });
    return;
  }

  let inviteeUid = "";
  try {
    inviteeUid = await requireAuthedUid(req);
  } catch (_) {
    res.status(401).json({ ok: false, error: "unauthenticated" });
    return;
  }

  const body = (typeof req.body === "object" && req.body !== null) ? req.body as Record<string, unknown> : {};
  const token = String(body.token ?? "").trim();
  if (!/^T-[A-F0-9]{18}$/.test(token)) {
    res.status(400).json({ ok: false, error: "missing_token" });
    return;
  }

  const inviteeLat = parseFinite(body.latitude);
  const inviteeLng = parseFinite(body.longitude);
  const inviteeAccuracyM = clampAccuracyMeters(parseFinite(body.accuracyM));

  const tokenRef = db.collection("referralSingleUseTokens").doc(token);
  const now = admin.firestore.FieldValue.serverTimestamp();

  try {
    const result = await db.runTransaction(async (tx) => {
      const tokenSnap = await tx.get(tokenRef);
      if (!tokenSnap.exists) {
        throw new Error("invalid_token");
      }

      const tokenData = tokenSnap.data() ?? {};
      const referrerUid = String(tokenData.referrerUid ?? "").trim();
      if (!referrerUid) {
        throw new Error("invalid_token_owner");
      }
      if (referrerUid === inviteeUid) {
        throw new Error("self_referral_blocked");
      }

      const status = String(tokenData.status ?? "new").trim();
      if (status === "completed") {
        if (tokenData.completedByUid !== inviteeUid) throw new Error('token_not_claimable');
        return {
          inPersonVerified: tokenData.inPersonVerified === true,
          distanceM: Number(tokenData.distanceM ?? 0),
          verificationStatus: String(tokenData.verificationStatus ?? "already_completed"),
          referrerUid,
        };
      }
      if (status !== "claimed" && status !== "new") {
        throw new Error("token_not_claimable");
      }
      if (!(tokenData.expiresAt instanceof admin.firestore.Timestamp) ||
          tokenData.expiresAt.toMillis() <= Date.now()) throw new Error('token_expired');

      const refLoc = tokenData.referrerLocation as Record<string, unknown> | undefined;
      const refLat = parseFinite(refLoc?.latitude);
      const refLng = parseFinite(refLoc?.longitude);
      const refAcc = clampAccuracyMeters(parseFinite(refLoc?.accuracyM));
      const partyInPersonQrRequested = tokenData.inPersonQrRequested === true;
      let distanceM = Number.NaN;
      let inPersonVerified = false;
      let verificationStatus = "pending_location";

      if (refLat != null && refLng != null && inviteeLat != null && inviteeLng != null &&
          Math.abs(refLat) <= 90 && Math.abs(inviteeLat) <= 90 &&
          Math.abs(refLng) <= 180 && Math.abs(inviteeLng) <= 180) {
        distanceM = haversineDistanceMeters(refLat, refLng, inviteeLat, inviteeLng);
        const thresholdM = Math.max(60, refAcc + inviteeAccuracyM + 30);
        inPersonVerified = distanceM <= thresholdM;
        verificationStatus = inPersonVerified ? "verified_in_person" : "distance_mismatch";
      }

      const referrerUserRef = db.collection("users").doc(referrerUid);
      const inviteeUserRef = db.collection("users").doc(inviteeUid);
      const referralDocRef = referrerUserRef.collection("referrals").doc(inviteeUid);
      const attributionRef = db.doc(`referralAttributions/${inviteeUid}`);
      const [existingUser, existingReferral, attribution] = await tx.getAll(inviteeUserRef, referralDocRef, attributionRef);
      const priorReferrer = attribution.data()?.referrerUid || existingUser.data()?.referrer;
      if (priorReferrer && priorReferrer !== referrerUid) throw new Error('referrer_already_assigned');
      if (existingReferral.data()?.rewardCredited === true) throw new Error('referral_already_rewarded');

      if (!attribution.exists) tx.create(attributionRef, {referrerUid, createdAt: now, token});
      tx.set(tokenRef, {
        status: "completed",
        completedByUid: inviteeUid,
        completedAt: now,
        inviteeLocation: (inviteeLat != null && inviteeLng != null) ? {
          latitude: inviteeLat,
          longitude: inviteeLng,
          accuracyM: inviteeAccuracyM,
        } : null,
        inPersonVerified,
        verificationStatus,
        distanceM: Number.isFinite(distanceM) ? distanceM : null,
        updatedAt: now,
      }, { merge: true });

      tx.set(inviteeUserRef, {
        referrer: referrerUid,
        root_referrer: String(tokenData.rootReferrerUid ?? referrerUid).trim() || referrerUid,
        referralStatus: inPersonVerified ? "verified" : "pending_in_person_verification",
        referralToken: token,
        updatedAt: now,
      }, { merge: true });

      tx.set(referralDocRef, {
        token,
        status: inPersonVerified ? "verified" : "pending",
        inPersonVerified,
        verificationStatus,
        partyInPersonQrRequested,
        rewardEligible: inPersonVerified,
        rewardGranted: false,
        rewardCredited: false,
        meetupsCompleted: 0,
        joinedAt: now,
        updatedAt: now,
      }, { merge: true });

      return {
        inPersonVerified,
        distanceM: Number.isFinite(distanceM) ? distanceM : null,
        verificationStatus,
        referrerUid,
      };
    });

    res.status(200).json({
      ok: true,
      inPersonVerified: result.inPersonVerified,
      verificationStatus: result.verificationStatus,
      distanceM: result.distanceM,
      referrerUid: result.referrerUid,
      message: result.inPersonVerified
        ? "Referral verified in person and linked to your referrer."
        : "Referral linked. In-person verification is still pending.",
    });
  } catch (e) {
    const err = String((e as Error)?.message ?? e ?? "unknown");
    const status = (
      err === "missing_auth" ||
      err === "invalid_auth"
    ) ? 401 : (
      err === "invalid_token" || err === "invalid_token_owner"
    ) ? 404 : (
      err === "self_referral_blocked" || err === "token_not_claimable" || err === 'token_expired' ||
      err === 'referrer_already_assigned' || err === 'referral_already_rewarded'
    ) ? 409 : 500;

    logger.error("finalizeReferralSingleUseToken failed", {
      error: err,
      inviteeUid,
    });
    res.status(status).json({ ok: false, error: err });
  }
});

/** Link codes on the server so the code owner, direction and reward flags cannot be forged. */
export const linkReferralCode = onCall({region: 'us-central1'}, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to accept a referral.');
  const uid = request.auth.uid;
  const code = normalizeCode(String(request.data?.code || '')).slice(0, 80);
  if (!code) throw new HttpsError('invalid-argument', 'A referral code is required.');
  return db.runTransaction(async tx => {
    const userRef = db.doc(`users/${uid}`);
    const attribution = db.doc(`referralAttributions/${uid}`);
    const [codeSnap, userSnap, prior, deletion] = await tx.getAll(db.doc(`referralCodes/${code}`), userRef, attribution, db.doc(`accountDeletions/${uid}`));
    const definition = codeSnap.data() || {};
    const owner = String(definition.referrerUid || definition.ownerUid || definition.uid || definition.userId || '');
    if (deletion.exists || !codeSnap.exists || definition.active === false || definition.blocked === true || definition.flagged === true || !owner || owner.includes('/')) {
      throw new HttpsError('failed-precondition', 'This referral code is unavailable.');
    }
    if (owner === uid) throw new HttpsError('invalid-argument', 'You cannot refer yourself.');
    const existing = String(prior.data()?.referrerUid || userSnap.data()?.referrer || '');
    if (existing && existing !== owner) throw new HttpsError('already-exists', 'A referrer is already assigned.');
    if (prior.exists) return {linked: true, referrerUid: owner, replayed: true};
    const referral = db.doc(`users/${owner}/referrals/${uid}`);
    const [referralSnap, ownerDeletion] = await tx.getAll(referral, db.doc(`accountDeletions/${owner}`));
    if (ownerDeletion.exists) throw new HttpsError('failed-precondition', 'This referral code is unavailable.');
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.create(attribution, {referrerUid: owner, code, createdAt: now});
    tx.set(userRef, {referrer: owner, root_referrer: owner, referralStatus: 'joined', updatedAt: now}, {merge: true});
    if (!referralSnap.exists) tx.create(referral, {
      uid, code, status: 'joined', inPersonVerified: false, rewardEligible: false,
      rewardGranted: false, rewardCredited: false, meetupsCompleted: 0,
      verificationStatus: 'awaiting_in_person_verification', joinedAt: now, updatedAt: now,
    });
    return {linked: true, referrerUid: owner, replayed: false};
  });
});
