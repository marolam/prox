import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

const webhookUrl = (process.env.SUPPORT_SHEETS_WEBHOOK_URL || "").trim();

async function postToSheets(payload: Record<string, unknown>): Promise<void> {
  if (!webhookUrl) {
    logger.info("support_sheets webhook not configured; skipping export");
    return;
  }

  const c = new AbortController();
  const timer = setTimeout(() => c.abort(), 8000);
  try {
    const res = await fetch(webhookUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
      signal: c.signal,
    });

    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Sheets webhook failed status=${res.status} body=${text.slice(0, 300)}`);
    }
  } finally {
    clearTimeout(timer);
  }
}

export const onSupportTicketCreatedExportSheets = onDocumentCreated(
  "support_tickets/{ticketId}",
  async (event) => {
    const after = event.data;
    if (!after?.exists) return;

    const d = after.data() ?? {};
    const payload: Record<string, unknown> = {
      ticketId: event.params.ticketId,
      uid: d.uid ?? d.ownerUid ?? d.userId ?? "",
      category: d.category ?? d.type ?? "",
      priority: d.priority ?? "",
      status: d.status ?? "new",
      subject: d.subject ?? d.title ?? "",
      body: d.body ?? d.description ?? d.message ?? "",
      route: d.route ?? "",
      platform: d.platform ?? "",
      appVersion: d.appVersion ?? "",
      createdAt: Date.now(),
    };

    try {
      await postToSheets(payload);
      logger.info("support ticket exported to sheets", {
        ticketId: event.params.ticketId,
      });
    } catch (e) {
      logger.error("support ticket sheets export failed", {
        ticketId: event.params.ticketId,
        error: e,
      });
    }
  },
);
