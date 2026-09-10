import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

const SWEEP_BATCH_SIZE = 300;
const TRUST_PENALTY_PER_INVALID = 0.75;
const TRUST_PENALTY_PER_DUPLICATE = 0.5;

const BUCKETS: readonly string[] = [
  "searchingFor",
  "canProvide",
  "privateSearchingFor",
  "privateCanProvide",
  "visibleInventory",
  "privateInventory",
  "satisfied",
  "removed",
] as const;

function normalizeKeyword(raw: unknown): string {
  if (typeof raw !== "string") return "";
  return raw.trim().toLowerCase().replace(/\s+/g, " ");
}

function validateKeyword(raw: unknown): { normalized: string; valid: boolean } {
  const normalized = normalizeKeyword(raw);
  if (!normalized) return { normalized, valid: false };
  if (normalized.length > 42) return { normalized, valid: false };
  if (/\d/.test(normalized)) return { normalized, valid: false };

  const parts = normalized.split(" ").filter(Boolean);
  if (parts.length === 0 || parts.length > 3) return { normalized, valid: false };

  for (const part of parts) {
    if (!/^[a-z][a-z'-]{1,23}$/.test(part)) return { normalized, valid: false };
    if (/(.)\1\1/.test(part)) return { normalized, valid: false };
  }

  return { normalized, valid: true };
}

type BucketItem = { value: string; status: string };

type SweepOutcome = {
  changed: boolean;
  workspace: Record<string, BucketItem[]>;
  activeKeywords: string[];
  invalidRemoved: number;
  duplicateRemoved: number;
  qualityScore: number;
  trustPenalty: number;
};

function sanitizeWorkspace(raw: unknown): SweepOutcome {
  const workspace: Record<string, BucketItem[]> = {};
  const seen = new Set<string>();
  let invalidRemoved = 0;
  let duplicateRemoved = 0;

  for (const bucket of BUCKETS) {
    const rawList = (raw as Record<string, unknown> | undefined)?.[bucket];
    const next: BucketItem[] = [];

    if (Array.isArray(rawList)) {
      for (const entry of rawList) {
        const value = typeof entry === "object" && entry !== null ? (entry as Record<string, unknown>).value : entry;
        const statusRaw =
          typeof entry === "object" && entry !== null ? (entry as Record<string, unknown>).status : "clear";
        const status = typeof statusRaw === "string" ? statusRaw : "clear";

        const validated = validateKeyword(value);
        if (!validated.valid) {
          invalidRemoved += 1;
          continue;
        }
        if (seen.has(validated.normalized)) {
          duplicateRemoved += 1;
          continue;
        }

        seen.add(validated.normalized);
        next.push({ value: validated.normalized, status });
      }
    }

    workspace[bucket] = next;
  }

  const activeKeywords = [
    ...workspace.searchingFor
      .filter((x) => x.status === "clear" || x.status === "working")
      .map((x) => x.value),
    ...workspace.canProvide
      .filter((x) => x.status === "clear" || x.status === "working")
      .map((x) => x.value),
  ];

  const totalIssues = invalidRemoved + duplicateRemoved;
  const qualityScore = Math.max(0, 100 - invalidRemoved * 10 - duplicateRemoved * 6);
  const trustPenalty = Number(
    (invalidRemoved * TRUST_PENALTY_PER_INVALID + duplicateRemoved * TRUST_PENALTY_PER_DUPLICATE).toFixed(2),
  );

  return {
    changed: totalIssues > 0,
    workspace,
    activeKeywords,
    invalidRemoved,
    duplicateRemoved,
    qualityScore,
    trustPenalty,
  };
}

export const sweepKeywordHygiene = functions.pubsub
  .schedule("every 24 hours")
  .timeZone("UTC")
  .onRun(async () => {
    let scanned = 0;
    let changed = 0;
    let totalInvalidRemoved = 0;
    let totalDuplicateRemoved = 0;

    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    do {
      let query = db.collection("users").orderBy(admin.firestore.FieldPath.documentId()).limit(SWEEP_BATCH_SIZE);
      if (cursor) {
        query = query.startAfter(cursor.id);
      }

      const snap = await query.get();
      if (snap.empty) break;

      const batch = db.batch();

      for (const userDoc of snap.docs) {
        scanned += 1;
        const uid = userDoc.id;
        const userData = userDoc.data() || {};

        const sanitized = sanitizeWorkspace(userData.keywordWorkspace);
        if (!sanitized.changed) continue;

        changed += 1;
        totalInvalidRemoved += sanitized.invalidRemoved;
        totalDuplicateRemoved += sanitized.duplicateRemoved;

        const usersRef = db.collection("users").doc(uid);
        const profilesRef = db.collection("profiles").doc(uid);
        const pointsRef = usersRef.collection("meta").doc("points");

        batch.set(
          usersRef,
          {
            keywordWorkspace: sanitized.workspace,
            searchingFor: sanitized.activeKeywords,
            activeKeywords: sanitized.activeKeywords,
            keywordQuality: {
              score: sanitized.qualityScore,
              invalidRemoved: sanitized.invalidRemoved,
              duplicateRemoved: sanitized.duplicateRemoved,
              trustPenalty: sanitized.trustPenalty,
              lastKeywordHygieneAt: admin.firestore.FieldValue.serverTimestamp(),
              source: "scheduledSweep",
            },
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        batch.set(
          profilesRef,
          {
            keywordWorkspace: sanitized.workspace,
            activeKeywords: sanitized.activeKeywords,
            keywordQuality: {
              score: sanitized.qualityScore,
              invalidRemoved: sanitized.invalidRemoved,
              duplicateRemoved: sanitized.duplicateRemoved,
              trustPenalty: sanitized.trustPenalty,
              lastKeywordHygieneAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        batch.set(
          pointsRef,
          {
            keywordTrustPenalty: sanitized.trustPenalty,
            keywordQualityScore: sanitized.qualityScore,
            keywordQualityInvalidCount: sanitized.invalidRemoved,
            keywordQualityDuplicateCount: sanitized.duplicateRemoved,
            keywordQualityUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            trustScore: admin.firestore.FieldValue.increment(-sanitized.trustPenalty),
            trustPercent: admin.firestore.FieldValue.increment(-sanitized.trustPenalty),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      await batch.commit();
      cursor = snap.docs[snap.docs.length - 1];
    } while (true);

    await db.collection("dashboard").doc("keywordHygiene").set(
      {
        scanned,
        changed,
        totalInvalidRemoved,
        totalDuplicateRemoved,
        lastSweepAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return null;
  });
