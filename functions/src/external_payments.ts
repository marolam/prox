import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { createHmac, timingSafeEqual } from "node:crypto";
import {reconcileSquareLifecycle} from './payment_reconciliation';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

const VALID_SKUS = new Set<string>([
  "biz_monthly_subscription",
  "biz_onetime_unlock",
  "dev_card_test_charge",
  "points_topup_1",
  "points_topup_250",
  "points_topup_600",
  "points_topup_1400",
  "points_topup_4000",
]);

const POINTS_TOPUP_BY_SKU: Record<string, { points: number; amountUsd: number }> = {
  points_topup_1: { points: 1, amountUsd: 0.01 },
  points_topup_250: { points: 250, amountUsd: 4.99 },
  points_topup_600: { points: 600, amountUsd: 9.99 },
  points_topup_1400: { points: 1400, amountUsd: 19.99 },
  points_topup_4000: { points: 4000, amountUsd: 49.99 },
};

const REQUIRED_CHECKOUT_CONFIG_KEYS = [
  "PROX_CHECKOUT_SUCCESS_URL",
] as const;

const IMMEDIATE_DOWNGRADE_STATUSES = new Set<string>([
  "canceled",
  "cancelled",
  "unpaid",
  "past_due",
  "payment_failed",
  "failed",
]);

// Square/processor callback status mapping for monthly subscriptions:
// paid -> activate entitlement and set 30-day renew window
// canceled/cancelled/unpaid/past_due/payment_failed/failed -> immediate downgrade
// any other status -> accepted but no entitlement mutation

function parseBoolEnv(name: string): boolean {
  const raw = (process.env[name] ?? "").toString().trim().toLowerCase();
  return raw === "1" || raw === "true" || raw === "yes" || raw === "on";
}

function normalizeProvider(raw: string): string {
  const clean = raw.trim().toLowerCase();
  if (!clean) return "square";
  if (clean === "square" || clean === "square_prod") return "square";
  return clean;
}

function readRequiredCheckoutConfig(): { ok: true } | { ok: false; missing: string[] } {
  const missing = REQUIRED_CHECKOUT_CONFIG_KEYS.filter((k) => (process.env[k] ?? "").toString().trim().length === 0);
  if (missing.length > 0) return { ok: false, missing };
  return { ok: true };
}

function monthlySubscriptionAmountUsd(): number {
  // Dev switch for checkout pipeline validation without changing source.
  if (parseBoolEnv("PROX_BIZ_MONTHLY_DEV_PRICE_ENABLED")) return 0.01;
  return 49.99;
}

function toAmountCents(usd: number): number {
  return Math.max(0, Math.round(usd * 100));
}

function getSquareAccessToken(): string {
  return (process.env.SQUARE_ACCESS_TOKEN ?? "").toString().trim();
}

function getSquareLocationId(): string {
  return (process.env.SQUARE_LOCATION_ID ?? "").toString().trim();
}

function getSquareApiVersion(): string {
  return (process.env.SQUARE_API_VERSION ?? "2025-01-23").toString().trim() || "2025-01-23";
}

