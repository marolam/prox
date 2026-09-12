import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

type ScoreBreakdown = {
  reproSteps: number;
  expectedVsActual: number;
  evidence: number;
  timeline: number;
  severity: number;
  total: number;
};

function clampInt(v: number, min: number, max: number): number {
  const n = Number.isFinite(v) ? Math.round(v) : 0;
  return Math.max(min, Math.min(max, n));
}

function normalizeUid(raw: unknown): string {
  const uid = String(raw ?? "").trim();
  if (!uid || uid.toLowerCase() === "anon") return "";
  return uid;
}

function hasTimelineSignal(text: string): boolean {
  const t = text.toLowerCase();
  return /\b\d{1,2}:\d{2}\b/.test(t) || t.includes("timeline") || t.includes("timestamp") || t.includes("hh:mm");
}

function scoreTextArtifact(args: {
  text: string;
  hasEvidence: boolean;
  hasTimelineSignal: boolean;
  hasSeveritySignal: boolean;
}): ScoreBreakdown {
  const text = args.text.trim();
  const lower = text.toLowerCase();

  let repro = 0;
  const hasStepWord =
    lower.includes("step") ||
    lower.includes("repro") ||
    lower.includes("tap") ||
    lower.includes("open") ||
    lower.includes("press");
  const numberedSteps = /(^|\n)\s*(\d+\.|- )/m.test(text);
  if (text.length >= 30) repro += 8;
  if (text.length >= 120) repro += 8;
  if (hasStepWord) repro += 5;
  if (numberedSteps) repro += 7;
  repro = clampInt(repro, 0, 25);

  let expected = 0;
  const expectedWords = ["expected", "actual", "instead", "happened", "should", "but"];
  let expectedHits = 0;
  for (const w of expectedWords) {
    if (lower.includes(w)) expectedHits += 1;
  }
  expected += expectedHits * 5;
  expected = clampInt(expected, 0, 25);

  let evidence = args.hasEvidence ? 18 : 0;
  if (args.hasEvidence && text.length >= 80) evidence += 7;
  evidence = clampInt(evidence, 0, 25);

  let timeline = args.hasTimelineSignal ? 10 : 0;
  if (args.hasTimelineSignal && numberedSteps) timeline += 5;
  timeline = clampInt(timeline, 0, 15);

  let severity = args.hasSeveritySignal ? 8 : 0;
  if (
    lower.includes("blocker") ||
    lower.includes("critical") ||
    lower.includes("high") ||
    lower.includes("medium") ||
    lower.includes("low")
  ) {
    severity += 2;
  }
  severity = clampInt(severity, 0, 10);

  const total = clampInt(repro + expected + evidence + timeline + severity, 0, 100);

  return {
    reproSteps: repro,
    expectedVsActual: expected,
    evidence,
    timeline,
    severity,
    total,
  };
}

function compareBreakdown(a: ScoreBreakdown, b: ScoreBreakdown): boolean {
  return (
    a.reproSteps === b.reproSteps &&
    a.expectedVsActual === b.expectedVsActual &&
    a.evidence === b.evidence &&
    a.timeline === b.timeline &&
    a.severity === b.severity &&
    a.total === b.total
  );
}

function parseBreakdown(raw: unknown, fallbackTotal: number): ScoreBreakdown {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    reproSteps: clampInt(Number(r["reproSteps"] ?? 0), 0, 25),
    expectedVsActual: clampInt(Number(r["expectedVsActual"] ?? 0), 0, 25),
    evidence: clampInt(Number(r["evidence"] ?? 0), 0, 25),
    timeline: clampInt(Number(r["timeline"] ?? 0), 0, 15),
    severity: clampInt(Number(r["severity"] ?? 0), 0, 10),
    total: clampInt(fallbackTotal, 0, 100),
  };
}

