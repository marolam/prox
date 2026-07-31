"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onSupportTicketScoreFeedback = exports.onBugReportScoreFeedback = exports.sweepKeywordHygiene = exports.sweepMeetupAutoClose = exports.onInPartyMatchMetrics = exports.onSquareWebhookBridge = exports.verifyExternalCheckoutCallback = exports.createExternalCheckoutSession = exports.onSupportTicketCreatedExportSheets = exports.onBusinessSubscriptionCongratsParty = exports.onDashboardAnnouncementCreate = exports.runActiveModeSweepNow = exports.getActiveModeSweepHealth = exports.onPointsProgressionWrite = exports.onMutualPartyBridgeReward = exports.onReferralMilestoneReward = exports.onSupportTicketReward = exports.recomputeDashboardMetrics = exports.onAuthCreate = exports.sweepActiveModePolicies = exports.onMessagePolicyResolve = exports.onMatchPolicySeed = exports.onMeetupUpdate = exports.onNewMatch = exports.onNewChatMessage = void 0;
/**
 * Prox Cloud Functions entry
 */
const admin = __importStar(require("firebase-admin"));
if (admin.apps.length === 0) {
    admin.initializeApp();
}
// Push triggers (v1 style)
var push_1 = require("./lib/push");
Object.defineProperty(exports, "onNewChatMessage", { enumerable: true, get: function () { return push_1.onNewChatMessage; } });
Object.defineProperty(exports, "onNewMatch", { enumerable: true, get: function () { return push_1.onNewMatch; } });
Object.defineProperty(exports, "onMeetupUpdate", { enumerable: true, get: function () { return push_1.onMeetupUpdate; } });
var active_mode_1 = require("./lib/active_mode");
Object.defineProperty(exports, "onMatchPolicySeed", { enumerable: true, get: function () { return active_mode_1.onMatchPolicySeed; } });
Object.defineProperty(exports, "onMessagePolicyResolve", { enumerable: true, get: function () { return active_mode_1.onMessagePolicyResolve; } });
Object.defineProperty(exports, "sweepActiveModePolicies", { enumerable: true, get: function () { return active_mode_1.sweepActiveModePolicies; } });
var on_auth_create_1 = require("./on_auth_create");
Object.defineProperty(exports, "onAuthCreate", { enumerable: true, get: function () { return on_auth_create_1.onAuthCreate; } });
var dashboard_metrics_1 = require("./dashboard_metrics");
Object.defineProperty(exports, "recomputeDashboardMetrics", { enumerable: true, get: function () { return dashboard_metrics_1.recomputeDashboardMetrics; } });
var rewards_1 = require("./lib/rewards");
Object.defineProperty(exports, "onSupportTicketReward", { enumerable: true, get: function () { return rewards_1.onSupportTicketReward; } });
Object.defineProperty(exports, "onReferralMilestoneReward", { enumerable: true, get: function () { return rewards_1.onReferralMilestoneReward; } });
Object.defineProperty(exports, "onMutualPartyBridgeReward", { enumerable: true, get: function () { return rewards_1.onMutualPartyBridgeReward; } });
var progression_1 = require("./lib/progression");
Object.defineProperty(exports, "onPointsProgressionWrite", { enumerable: true, get: function () { return progression_1.onPointsProgressionWrite; } });
var admin_observability_1 = require("./admin_observability");
Object.defineProperty(exports, "getActiveModeSweepHealth", { enumerable: true, get: function () { return admin_observability_1.getActiveModeSweepHealth; } });
var admin_observability_2 = require("./admin_observability");
Object.defineProperty(exports, "runActiveModeSweepNow", { enumerable: true, get: function () { return admin_observability_2.runActiveModeSweepNow; } });
var creator_notifications_1 = require("./creator_notifications");
Object.defineProperty(exports, "onDashboardAnnouncementCreate", { enumerable: true, get: function () { return creator_notifications_1.onDashboardAnnouncementCreate; } });
Object.defineProperty(exports, "onBusinessSubscriptionCongratsParty", { enumerable: true, get: function () { return creator_notifications_1.onBusinessSubscriptionCongratsParty; } });
var support_sheets_1 = require("./support_sheets");
Object.defineProperty(exports, "onSupportTicketCreatedExportSheets", { enumerable: true, get: function () { return support_sheets_1.onSupportTicketCreatedExportSheets; } });
var external_payments_1 = require("./external_payments");
Object.defineProperty(exports, "createExternalCheckoutSession", { enumerable: true, get: function () { return external_payments_1.createExternalCheckoutSession; } });
Object.defineProperty(exports, "verifyExternalCheckoutCallback", { enumerable: true, get: function () { return external_payments_1.verifyExternalCheckoutCallback; } });
Object.defineProperty(exports, "onSquareWebhookBridge", { enumerable: true, get: function () { return external_payments_1.onSquareWebhookBridge; } });
var in_party_match_metrics_1 = require("./lib/in_party_match_metrics");
Object.defineProperty(exports, "onInPartyMatchMetrics", { enumerable: true, get: function () { return in_party_match_metrics_1.onInPartyMatchMetrics; } });
var meetup_auto_close_1 = require("./lib/meetup_auto_close");
Object.defineProperty(exports, "sweepMeetupAutoClose", { enumerable: true, get: function () { return meetup_auto_close_1.sweepMeetupAutoClose; } });
var keyword_hygiene_1 = require("./lib/keyword_hygiene");
Object.defineProperty(exports, "sweepKeywordHygiene", { enumerable: true, get: function () { return keyword_hygiene_1.sweepKeywordHygiene; } });
var tester_feedback_scoring_1 = require("./lib/tester_feedback_scoring");
Object.defineProperty(exports, "onBugReportScoreFeedback", { enumerable: true, get: function () { return tester_feedback_scoring_1.onBugReportScoreFeedback; } });
Object.defineProperty(exports, "onSupportTicketScoreFeedback", { enumerable: true, get: function () { return tester_feedback_scoring_1.onSupportTicketScoreFeedback; } });
//# sourceMappingURL=index.js.map