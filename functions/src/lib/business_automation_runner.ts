import * as admin from "firebase-admin";
import {createHash, randomUUID} from "node:crypto";
import * as logger from "firebase-functions/logger";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "./active_callable";
import {onSchedule} from "firebase-functions/v2/scheduler";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const stamp = () => admin.firestore.FieldValue.serverTimestamp();
const STEPS = new Set(["followup_15m", "followup_24h", "followup_72h"]);
const TERMINAL = new Set(["reminded", "sent", "review_required", "deduplicated"]);
const hash = (parts: string[]) => createHash("sha256").update(JSON.stringify(parts)).digest("hex");
const text = (value: unknown, max = 4000) => typeof value === "string" ? value.trim().slice(0, max) : "";
const id = (value: unknown) => /^[^/\s]{1,160}$/.test(text(value, 161)) ? text(value, 161) : "";

export function businessAutomationJobId(path: string): string {
  if (!/^users\/[^/]+\/business\/automations\/items\/[^/]+$/.test(path)) {
    throw new HttpsError("invalid-argument", "Invalid business automation path.");
  }
  return hash([path]);
}

export function businessAutomationReceiptId(uid: string, leadId: string, step: string): string {
  return hash([uid, leadId, step]);
}

function parseSource(path: string, data: admin.firestore.DocumentData | undefined) {
  const uid = path.split("/")[1];
  const leadId = id(data?.leadId);
  const step = text(data?.step, 30);
  const channel = text(data?.channel || "in_app", 20);
  const scheduledAt = data?.scheduledAt;
  if (!leadId || !STEPS.has(step) || !["in_app", "sms", "email"].includes(channel) ||
      !(scheduledAt instanceof admin.firestore.Timestamp)) return null;
  return {uid, leadId, step, channel, scheduledAt, threadId: id(data?.threadId),
    message: text(data?.templateMessage), messageSource: text(data?.templateMessageSource, 100)};
}

// Queue and receipts are server-owned. Owner-writable source documents never supply leases or receipts.
export async function syncBusinessAutomation(path: string): Promise<void> {
  const jobRef = db.doc(`businessAutomationJobs/${businessAutomationJobId(path)}`);
  const sourceRef = db.doc(path);
  const uid = path.split("/")[1];
  await db.runTransaction(async tx => {
    const [source, job, deletion] = await tx.getAll(sourceRef, jobRef, db.doc(`accountDeletions/${uid}`));
    if (deletion.exists) { if (job.exists) tx.delete(jobRef); return; }
    const parsed = parseSource(path, source.data());
    if (!source.exists || source.get("state") !== "scheduled" || !parsed || source.get("deletedAt") || source.get("deleted") === true) {
      if (job.exists && !TERMINAL.has(job.get("state"))) tx.set(jobRef, {state: "cancelled", updatedAt: stamp()}, {merge: true});
      return;
    }
    // Repeated source updates cannot reopen a sent job or steal an in-flight lease.
    if (job.exists && (TERMINAL.has(job.get("state")) || job.get("state") === "processing")) return;
    tx.set(jobRef, {uid, sourcePath: path, leadId: parsed.leadId, step: parsed.step,
      scheduledAt: parsed.scheduledAt, state: "scheduled", updatedAt: stamp()}, {merge: true});
  });
}

export const onBusinessAutomationWritten = onDocumentWritten({
  document: "users/{uid}/business/automations/items/{automationId}", region: "us-central1", retry: true,
}, async event => { if (event.data) await syncBusinessAutomation(event.data.after.ref.path); });

function hasPaidAccess(data: admin.firestore.DocumentData, now: number): boolean {
  return data.businessModeActive === true && (data.businessPurchased === true ||
    (data.businessSubscriptionActive === true && data.subscriptionRenewsAt instanceof admin.firestore.Timestamp &&
      data.subscriptionRenewsAt.toMillis() > now));
}

type Delivery = {uid: string; leadId: string; step: string; channel: string; threadId: string;
  message: string; messageSource: string; idempotencyKey: string};
type Transport = (url: string, payload: Delivery, token: string) => Promise<boolean>;
type ProcessOptions = {now?: number; transport?: Transport};

