import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

function tsNow() {
  return admin.firestore.FieldValue.serverTimestamp();
}

function uniqStrings(input: string[]): string[] {
  return Array.from(new Set(input.map((s) => String(s || "").trim()).filter(Boolean)));
}

function matchParticipants(data: Record<string, unknown>): string[] {
  if (Array.isArray(data.participants)) {
    return uniqStrings(data.participants.map((x) => String(x || "")));
  }
  if (Array.isArray(data.userIds)) {
    return uniqStrings(data.userIds.map((x) => String(x || "")));
  }
  const a = String(data.aUid ?? "").trim();
  const b = String(data.bUid ?? "").trim();
  return uniqStrings([a, b]);
}

function dayKeyUtc(ms: number): string {
  const d = new Date(ms);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${dd}`;
}

function stablePairKey(a: string, b: string): string {
  return [a.trim(), b.trim()].sort().join("__");
}

type PairEval = {
  a: string;
  b: string;
  pairKey: string;
  aInParty: boolean;
  bInParty: boolean;
};

async function evaluatePair(a: string, b: string): Promise<PairEval> {
  const db = admin.firestore();
  const aRef = db.doc(`users/${a}/party/${b}`);
  const bRef = db.doc(`users/${b}/party/${a}`);
  const [aSnap, bSnap] = await Promise.all([aRef.get(), bRef.get()]);

  return {
    a,
    b,
    pairKey: stablePairKey(a, b),
    aInParty: aSnap.exists,
    bInParty: bSnap.exists,
  };
}

export const onInPartyMatchMetrics = onDocumentCreated("matches/{matchId}", async (event) => {
  const matchId = String(event.params.matchId ?? "").trim();
  if (!matchId) return;

  const data = event.data?.data() ?? {};
  const users = matchParticipants(data as Record<string, unknown>);
  if (users.length < 2) return;

  const pairs: Array<Promise<PairEval>> = [];
  for (let i = 0; i < users.length; i += 1) {
    for (let j = i + 1; j < users.length; j += 1) {
      pairs.push(evaluatePair(users[i], users[j]));
    }
  }

  const evals = await Promise.all(pairs);
  const qualifying = evals.filter((p) => p.aInParty || p.bInParty);
  if (!qualifying.length) return;

  const nowMs = Date.now();
  const day = dayKeyUtc(nowMs);
  const db = admin.firestore();

  await db.runTransaction(async (tx) => {
    const references: FirebaseFirestore.DocumentReference[] = [];
    for (const uid of users) references.push(db.doc(`accountDeletions/${uid}`));
    for (const p of qualifying) {
      references.push(db.doc(`analytics/inPartyMatchMetrics/pairs/${p.pairKey}/matches/${matchId}`));
      if (p.aInParty) references.push(db.doc(`users/${p.a}/meta/inPartyMatchMetrics/events/${matchId}__${p.b}`));
      if (p.bInParty) references.push(db.doc(`users/${p.b}/meta/inPartyMatchMetrics/events/${matchId}__${p.a}`));
      if (p.aInParty) references.push(db.doc(`users/${p.a}/meta/inPartyMatchMetrics/uniquePairs/${p.b}`));
      if (p.bInParty) references.push(db.doc(`users/${p.b}/meta/inPartyMatchMetrics/uniquePairs/${p.a}`));
    }
    const snapshots = await tx.getAll(...references);
    const byPath = new Map(snapshots.map(snapshot => [snapshot.ref.path, snapshot]));
    let userSideIncrements = 0;
    let pairIncrements = 0;
    let oneSidedPairs = 0;
    let twoSidedPairs = 0;

    for (const p of qualifying) {
      if (byPath.get(`accountDeletions/${p.a}`)?.exists || byPath.get(`accountDeletions/${p.b}`)?.exists) continue;
      const pairRef = db.doc(`analytics/inPartyMatchMetrics/pairs/${p.pairKey}/matches/${matchId}`);
      const pairSnap = byPath.get(pairRef.path)!;
      if (!pairSnap.exists) {
        tx.set(
          pairRef,
          {
            matchId,
            pairKey: p.pairKey,
            aUid: p.a,
            bUid: p.b,
            aInParty: p.aInParty,
            bInParty: p.bInParty,
            createdAt: tsNow(),
            updatedAt: tsNow(),
          },
          { merge: true },
        );
        pairIncrements += 1;
        if (p.aInParty && p.bInParty) {
          twoSidedPairs += 1;
        } else {
          oneSidedPairs += 1;
        }
      }

      if (p.aInParty) {
        const eventRef = db.doc(`users/${p.a}/meta/inPartyMatchMetrics/events/${matchId}__${p.b}`);
        const eventSnap = byPath.get(eventRef.path)!;
        if (!eventSnap.exists) {
          tx.set(
            eventRef,
            {
              matchId,
              otherUid: p.b,
              pairKey: p.pairKey,
              countedAt: tsNow(),
              updatedAt: tsNow(),
            },
            { merge: true },
          );
          tx.set(
            db.doc(`users/${p.a}/meta/inPartyMatchMetrics`),
            {
              totalInPartyMatches: admin.firestore.FieldValue.increment(1),
              uniquePairs: admin.firestore.FieldValue.increment(byPath.get(`users/${p.a}/meta/inPartyMatchMetrics/uniquePairs/${p.b}`)?.exists ? 0 : 1),
              lastMatchId: matchId,
              lastOtherUid: p.b,
              updatedAt: tsNow(),
            },
            { merge: true },
          );
          tx.set(db.doc(`users/${p.a}/meta/inPartyMatchMetrics/uniquePairs/${p.b}`), {otherUid: p.b, firstCountedAt: tsNow()}, {merge: true});
          userSideIncrements += 1;
        }
      }

      if (p.bInParty) {
        const eventRef = db.doc(`users/${p.b}/meta/inPartyMatchMetrics/events/${matchId}__${p.a}`);
        const eventSnap = byPath.get(eventRef.path)!;
        if (!eventSnap.exists) {
          tx.set(
            eventRef,
            {
              matchId,
              otherUid: p.a,
              pairKey: p.pairKey,
              countedAt: tsNow(),
              updatedAt: tsNow(),
            },
            { merge: true },
          );
          tx.set(
            db.doc(`users/${p.b}/meta/inPartyMatchMetrics`),
            {
              totalInPartyMatches: admin.firestore.FieldValue.increment(1),
              uniquePairs: admin.firestore.FieldValue.increment(byPath.get(`users/${p.b}/meta/inPartyMatchMetrics/uniquePairs/${p.a}`)?.exists ? 0 : 1),
              lastMatchId: matchId,
              lastOtherUid: p.a,
              updatedAt: tsNow(),
            },
            { merge: true },
          );
          tx.set(db.doc(`users/${p.b}/meta/inPartyMatchMetrics/uniquePairs/${p.a}`), {otherUid: p.a, firstCountedAt: tsNow()}, {merge: true});
          userSideIncrements += 1;
        }
      }
    }

    if (userSideIncrements > 0 || pairIncrements > 0) {
      const dailyRef = db.doc(`analytics/inPartyMatchMetrics/daily/${day}`);
      tx.set(
        dailyRef,
        {
          date: day,
          userSideMatches: admin.firestore.FieldValue.increment(userSideIncrements),
          pairMatches: admin.firestore.FieldValue.increment(pairIncrements),
          oneSidedPairs: admin.firestore.FieldValue.increment(oneSidedPairs),
          twoSidedPairs: admin.firestore.FieldValue.increment(twoSidedPairs),
          updatedAt: tsNow(),
        },
        { merge: true },
      );
    }
  });

  logger.info("in-party match metrics updated", {
    matchId,
    participants: users.length,
    qualifyingPairs: qualifying.length,
  });
});
