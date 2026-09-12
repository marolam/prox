/**
 * Prox Cloud Functions entry
 */
import * as admin from "firebase-admin";
export { deleteMyAccount, onAuthDelete, onTrustFeedbackWrite } from './account_lifecycle';
export { purchaseWithPoints } from './points_purchases';
export { claimVerifiedReward, cancelMySubscription } from './verified_rewards';
export { onMeetupCompletedAccounting, syncCompletedMeetup } from './meetup_accounting';
export { onPartyWrite } from './lib/party';
export { onPublicProfileProjection, onPublicMatchingProjection } from './public_profiles';
export { setBusinessModeActive } from './business_mode';
export { onPresenceCoordinates } from './presence_projection';

if (admin.apps.length === 0) {
  admin.initializeApp();
}

// Push triggers (v1 style)
export { onNewChatMessage, onNewMatch, onMeetupUpdate } from "./lib/push";
export { onMatchPolicySeed, onMessagePolicyResolve, sweepActiveModePolicies } from "./lib/active_mode";
export { onAuthCreate } from "./on_auth_create";
export { recomputeDashboardMetrics } from "./dashboard_metrics";
export { onSupportTicketReward, onReferralMilestoneReward, onMutualPartyBridgeReward } from "./lib/rewards";
export { onPointsProgressionWrite } from "./lib/progression";
export { getActiveModeSweepHealth } from "./admin_observability";
export { runActiveModeSweepNow } from "./admin_observability";
export { onDashboardAnnouncementCreate, onBusinessSubscriptionCongratsParty } from "./creator_notifications";
export { onSupportTicketCreatedExportSheets } from "./support_sheets";
export { createExternalCheckoutSession, verifyExternalCheckoutCallback, onSquareWebhookBridge } from "./external_payments";
export { onInPartyMatchMetrics } from "./lib/in_party_match_metrics";
export { sweepMeetupAutoClose } from "./lib/meetup_auto_close";
export { sweepKeywordHygiene } from "./lib/keyword_hygiene";
export { onBugReportScoreFeedback, onSupportTicketScoreFeedback } from "./lib/tester_feedback_scoring";
export {
  createReferralSingleUseToken,
  referralApkDownload,
  finalizeReferralSingleUseToken,
  linkReferralCode,
} from "./referral_downloads";
