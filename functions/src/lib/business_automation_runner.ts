import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

type AutomationDoc = {
  automationId?: string;
  leadId?: string;
  threadId?: string;
  state?: string;
  step?: string;
  channel?: string;
  templateId?: string;
  scheduledAt?: admin.firestore.Timestamp;
};

function parseWebhook(raw: string | undefined): string {
  const v = String(raw ?? "").trim();
  if (!v) return "";
  try {
    const u = new URL(v);
    if (u.protocol !== "https:") return "";
    return u.toString();
  } catch (_) {
    return "";
  }
}

async function postJson(url: string, payload: unknown): Promise<boolean> {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    });
    return res.status >= 200 && res.status < 300;
  } catch (_) {
    return false;
  }
}

async function appendBusinessEvent(uid: string, payload: Record<string, unknown>): Promise<void> {
  await db
    .collection("users")
    .doc(uid)
    .collection("business")
    .doc("events")
    .collection("items")
    .add({
      ...payload,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

function userDocFromAutomationPath(path: string): string {
  const seg = path.split("/");
  // users/{uid}/business/automations/items/{automationId}
  if (seg.length < 6) return "";
  if (seg[0] !== "users") return "";
  return String(seg[1] ?? "").trim();
}

function isBusinessAutomationPath(path: string): boolean {
  return path.includes("/business/automations/items/");
}

async function deliverAutomation(params: {
  uid: string;
  leadId: string;
  step: string;
  channel: string;
  threadId: string;
}): Promise<"sent" | "fallback" | "failed"> {
  const smsWebhook = parseWebhook(process.env.PROX_SMS_WEBHOOK_URL);
  const emailWebhook = parseWebhook(process.env.PROX_EMAIL_WEBHOOK_URL);

  const payload = {
    uid: params.uid,
    leadId: params.leadId,
    threadId: params.threadId,
    step: params.step,
    channel: params.channel,
    sentAt: new Date().toISOString(),
  };

  const ch = params.channel.trim().toLowerCase();
  if (ch === "sms") {
    if (!smsWebhook) {
      await appendBusinessEvent(params.uid, {
        type: "business_automation_fallback",
        leadId: params.leadId,
        threadId: params.threadId,
        step: params.step,
        channel: "sms",
        fallbackChannel: "in_app",
      });
      return "fallback";
    }
    return (await postJson(smsWebhook, payload)) ? "sent" : "failed";
  }

  if (ch === "email") {
    if (!emailWebhook) {
      await appendBusinessEvent(params.uid, {
        type: "business_automation_fallback",
        leadId: params.leadId,
        threadId: params.threadId,
        step: params.step,
        channel: "email",
        fallbackChannel: "in_app",
      });
      return "fallback";
    }
    return (await postJson(emailWebhook, payload)) ? "sent" : "failed";
  }

  // Default in-app path.
  await appendBusinessEvent(params.uid, {
    type: "business_automation_sent",
    leadId: params.leadId,
    threadId: params.threadId,
    step: params.step,
    channel: "in_app",
  });
  return "sent";
}

export const runBusinessFollowupAutomation = onSchedule(
  {
    schedule: "every 2 minutes",
    region: "us-central1",
    timeZone: "Etc/UTC",
  },
  async () => {
    const now = admin.firestore.Timestamp.now();

    const query = await db
      .collectionGroup("items")
      .where("state", "==", "scheduled")
      .limit(300)
      .get();

    if (query.empty) {
      logger.info("business_automation_runner.noop");
      return;
    }

    let scanned = 0;
    let processed = 0;
    let sent = 0;
    let fallback = 0;
    let failed = 0;
    let skipped = 0;

    for (const doc of query.docs) {
      scanned++;
      const path = doc.ref.path;
      if (!isBusinessAutomationPath(path)) {
        skipped++;
        continue;
      }

      const uid = userDocFromAutomationPath(path);
      if (!uid) {
        skipped++;
        continue;
      }

      const data = doc.data() as AutomationDoc;
      const leadId = String(data.leadId ?? "").trim();
      const step = String(data.step ?? "").trim();
      const channel = String(data.channel ?? "in_app").trim();
      const threadId = String(data.threadId ?? "").trim();
      const scheduledAt = data.scheduledAt;

      if (!(scheduledAt instanceof admin.firestore.Timestamp)) {
        await doc.ref.set(
          {
            state: "skipped",
            skipReason: "missing_scheduledAt",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        skipped++;
        continue;
      }

      if (scheduledAt.toMillis() > now.toMillis()) {
        skipped++;
        continue;
      }

      if (!leadId || !step) {
        await doc.ref.set(
          {
            state: "skipped",
            skipReason: "missing_fields",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        skipped++;
        continue;
      }

      const delivery = await deliverAutomation({
        uid,
        leadId,
        step,
        channel,
        threadId,
      });

      if (delivery === "sent") {
        await doc.ref.set(
          {
            state: "sent",
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        await appendBusinessEvent(uid, {
          type: "business_followup_sent",
          leadId,
          threadId,
          step,
          channel,
        });
        sent++;
      } else if (delivery === "fallback") {
        await doc.ref.set(
          {
            state: "sent",
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            deliveryMode: "fallback_in_app",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        await appendBusinessEvent(uid, {
          type: "business_followup_sent",
          leadId,
          threadId,
          step,
          channel: "in_app",
          requestedChannel: channel,
          fallback: true,
        });
        fallback++;
      } else {
        await doc.ref.set(
          {
            state: "failed",
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        await appendBusinessEvent(uid, {
          type: "business_followup_failed",
          leadId,
          threadId,
          step,
          channel,
        });
        failed++;
      }

      processed++;
    }

    logger.info("business_automation_runner.summary", {
      scanned,
      processed,
      sent,
      fallback,
      failed,
      skipped,
    });
  }
);