async function createSquarePaymentLink(args: {
  sessionId: string;
  sku: string;
  amountUsd: number;
}): Promise<{ checkoutUrl: string; providerSessionId: string | null; providerOrderId: string }> {
  const accessToken = getSquareAccessToken();
  const locationId = getSquareLocationId();
  const successUrl = (process.env.PROX_CHECKOUT_SUCCESS_URL ?? "").toString().trim();

  if (!accessToken || !locationId || !successUrl) {
    throw new Error("square_checkout_config_missing");
  }

  const base = (process.env.SQUARE_API_BASE_URL ?? "https://connect.squareup.com").toString().trim() || "https://connect.squareup.com";
  const url = `${base}/v2/online-checkout/payment-links`;

  const amountCents = toAmountCents(args.amountUsd);
  const body = {
    idempotency_key: args.sessionId,
    order: {
      location_id: locationId,
      reference_id: `prox_session:${args.sessionId}`,
      line_items: [
        {
          name: args.sku,
          quantity: "1",
          base_price_money: {
            amount: amountCents,
            currency: "USD",
          },
        },
      ],
    },
    checkout_options: {
      redirect_url: successUrl,
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${accessToken}`,
      "square-version": getSquareApiVersion(),
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });

  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`square_checkout_create_failed:${res.status}:${JSON.stringify(json).slice(0, 400)}`);
  }

  const paymentLink = (json as any)?.payment_link ?? {};
  const checkoutUrl = (paymentLink.url ?? "").toString().trim();
  const providerSessionId = (paymentLink.id ?? "").toString().trim() || null;

  if (!checkoutUrl) {
    throw new Error("square_checkout_missing_url");
  }

  return { checkoutUrl, providerSessionId, providerOrderId: String(paymentLink.order_id || "") };
}

function parseSessionIdFromReferenceId(referenceId: string): string {
  const raw = referenceId.trim();
  if (!raw) return "";
  if (raw.startsWith("prox_session:")) {
    return raw.slice("prox_session:".length).trim();
  }
  return raw;
}

async function fetchSquareOrderReferenceId(orderId: string): Promise<string> {
  const cleanOrderId = orderId.trim();
  if (!cleanOrderId) return "";

  const accessToken = getSquareAccessToken();
  if (!accessToken) return "";

  const base = (process.env.SQUARE_API_BASE_URL ?? "https://connect.squareup.com").toString().trim() || "https://connect.squareup.com";
  const url = `${base}/v2/orders/${encodeURIComponent(cleanOrderId)}`;

  const res = await fetch(url, {
    method: "GET",
    signal: AbortSignal.timeout(15000),
    headers: {
      "authorization": `Bearer ${accessToken}`,
      "square-version": getSquareApiVersion(),
    },
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) return "";

  return ((json as any)?.order?.reference_id ?? "").toString().trim();
}

async function findSessionBySessionId(sessionId: string): Promise<{ uid: string; sessionId: string } | null> {
  const clean = sessionId.trim();
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(clean)) return null;
  const registered = await db.doc(`checkoutSessions/${clean}`).get();
  if (registered.exists && typeof registered.data()?.uid === 'string') return {uid: registered.data()!.uid, sessionId: clean};

  const snap = await db
    .collectionGroup("items")
    .where("sessionId", "==", clean)
    .limit(1)
    .get();

  if (snap.empty) return null;
  const refPath = snap.docs[0].ref.path;
  const parts = refPath.split("/");
  if (parts.length < 2 || parts[0] !== "users") return null;
  if (parts.length !== 6 || parts[2] !== "billing" || parts[3] !== "externalCheckout" || parts[4] !== "items") return null;
  const uid = (parts[1] ?? "").trim();
  if (!uid) return null;
  return { uid, sessionId: clean };
}

async function findSessionByProviderSessionId(providerSessionId: string): Promise<{ uid: string; sessionId: string } | null> {
  const clean = providerSessionId.trim();
  if (!clean) return null;
  const registered = await db.collection('checkoutSessions').where('providerSessionId', '==', clean).limit(1).get();
  if (!registered.empty) return {uid: String(registered.docs[0].data().uid), sessionId: registered.docs[0].id};

  const snap = await db
    .collectionGroup("items")
    .where("providerSessionId", "==", clean)
    .limit(1)
    .get();

  if (snap.empty) return null;
  const doc = snap.docs[0];
  const data = doc.data() ?? {};
  const refPath = doc.ref.path;
  const parts = refPath.split("/");
  if (parts.length < 2 || parts[0] !== "users") return null;
  if (parts.length !== 6 || parts[2] !== "billing" || parts[3] !== "externalCheckout" || parts[4] !== "items") return null;
  const uid = (parts[1] ?? "").trim();
  const sessionId = (data.sessionId ?? "").toString().trim();
  if (!uid || !sessionId) return null;
  return { uid, sessionId };
}

export function mapSquareEventToStatus(eventType: string, eventPayload: any): string {
  if (!['payment.created', 'payment.updated'].includes(eventType)) return '';
  return eventPayload?.data?.object?.payment?.status === 'COMPLETED' ? 'paid' : '';
}

export function verifySquareWebhookSignature(req: any): boolean {
  const signatureKey = (process.env.SQUARE_WEBHOOK_SIGNATURE_KEY ?? "").toString().trim();
  if (!signatureKey) return false;

  const headerSig = (req.header("x-square-hmacsha256-signature") ?? "").toString().trim();
  if (!headerSig) return false;

  if (!Buffer.isBuffer(req.rawBody)) return false;
  const rawBody = req.rawBody.toString("utf8");
  const configuredUrl = (process.env.SQUARE_WEBHOOK_ENDPOINT_URL ?? "").toString().trim();
  if (!configuredUrl) return false;
  const notificationUrl = configuredUrl;

  const payloadToSign = `${notificationUrl}${rawBody}`;
  const computed = createHmac("sha256", signatureKey).update(payloadToSign).digest("base64");

  const a = Buffer.from(computed, "utf8");
  const b = Buffer.from(headerSig, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export async function applyExternalCheckoutStatus(args: {
  uid: string; sessionId: string; status: string; providerReference: string;
  callbackPayload: unknown; amountCents?: number; currency?: string; orderId?: string; paymentId?: string;
}): Promise<{ accepted: boolean; applied: boolean; downgraded: boolean; sku: string }> {
  const {uid, sessionId, status, providerReference} = args;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(uid) || !/^[A-Za-z0-9_-]{1,128}$/.test(sessionId)) {
    throw new Error('invalid_session_identity');
  }
  const sessionRef = db.doc(`users/${uid}/billing/externalCheckout/items/${sessionId}`);
  const entitlementRef = db.doc(`users/${uid}/billing/entitlements`);
  const pointsRef = db.doc(`users/${uid}/meta/points`);
  const invoiceRef = db.doc(`users/${uid}/billing/invoices/items/${sessionId}`);
  return db.runTransaction(async tx => {
    // All reads precede writes. The session and invoice are the durable
    // idempotency record, atomically committed with every grant or debit.
    const [sessionSnap, entSnap, pointsSnap, invoiceSnap, deletion] = await tx.getAll(sessionRef, entitlementRef, pointsRef, invoiceRef,
      db.doc(`accountDeletions/${uid}`));
    if (deletion.exists) throw new Error('account_deleted');
    if (!sessionSnap.exists) throw new Error('session_not_found');
    const session = sessionSnap.data()!;
    const sku = String(session.sku || '');
    if (!VALID_SKUS.has(sku)) throw new Error('invalid_session_sku');
    if (session.uid !== uid || session.provider !== 'square') throw new Error('invalid_session_identity');
    if (session.providerOrderId && args.orderId !== session.providerOrderId) throw new Error('payment_order_mismatch');
    if (status === 'paid' && (args.currency !== 'USD' || args.amountCents !== toAmountCents(Number(session.amountUsd)))) {
      throw new Error('payment_amount_mismatch');
    }
    const wasGranted = invoiceSnap.exists;
    if (status === 'paid' && wasGranted) return {accepted: true, applied: false, downgraded: false, sku};
    if (status === 'paid' && (session.refundReviewRequired === true || ['refunded', 'canceled', 'cancelled'].includes(String(session.status)))) {
      return {accepted: true, applied: false, downgraded: false, sku};
    }
    const ent = entSnap.data() || {};
    const now = admin.firestore.FieldValue.serverTimestamp();
    const patch: Record<string, unknown> = {
      updatedAt: now, lastSku: sku, lastPaymentMethod: 'card_external',
      lastExternalSessionId: sessionId, lastExternalProviderReference: providerReference,
    };
    if (sku === 'biz_monthly_subscription' && IMMEDIATE_DOWNGRADE_STATUSES.has(status)) {
      if (ent.lastExternalSessionId === sessionId) {
        tx.set(entitlementRef, {businessSubscriptionActive: false, subscriptionRenewsAt: null, downgradeReason: status, updatedAt: now}, {merge: true});
      }
      tx.update(sessionRef, {status, providerReference, updatedAt: now});
      return {accepted: true, applied: true, downgraded: true, sku};
    }
    if (status !== 'paid') return {accepted: true, applied: false, downgraded: false, sku};
    if (sku === 'biz_monthly_subscription') {
      patch.businessSubscriptionSourceSessionId = sessionId;
      patch.businessSubscriptionActive = true;
      patch.subscriptionStartedAt = now;
      const currentExpiry = ent.subscriptionRenewsAt instanceof admin.firestore.Timestamp ? ent.subscriptionRenewsAt.toMillis() : 0;
      patch.subscriptionRenewsAt = admin.firestore.Timestamp.fromMillis(Math.max(Date.now(), currentExpiry) + 30 * 86400000);
    }
    if (sku === 'biz_onetime_unlock' && ent.businessPurchased !== true) {patch.businessPurchased = true; patch.businessPurchasedSourceSessionId = sessionId;}
    if (sku === 'biz_onetime_unlock') patch.businessLifetimePaymentCount = Math.max(ent.businessPurchased === true ? 1 : 0, Number(ent.businessLifetimePaymentCount) || 0) + 1;
    if (sku === 'biz_onetime_unlock' || sku === 'biz_monthly_subscription') {patch.businessStoreUnlocked = true; patch.businessWalletUnlocked = true;}
    const topup = POINTS_TOPUP_BY_SKU[sku];
    if (topup) {
      const points = pointsSnap.data() || {};
      tx.set(pointsRef, {
        currentPoints: Math.max(0, Number(points.currentPoints) || 0) + topup.points,
        totalPoints: Math.max(0, Number(points.totalPoints) || 0) + topup.points,
        updatedAt: now, lastActivity: now,
      }, {merge: true});
      tx.set(pointsRef.collection('events').doc(sessionId), {
        eventId: sessionId, category: 'purchase_card_topup', amount: topup.points,
        reason: 'Card points top-up', sku, timestamp: now,
      });
    }
    tx.set(entitlementRef, patch, {merge: true});
    tx.create(invoiceRef, {
      invoiceId: sessionId, externalSessionId: sessionId, sku,
      amountPoints: topup?.points || 0, amountUsd: session.amountUsd,
      status: 'paid', paymentMethod: 'card_external', providerReference, createdAt: now,
    });
    tx.update(sessionRef, {status: 'paid', providerReference, providerPaymentId: args.paymentId || null, callbackReceivedAt: now, updatedAt: now,
      ...(sku === 'biz_onetime_unlock' ? {grantAddsLifetimeAccess: ent.businessPurchased !== true} : {}),
      ...(sku === 'biz_monthly_subscription' ? {previousSubscriptionExpiresAt: ent.subscriptionRenewsAt || null, previousSubscriptionSourceSessionId: ent.businessSubscriptionSourceSessionId || null, grantedSubscriptionExpiresAt: patch.subscriptionRenewsAt} : {})});
    tx.set(db.doc(`checkoutSessions/${sessionId}`), {uid, provider: 'square', providerPaymentId: args.paymentId || null, providerOrderId: args.orderId || session.providerOrderId || null, updatedAt: now}, {merge: true});
    return {accepted: true, applied: true, downgraded: false, sku};
  });
}

function amountUsdForSku(sku: string): number {
  if (sku === "biz_monthly_subscription") return monthlySubscriptionAmountUsd();
  if (sku === "biz_onetime_unlock") return 11.99;
  if (sku === "dev_card_test_charge") return 0.01;
  if (POINTS_TOPUP_BY_SKU[sku]) return POINTS_TOPUP_BY_SKU[sku].amountUsd;
  return 0;
}

function readBearerToken(authHeader: string | undefined): string {
  if (!authHeader) return "";
  const raw = authHeader.trim();
  if (!raw.toLowerCase().startsWith("bearer ")) return "";
  return raw.slice(7).trim();
}

async function verifyUserFromRequest(req: any): Promise<string> {
  const token = readBearerToken(req.header("authorization"));
  if (!token) return "";

  try {
    const decoded = await admin.auth().verifyIdToken(token, true);
    return decoded.uid ?? "";
  } catch (e) {
    logger.warn("external checkout auth failed", { error: String(e) });
    return "";
  }
}


export const createExternalCheckoutSession = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const uid = await verifyUserFromRequest(req);
  if (!uid) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  const sku = (req.body?.sku ?? "").toString().trim();
  const provider = normalizeProvider((req.body?.provider ?? "square").toString());
  const paymentMethodId = (req.body?.paymentMethodId ?? "").toString().trim();
  if (!VALID_SKUS.has(sku) || provider !== "square") {
    res.status(400).json({ error: "invalid_sku" });
    return;
  }

  if (sku === 'dev_card_test_charge' || sku === 'points_topup_1' ||
      (sku === 'biz_monthly_subscription' && parseBoolEnv('PROX_BIZ_MONTHLY_DEV_PRICE_ENABLED'))) {
    const account = await admin.auth().getUser(uid);
    if (account.email?.toLowerCase() !== 'marty.marola@hotmail.com' || !account.emailVerified) {
      res.status(403).json({error: 'preview_only'});
      return;
    }
  }
  if ((await db.doc(`accountDeletions/${uid}`).get()).exists) {
    res.status(403).json({error: 'account_deleting'});
    return;
  }
  if (sku === 'biz_monthly_subscription' || sku === 'biz_onetime_unlock') {
    const ent = (await db.doc(`users/${uid}/billing/entitlements`).get()).data() || {};
    const active = ent.businessSubscriptionActive === true && ent.subscriptionRenewsAt instanceof admin.firestore.Timestamp && ent.subscriptionRenewsAt.toMillis() > Date.now();
    if ((sku === 'biz_onetime_unlock' && ent.businessPurchased === true) || (sku === 'biz_monthly_subscription' && (active || ent.businessPurchased === true))) {
      res.status(409).json({error: 'business_access_already_owned'});
      return;
    }
  }
  const sessionRef = db
    .collection("users")
    .doc(uid)
    .collection("billing")
    .doc("externalCheckout")
    .collection("items")
    .doc();

  let checkoutUrl = "";
  let providerSessionId: string | null = null;
  let providerOrderId = "";
  try {
    const checkoutConfig = readRequiredCheckoutConfig();
    if (!checkoutConfig.ok) {
      logger.error("external checkout config missing required env vars", {
        missing: checkoutConfig.missing,
        provider,
        uid,
      });
      res.status(503).json({ error: "missing_checkout_config", missing: checkoutConfig.missing });
      return;
    }

    if (provider === "square") {
      const square = await createSquarePaymentLink({
        sessionId: sessionRef.id,
        sku,
        amountUsd: amountUsdForSku(sku),
      });
      checkoutUrl = square.checkoutUrl;
      providerSessionId = square.providerSessionId;
      providerOrderId = square.providerOrderId;
    } else {
      throw new Error("unsupported_payment_provider");
    }
  } catch (e) {
    const message = String(e);
    const isConfigError =
      message.includes("square_checkout_config_missing") ||
      message.includes("missing required env vars");
    const isSquareBadState =
      message.includes("square_checkout_create_failed") &&
      message.toUpperCase().includes("BAD_STATE");

    logger.error("external checkout session creation failed", {
      uid,
      sku,
      provider,
      error: message,
    });

    if (isConfigError) {
      res.status(503).json({
        error: "provider_checkout_unavailable",
        provider,
        reason: "provider_config_missing",
      });
      return;
    }

    if (isSquareBadState) {
      res.status(409).json({
        error: "provider_account_bad_state",
        provider,
        reason: "square_bad_state",
        detail: "Square account/location is not currently able to create checkout links.",
      });
      return;
    }

    res.status(502).json({
      error: "provider_checkout_failed",
      provider,
      reason: "provider_unavailable",
    });
    return;
  }

  const save = db.batch();
  save.set(sessionRef, {
    sessionId: sessionRef.id,
    uid,
    sku,
    provider,
    paymentMethodId: paymentMethodId || null,
    status: "session_created",
    amountUsd: amountUsdForSku(sku),
    checkoutUrl,
    providerSessionId,
    providerOrderId,
    providerReference: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  save.create(db.doc(`checkoutSessions/${sessionRef.id}`), {uid, provider, providerSessionId, providerOrderId, createdAt: admin.firestore.FieldValue.serverTimestamp()});
  await save.commit();

  if (sku === "biz_monthly_subscription" && amountUsdForSku(sku) === 0.01) {
    logger.warn("monthly subscription dev pricing toggle is enabled", {
      env: "PROX_BIZ_MONTHLY_DEV_PRICE_ENABLED",
      sku,
      amountUsd: 0.01,
    });
  }

  logger.info("external checkout session created", { uid, sku, provider, sessionId: sessionRef.id });

  res.status(200).json({
    ok: true,
    sessionId: sessionRef.id,
    sku,
    provider,
    paymentMethodId: paymentMethodId || null,
    checkoutUrl,
  });
});

// Legacy generic callbacks cannot provide verifiable payment evidence.
export const verifyExternalCheckoutCallback = onRequest(async (_req, res) => {
  res.status(410).json({error: 'use_signed_square_webhook'});
});

export const onSquareWebhookBridge = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  if (!verifySquareWebhookSignature(req)) {
    res.status(401).json({ error: "invalid_square_signature" });
    return;
  }

  const payload = req.body ?? {};
  const eventType = (payload.type ?? "").toString().trim();
  if (['refund.created', 'refund.updated', 'dispute.created', 'dispute.state.updated'].includes(eventType)) {
    try {
      const result = await reconcileSquareLifecycle(payload);
      res.status(200).json({ok: true, ...result});
    } catch (error) {
      logger.error('Square reconciliation failed', {eventType, error: String(error)});
      res.status(500).json({error: 'square_reconciliation_failed'});
    }
    return;
  }
  const mappedStatus = mapSquareEventToStatus(eventType, payload);
  if (!mappedStatus) {
    res.status(200).json({ ok: true, accepted: false, reason: "ignored_event_type", eventType });
    return;
  }

  const providerReference = (
    payload.event_id ?? payload.id ?? payload.data?.id ?? payload.data?.object?.payment?.id ?? ""
  ).toString().trim();

  const object = payload.data?.object ?? {};
  const payment = object.payment ?? {};
  const invoice = object.invoice ?? {};
  const subscription = object.subscription ?? {};

  const providerSessionId = (
    payment.payment_link_id ??
    invoice.payment_link_id ??
    subscription.payment_link_id ??
    ""
  ).toString().trim();

  let sessionId = "";
  const referenceCandidates = [
    payment.reference_id,
    invoice.reference_id,
    subscription.reference_id,
    payment.note,
  ];
  for (const candidate of referenceCandidates) {
    const parsed = parseSessionIdFromReferenceId((candidate ?? "").toString());
    if (parsed) {
      sessionId = parsed;
      break;
    }
  }

  const orderId = (
    payment.order_id ??
    invoice.order_id ??
    subscription.order_id ??
    ""
  ).toString().trim();

  if (!sessionId && orderId) {
    const orderReference = await fetchSquareOrderReferenceId(orderId);
    sessionId = parseSessionIdFromReferenceId(orderReference);
  }

  let resolved: { uid: string; sessionId: string } | null = null;
  if (sessionId) {
    resolved = await findSessionBySessionId(sessionId);
  }
  if (!resolved && providerSessionId) {
    resolved = await findSessionByProviderSessionId(providerSessionId);
  }

  if (!resolved) {
    logger.warn("square webhook could not resolve checkout session", {
      eventType,
      providerReference,
      providerSessionId,
      sessionId,
      orderId,
    });
    res.status(503).json({ ok: false, reason: "session_unresolved", eventType });
    return;
  }

  try {
    const applied = await applyExternalCheckoutStatus({
      uid: resolved.uid,
      sessionId: resolved.sessionId,
      status: mappedStatus,
      providerReference,
      callbackPayload: null,
      amountCents: Number(payment.amount_money?.amount),
      currency: String(payment.amount_money?.currency || ""),
      orderId: String(payment.order_id || ""),
      paymentId: String(payment.id || ""),
    });

    logger.info("square webhook processed", {
      eventType,
      mappedStatus,
      providerReference,
      uid: resolved.uid,
      sessionId: resolved.sessionId,
      applied: applied.applied,
      downgraded: applied.downgraded,
    });

    res.status(200).json({ ok: true, eventType, mappedStatus, ...applied });
  } catch (e) {
    logger.error("square webhook processing failed", {
      error: String(e),
      eventType,
      mappedStatus,
      providerReference,
      uid: resolved.uid,
      sessionId: resolved.sessionId,
    });
    res.status(500).json({ error: "square_webhook_processing_failed" });
  }
});