async function recomputeTesterStats(uid: string): Promise<void> {
  const bugCountAgg = await db.collection("bugReports").where("actor", "==", uid).count().get();
  const evidenceBugCountAgg = await db
    .collection("bugReports")
    .where("actor", "==", uid)
    .where("hasEvidence", "==", true)
    .count()
    .get();
  const helpfulAgg = await db
    .collection("support_tickets")
    .where("testerUid", "==", uid)
    .where("thumbsUp", "==", true)
    .count()
    .get();

  const bugScoresSnap = await db
    .collection("bugReports")
    .where("actor", "==", uid)
    .orderBy("feedbackScoredAt", "desc")
    .limit(120)
    .get();

  const supportScoresSnap = await db
    .collection("support_tickets")
    .where("testerUid", "==", uid)
    .orderBy("feedbackScoredAt", "desc")
    .limit(120)
    .get();

  let scoreSum = 0;
  let scoreCount = 0;

  for (const d of bugScoresSnap.docs) {
    const s = d.data()["feedbackScore100"];
    if (typeof s === "number" && s >= 0) {
      scoreSum += s;
      scoreCount += 1;
    }
  }

  for (const d of supportScoresSnap.docs) {
    const s = d.data()["feedbackScore100"];
    if (typeof s === "number" && s >= 0) {
      scoreSum += s;
      scoreCount += 1;
    }
  }

  const score = scoreCount > 0 ? clampInt(scoreSum / scoreCount, 0, 100) : 0;

  await db.collection("users").doc(uid).collection("stats").doc("current").set(
    {
      bugsReported: bugCountAgg.data().count,
      evidenceReports: evidenceBugCountAgg.data().count,
      feedbackHelpfulVotes: helpfulAgg.data().count,
      feedbackScore100: score,
      feedbackScoreSamples: scoreCount,
      feedbackScoreUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

export const onBugReportScoreFeedback = onDocumentWritten("bugReports/{reportId}", async (event) => {
  const after = event.data?.after;
  if (!after?.exists) return;

  const data = after.data() ?? {};
  const uid = normalizeUid(data["actor"]);
  if (!uid) return;

  const note = String(data["note"] ?? "").trim();
  const route = String(data["route"] ?? "").trim();
  const localTs = String(data["localTs"] ?? "").trim();

  const hasEvidence = String(data["screenshotUrl"] ?? "").trim().length > 0;
  const timelineSignal = localTs.length > 0 || hasTimelineSignal(note);
  const severitySignal =
    String(data["severity"] ?? "").trim().length > 0 ||
    String(data["type"] ?? "").trim().length > 0 ||
    String(data["scope"] ?? "").trim().length > 0;

  const text = `${note}\nroute:${route}`;
  const scored = scoreTextArtifact({
    text,
    hasEvidence,
    hasTimelineSignal: timelineSignal,
    hasSeveritySignal: severitySignal,
  });

  const prevScore = data["feedbackScore100"];
  const prevHasEvidence = data["hasEvidence"];
  const prevBreakdown = data["feedbackScoreBreakdown"];

  let shouldWrite = true;
  if (typeof prevScore === "number" && typeof prevHasEvidence === "boolean" && prevBreakdown && typeof prevBreakdown === "object") {
    const old = parseBreakdown(prevBreakdown, prevScore);
    if (old.total === scored.total && prevHasEvidence === hasEvidence && compareBreakdown(old, scored)) {
      shouldWrite = false;
    }
  }

  if (shouldWrite) {
    await after.ref.set(
      {
        testerUid: uid,
        hasEvidence,
        feedbackScore100: scored.total,
        feedbackScoreBreakdown: {
          reproSteps: scored.reproSteps,
          expectedVsActual: scored.expectedVsActual,
          evidence: scored.evidence,
          timeline: scored.timeline,
          severity: scored.severity,
        },
        feedbackScoredAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  await recomputeTesterStats(uid);
  logger.info("bug report feedback scored", { reportId: event.params.reportId, uid, score: scored.total });
});

export const onSupportTicketScoreFeedback = onDocumentWritten("support_tickets/{ticketId}", async (event) => {
  const after = event.data?.after;
  if (!after?.exists) return;

  const data = after.data() ?? {};
  const uid = normalizeUid(data["uid"] ?? data["ownerUid"] ?? data["userId"]);
  if (!uid) return;

  const subject = String(data["subject"] ?? data["title"] ?? "").trim();
  const body = String(data["body"] ?? data["description"] ?? data["message"] ?? "").trim();
  const route = String(data["route"] ?? "").trim();
  const text = `${subject}\n${body}\n${route}`;

  const attachmentsCount = Number(data["attachmentsCount"] ?? 0);
  const hasEvidence =
    String(data["screenshotUrl"] ?? "").trim().length > 0 ||
    (Number.isFinite(attachmentsCount) && attachmentsCount > 0);

  const timelineSignal = hasTimelineSignal(text) || String(data["createdAt"] ?? "").trim().length > 0;
  const severitySignal =
    String(data["priority"] ?? "").trim().length > 0 ||
    String(data["severity"] ?? "").trim().length > 0 ||
    String(data["category"] ?? "").trim().length > 0;

  const scored = scoreTextArtifact({
    text,
    hasEvidence,
    hasTimelineSignal: timelineSignal,
    hasSeveritySignal: severitySignal,
  });

  const prevScore = data["feedbackScore100"];
  if (!(typeof prevScore === "number" && clampInt(prevScore, 0, 100) === scored.total)) {
    await after.ref.set(
      {
        testerUid: uid,
        feedbackScore100: scored.total,
        feedbackScoreBreakdown: {
          reproSteps: scored.reproSteps,
          expectedVsActual: scored.expectedVsActual,
          evidence: scored.evidence,
          timeline: scored.timeline,
          severity: scored.severity,
        },
        feedbackScoredAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  await recomputeTesterStats(uid);
  logger.info("support ticket feedback scored", { ticketId: event.params.ticketId, uid, score: scored.total });
});
