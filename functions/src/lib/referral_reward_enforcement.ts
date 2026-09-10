import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

type ReferralDoc = Record<string, unknown>;

function asMap(v: unknown): ReferralDoc {
  if (v && typeof v === "object") return v as ReferralDoc;
  return {};
}

function asBool(v: unknown): boolean {
  return v === true;
}

export const onReferralRewardEnforcement = functions.firestore
  .document("users/{referrerUid}/referrals/{inviteeUid}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return;

    const before = asMap(change.before.data());
    const after = asMap(change.after.data());

    const rewardEligible = asBool(after["rewardEligible"]);
    const inPersonVerified = asBool(after["inPersonVerified"]);

    const grantRequested = asBool(after["rewardGranted"]);
    const creditRequested = asBool(after["rewardCredited"]);

    // Enforce verified-only rewards. If anyone tries to set reward flags early,
    // roll them back to previous values (or false for creates) and stamp policy metadata.
    const invalidRewardMutation = (grantRequested || creditRequested) && (!rewardEligible || !inPersonVerified);
    if (!invalidRewardMutation) return;

    const fallbackGranted = asBool(before["rewardGranted"]);
    const fallbackCredited = asBool(before["rewardCredited"]);

    await change.after.ref.set(
      {
        rewardGranted: fallbackGranted,
        rewardCredited: fallbackCredited,
        rewardPolicy: {
          blockedAt: admin.firestore.FieldValue.serverTimestamp(),
          blockedReason: "verified_only_referral_rewards",
          blockedRequestedGranted: grantRequested,
          blockedRequestedCredited: creditRequested,
          rewardEligible,
          inPersonVerified,
          blockedByFunction: "onReferralRewardEnforcement",
          referrerUid: String(context.params.referrerUid ?? "").trim(),
          inviteeUid: String(context.params.inviteeUid ?? "").trim(),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