function provider(channel: string): {url: string; token: string} | null {
  const raw = channel === "sms" ? process.env.PROX_SMS_WEBHOOK_URL : process.env.PROX_EMAIL_WEBHOOK_URL;
  const token = text(process.env.PROX_BUSINESS_AUTOMATION_PROVIDER_TOKEN, 2000);
  if (!token) return null;
  try {
    const url = new URL(raw || "");
    if (url.protocol !== "https:" || url.username || url.password || !url.hostname ||
        url.hostname === "localhost" || /^(127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.)/.test(url.hostname)) return null;
    return {url: url.toString(), token};
  } catch { return null; }
}

async function post(url: string, payload: Delivery, token: string): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  try {
    const response = await fetch(url, {method: "POST", signal: controller.signal, redirect: "error",
      headers: {"content-type": "application/json", authorization: `Bearer ${token}`, "idempotency-key": payload.idempotencyKey},
      body: JSON.stringify(payload)});
    if (!response.ok) return false;
    const body = await response.json() as {accepted?: unknown; idempotencyKey?: unknown};
    return body.accepted === true && body.idempotencyKey === payload.idempotencyKey;
  } catch { return false; } finally { clearTimeout(timeout); }
}

// Returns bounded outcomes; no contact details or message bodies are logged.
export async function processBusinessAutomation(jobId: string, options: ProcessOptions = {}): Promise<string> {
  if (!/^[a-f0-9]{64}$/.test(jobId)) return "invalid_job";
  const jobRef = db.doc(`businessAutomationJobs/${jobId}`);
  const now = options.now ?? Date.now();
  const leaseToken = randomUUID();
  let delivery: Delivery | null = null;
  let connection: {url: string; token: string} | null = null;
  let sourcePath = "";
  let receiptId = "";
  const claimed = await db.runTransaction(async tx => {
    const [job, config] = await tx.getAll(jobRef, db.doc("businessAutomation/config"));
    if (!job.exists || !["scheduled", "processing"].includes(job.get("state"))) return "noop";
    if (config.get("enabled") !== true) return "disabled";
    sourcePath = text(job.get("sourcePath"), 500);
    if (!/^users\/[^/]+\/business\/automations\/items\/[^/]+$/.test(sourcePath) ||
        businessAutomationJobId(sourcePath) !== jobId) { tx.update(jobRef, {state: "blocked", reason: "invalid_source", updatedAt: stamp()}); return "blocked"; }
    const uid = sourcePath.split("/")[1];
    const [source, user, entitlement, deletion] = await tx.getAll(db.doc(sourcePath), db.doc(`users/${uid}`),
      db.doc(`users/${uid}/billing/entitlements`), db.doc(`accountDeletions/${uid}`));
    if (deletion.exists || !user.exists) { tx.delete(jobRef); return "deleted"; }
    const parsed = parseSource(sourcePath, source.data());
    if (!source.exists || source.get("state") !== "scheduled" || source.get("deletedAt") || source.get("deleted") === true || !parsed) {
      tx.update(jobRef, {state: "cancelled", updatedAt: stamp()}); return "cancelled";
    }
    if (parsed.scheduledAt.toMillis() > now) return "future";
    receiptId = businessAutomationReceiptId(uid, parsed.leadId, parsed.step);
    const receiptRef = db.doc(`businessAutomationReceipts/${receiptId}`);
    const [lead, receipt, consent] = await tx.getAll(db.doc(`users/${uid}/business/leads/items/${parsed.leadId}`),
      receiptRef, db.doc(`businessAutomationConsents/${hash([uid, parsed.leadId, parsed.channel])}`));
    if (!hasPaidAccess(entitlement.data() || {}, now) || !lead.exists || lead.get("deletedAt") ||
        lead.get("deleted") === true || ["won", "lost", "closed", "responded"].includes(text(lead.get("status"), 30))) {
      tx.update(jobRef, {state: "blocked", reason: "inactive_or_missing_lead", updatedAt: stamp()}); return "blocked";
    }
    if (receipt.exists) {
      if (receipt.get("state") === "dispatching") {
        const until = receipt.get("leaseUntil");
        if (until instanceof admin.firestore.Timestamp && until.toMillis() > now) return "leased";
        // A provider could have accepted a request before a worker crashed. Hold for review instead of resending.
        tx.update(receiptRef, {state: "review_required", reason: "expired_dispatch_lease", updatedAt: stamp()});
        tx.update(jobRef, {state: "review_required", updatedAt: stamp()});
        tx.update(source.ref, {state: "review_required", updatedAt: stamp()});
        return "review_required";
      }
      tx.update(jobRef, {state: "deduplicated", receiptId, updatedAt: stamp()});
      tx.update(source.ref, {state: "deduplicated", receiptId, updatedAt: stamp()});
      return "deduplicated";
    }
    if (parsed.channel === "in_app") {
      tx.create(receiptRef, {uid, leadId: parsed.leadId, step: parsed.step, state: "reminded", sourcePath, createdAt: stamp()});
      tx.set(db.doc(`users/${uid}/business/events/items/automation_${receiptId}`),
        {type: "business_followup_reminder", leadId: parsed.leadId, threadId: parsed.threadId,
          step: parsed.step, channel: "in_app", message: parsed.message, messageSource: parsed.messageSource,
          deliveryMode: "owner_reminder", createdAt: stamp()});
      tx.update(lead.ref, {followupReminderAt: stamp(), followupReminderMessage: parsed.message,
        followupReminderStep: parsed.step, updatedAt: stamp()});
      tx.update(jobRef, {state: "reminded", receiptId, updatedAt: stamp()});
      tx.update(source.ref, {state: "reminded", deliveryMode: "owner_reminder", receiptId, updatedAt: stamp()});
      return "reminded";
    }
    connection = provider(parsed.channel);
    if (config.get("outboundEnabled") !== true || config.get("providerIdempotency") !== true ||
        process.env.PROX_BUSINESS_AUTOMATION_OUTBOUND_ENABLED !== "true" || !connection || !parsed.message ||
        consent.get("allowed") !== true || consent.get("uid") !== uid || consent.get("leadId") !== parsed.leadId ||
        consent.get("channel") !== parsed.channel || consent.get("revokedAt")) {
      tx.update(jobRef, {state: "blocked", reason: "outbound_not_configured_or_consented", updatedAt: stamp()}); return "blocked";
    }
    delivery = {...parsed, idempotencyKey: receiptId};
    tx.create(receiptRef, {uid, leadId: parsed.leadId, step: parsed.step, state: "dispatching", sourcePath,
      leaseToken, leaseUntil: admin.firestore.Timestamp.fromMillis(now + 120000), createdAt: stamp()});
    tx.update(jobRef, {state: "processing", receiptId, leaseToken,
      scheduledAt: admin.firestore.Timestamp.fromMillis(now + 120000), updatedAt: stamp()});
    return "dispatching";
  });
  if (claimed !== "dispatching" || !delivery || !connection) return claimed;
  // Recheck cancellation, entitlement, deletion and protected consent immediately before contacting a provider.
  const outbound = delivery as Delivery;
  const settings = connection as {url: string; token: string};
  const [source, user, entitlement, deletion, consent, config, lead] = await db.getAll(db.doc(sourcePath), db.doc(`users/${outbound.uid}`),
    db.doc(`users/${outbound.uid}/billing/entitlements`), db.doc(`accountDeletions/${outbound.uid}`),
    db.doc(`businessAutomationConsents/${hash([outbound.uid, outbound.leadId, outbound.channel])}`), db.doc("businessAutomation/config"),
    db.doc(`users/${outbound.uid}/business/leads/items/${outbound.leadId}`));
  const latest = parseSource(sourcePath, source.data());
  const safe = source.exists && source.get("state") === "scheduled" && !source.get("deletedAt") && source.get("deleted") !== true && user.exists && !deletion.exists &&
    hasPaidAccess(entitlement.data() || {}, Date.now()) && consent.get("allowed") === true && !consent.get("revokedAt") &&
    consent.get("uid") === outbound.uid && consent.get("leadId") === outbound.leadId && consent.get("channel") === outbound.channel &&
    config.get("enabled") === true && config.get("outboundEnabled") === true && config.get("providerIdempotency") === true &&
    lead.exists && !lead.get("deletedAt") && lead.get("deleted") !== true &&
    !["won", "lost", "closed", "responded"].includes(text(lead.get("status"), 30)) &&
    latest?.leadId === outbound.leadId && latest.step === outbound.step && latest.channel === outbound.channel && latest.message === outbound.message;
  let accepted = false;
  if (safe) {
    try { accepted = await (options.transport || post)(settings.url, outbound, settings.token); } catch { /* Hold an ambiguous provider outcome. */ }
  }
  const outcome = accepted ? "sent" : safe ? "review_required" : "cancelled";
  await db.runTransaction(async tx => {
    const receiptRef = db.doc(`businessAutomationReceipts/${receiptId}`);
    const [receipt, currentSource, marker, currentJob, currentOwner] = await tx.getAll(receiptRef, db.doc(sourcePath),
      db.doc(`accountDeletions/${outbound.uid}`), jobRef, db.doc(`users/${outbound.uid}`));
    if (marker.exists) { if (receipt.exists) tx.delete(receiptRef); if (currentJob.exists) tx.delete(jobRef); return; }
    if (receipt.get("leaseToken") !== leaseToken || receipt.get("state") !== "dispatching") return;
    tx.update(receiptRef, {state: outcome, updatedAt: stamp(), leaseToken: admin.firestore.FieldValue.delete(),
      leaseUntil: admin.firestore.FieldValue.delete()});
    if (currentJob.exists) tx.update(jobRef, {state: outcome, updatedAt: stamp()});
    // Retain the protected receipt after a direct owner-document removal (dedup still matters), but do not recreate private activity.
    if (!currentOwner.exists) return;
    if (currentSource.exists && currentSource.get("state") === "scheduled") {
      tx.update(currentSource.ref, {state: outcome, deliveryMode: outbound.channel, updatedAt: stamp()});
    }
    if (accepted) tx.set(db.doc(`users/${outbound.uid}/business/events/items/automation_${receiptId}`),
      {type: "business_followup_sent", leadId: outbound.leadId, step: outbound.step, channel: outbound.channel, createdAt: stamp()});
  });
  return outcome;
}

export const configureBusinessAutomation = onCall({region: "us-central1"}, async request => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to configure automation.");
  if (request.auth.token.admin !== true) throw new HttpsError("permission-denied", "Administrator access required.");
  if (request.data?.expectedUid && request.data.expectedUid !== request.auth.uid) throw new HttpsError("failed-precondition", "Account changed.");
  const describe = (settings: admin.firestore.DocumentData) => ({
    enabled: settings.enabled === true, outboundEnabled: settings.outboundEnabled === true,
    providerIdempotency: settings.providerIdempotency === true,
    outboundDeploymentEnabled: process.env.PROX_BUSINESS_AUTOMATION_OUTBOUND_ENABLED === "true",
    providersConfigured: {sms: provider("sms") !== null, email: provider("email") !== null},
  });
  const keys = Object.keys(request.data || {}).filter(key => key !== "expectedUid");
  if (!keys.length) {
    return db.runTransaction(async tx => {
      const [config, deletion] = await tx.getAll(db.doc("businessAutomation/config"), db.doc(`accountDeletions/${request.auth!.uid}`));
      if (deletion.exists) throw new HttpsError("failed-precondition", "Account is being deleted.");
      return describe(config.data() || {});
    });
  }
  if (typeof request.data?.enabled !== "boolean" || typeof request.data?.outboundEnabled !== "boolean" ||
      typeof request.data?.providerIdempotency !== "boolean") throw new HttpsError("invalid-argument", "Choose all automation safeguards explicitly.");
  const settings = {enabled: request.data.enabled, outboundEnabled: request.data.outboundEnabled,
    providerIdempotency: request.data.providerIdempotency};
  if (settings.outboundEnabled && !settings.providerIdempotency) throw new HttpsError("failed-precondition", "An idempotent provider is required.");
  await db.runTransaction(async tx => {
    const deletion = await tx.get(db.doc(`accountDeletions/${request.auth!.uid}`));
    if (deletion.exists) throw new HttpsError("failed-precondition", "Account is being deleted.");
    tx.set(db.doc("businessAutomation/config"), {...settings, configuredBy: request.auth!.uid, updatedAt: stamp()});
  });
  return describe(settings);
});

export const runBusinessFollowupAutomation = onSchedule({schedule: "every 2 minutes", region: "us-central1",
  timeZone: "Etc/UTC", timeoutSeconds: 120, maxInstances: 1}, async () => {
  if ((await db.doc("businessAutomation/config").get()).get("enabled") !== true) return;
  let processed = 0;
  const deadline = Date.now() + 90000;
  for (const state of ["scheduled", "processing"]) {
    const jobs = await db.collection("businessAutomationJobs").where("state", "==", state)
      .where("scheduledAt", "<=", admin.firestore.Timestamp.now()).orderBy("scheduledAt").limit(50).get();
    for (const job of jobs.docs) {
      if (Date.now() >= deadline) break;
      await processBusinessAutomation(job.id);
      processed++;
    }
  }
  logger.info("business_automation_runner.summary", {processed});
});
