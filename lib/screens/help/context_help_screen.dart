import "package:flutter/material.dart";

class ContextHelpScreen extends StatelessWidget {
  const ContextHelpScreen({
    super.key,
    required this.routeName,
    this.contextKey,
  });

  final String routeName;
  final String? contextKey;

  static const String supportRoute = "/support";

  static const Map<String, _HelpContent> _contextHelp = <String, _HelpContent>{
    "home:nearby": _HelpContent(
      title: "Nearby",
      summary: "Nearby shows people around you who are currently discoverable.",
      tutorialSteps: <String>[
        "Confirm location access is enabled.",
        "Adjust discovery radius/mode to your current goal.",
        "Open a match card to start chat and move toward meetup.",
      ],
      tips: <String>[
        "Smaller radius often improves local relevance.",
        "If feed looks empty, try Public Mode and refresh nearby.",
      ],
    ),
    "home:matches": _HelpContent(
      title: "Matches",
      summary: "Matches is your active conversation and conversion pipeline.",
      tutorialSteps: <String>[
        "Open a thread and send a clear first message.",
        "Confirm mutual intent before proposing meetup details.",
        "Escalate to meetup planning when conversation is warm.",
      ],
      tips: <String>[
        "Short, specific openers get faster responses.",
        "Capture blockers and route them to Support if recurring.",
      ],
    ),
    "home:meetups": _HelpContent(
      title: "Meetups",
      summary: "Meetups tracks planning, live coordination, completion, and ratings.",
      tutorialSteps: <String>[
        "Open meetup details and confirm time/place.",
        "Use live flow while traveling/arriving.",
        "Submit rating after completion to close trust loop.",
      ],
      tips: <String>[
        "ETA updates reduce no-show risk.",
        "Ratings improve downstream match quality.",
      ],
    ),
    "home:party": _HelpContent(
      title: "Party",
      summary: "Party shows trusted connections and mutual relationship progress.",
      tutorialSteps: <String>[
        "Review current party members and status.",
        "Verify mutual indicators after successful meetups.",
        "Use party scope controls for safer discovery paths.",
      ],
      tips: <String>[
        "Mutual links are high-signal for reliability.",
        "Use party context to prioritize proven contacts.",
      ],
    ),
    "home:modes": _HelpContent(
      title: "Modes",
      summary: "Modes controls how discovery runs: normal, treasure, travel, or off.",
      tutorialSteps: <String>[
        "Choose a mode matching your current intent.",
        "Tune radius for each mode when available.",
        "Validate behavior by checking Nearby after changes.",
      ],
      tips: <String>[
        "Treasure Hunt is best for keyword-driven exploration.",
        "Travel mode helps when location context changes quickly.",
      ],
    ),
    "home:hq": _HelpContent(
      title: "HQ",
      summary: "HQ is the command center for announcements, status, progress, and quick actions.",
      tutorialSteps: <String>[
        "Read Announcements first for current priorities.",
        "Review business/unlock progress cards.",
        "Use quick actions for Referrals, Support, and Tester Mission.",
      ],
      tips: <String>[
        "Treat HQ as your daily startup checklist.",
        "Use tester mission to standardize validation runs.",
      ],
    ),
    "home:profile": _HelpContent(
      title: "Profile",
      summary: "Profile controls identity, trust signals, and visible account details.",
      tutorialSteps: <String>[
        "Complete required profile fields.",
        "Review trust/reliability indicators.",
        "Confirm public-facing details are accurate.",
      ],
      tips: <String>[
        "Complete profiles improve response and conversion rates.",
        "Keep profile details current after major changes.",
      ],
    ),
    "home:referrals": _HelpContent(
      title: "Referrals",
      summary: "Referrals manages invites, activation state, and reward verification.",
      tutorialSteps: <String>[
        "Share invite link/QR with a new user.",
        "Track status transitions: pending, activated, rewarded.",
        "Report mismatches with timestamped evidence.",
      ],
      tips: <String>[
        "Ask invitees to complete profile right away.",
        "Collect screenshots at each referral checkpoint.",
      ],
    ),
    "home:support": _HelpContent(
      title: "Support",
      summary: "Support is where users file bugs, feedback, and safety concerns.",
      tutorialSteps: <String>[
        "Open support center or ticket dashboard.",
        "Include exact steps and expected vs actual behavior.",
        "Attach screenshots with visible time.",
      ],
      tips: <String>[
        "Reproducible reports are fixed faster.",
        "Classify severity clearly: blocker, major, minor.",
      ],
    ),
    "home:settings": _HelpContent(
      title: "Settings",
      summary: "Settings controls app behavior, privacy, support tools, and accessibility.",
      tutorialSteps: <String>[
        "Review location/privacy status first.",
        "Tune discovery and scope to your test scenario.",
        "Use Text size slider to improve readability.",
      ],
      tips: <String>[
        "Increase text scale if labels feel crowded.",
        "Use Build & changelog for release evidence capture.",
      ],
    ),
    "settings:cosmetics": _HelpContent(
      title: "Cosmetics",
      summary: "Cosmetics changes look-and-feel options without affecting trust or safety logic.",
      tutorialSteps: <String>[
        "Preview a visual change.",
        "Apply it and return to a primary tab.",
        "Confirm readability and contrast remain good.",
      ],
      tips: <String>["Use visual changes that keep text legible at a glance."],
    ),
    "settings:business_receipts": _HelpContent(
      title: "Business Receipts",
      summary: "Business receipts shows local confirmations for tester build business actions.",
      tutorialSteps: <String>[
        "Open latest receipt entries.",
        "Check timestamp and action type.",
        "Capture evidence if expected receipt is missing.",
      ],
      tips: <String>["Receipts are useful for release and store-review evidence packs."],
    ),
    "settings:dev_panel": _HelpContent(
      title: "Developer Panel",
      summary: "Developer Panel contains diagnostics and internal tools for tester workflows.",
      tutorialSteps: <String>[
        "Open only the tool needed for your current check.",
        "Run one action at a time.",
        "Document unexpected behavior with build info.",
      ],
      tips: <String>["Avoid toggling unrelated debug controls during focused tests."],
    ),
    "settings:review_survival_kit": _HelpContent(
      title: "App Review Survival Kit",
      summary: "This kit organizes reviewer paths, test account setup, and screencast evidence.",
      tutorialSteps: <String>[
        "Follow the review path checklist in order.",
        "Validate each required reviewer action.",
        "Collect timestamped evidence for each checkpoint.",
      ],
      tips: <String>["Keep reviewer path steps short and deterministic."],
    ),
    "settings:support_mode": _HelpContent(
      title: "Support Mode",
      summary: "Support Mode lets qualified testers help users and track support activity.",
      tutorialSteps: <String>[
        "Review support mode status and eligibility.",
        "Open assigned support workflows.",
        "Log actions and outcomes clearly.",
      ],
      tips: <String>["Use concise, reproducible notes for every support interaction."],
    ),
    "settings:policy_hub": _HelpContent(
      title: "Policy Hub",
      summary: "Policy Hub explains conduct rules, enforcement paths, and appeals expectations.",
      tutorialSteps: <String>[
        "Read the relevant policy section first.",
        "Map your issue to policy language.",
        "Use linked report or appeal flow when needed.",
      ],
      tips: <String>["Citing exact policy language accelerates support triage."],
    ),
    "settings:my_incidents": _HelpContent(
      title: "My Reports & Appeals",
      summary: "This screen tracks your incident drafts, submissions, and appeal decisions.",
      tutorialSteps: <String>[
        "Open your latest case.",
        "Check current status and required next step.",
        "Submit missing evidence if requested.",
      ],
      tips: <String>["Attach concise timelines to improve incident clarity."],
    ),
    "settings:match_scope": _HelpContent(
      title: "Match Settings",
      summary: "Match settings controls scope depth and distance precision for who you can discover.",
      tutorialSteps: <String>[
        "Set scope for your current test objective.",
        "Save changes.",
        "Validate impact in Nearby results.",
      ],
      tips: <String>["Small scope changes can produce large feed differences."],
    ),
    "settings:discovery_filters": _HelpContent(
      title: "Discovery Filters",
      summary: "Discovery filters tune radius and mode-specific matching behavior.",
      tutorialSteps: <String>[
        "Adjust radius and relevant toggles.",
        "Return to Nearby.",
        "Confirm result quality aligns with your scenario.",
      ],
      tips: <String>["Start with moderate radius, then narrow for precision."],
    ),
    "settings:business_mode_payments": _HelpContent(
      title: "Business Mode & Payments",
      summary: "This flow handles business activation and related payment steps.",
      tutorialSteps: <String>[
        "Open plan/options and review eligibility details.",
        "Complete the required action path.",
        "Confirm entitlement updates after completion.",
      ],
      tips: <String>["Capture any payment errors with exact step and timestamp."],
    ),
    "settings:location_privacy_disclosure": _HelpContent(
      title: "Location Disclosure",
      summary: "Location disclosure explains when Prox uses location and key privacy guarantees.",
      tutorialSteps: <String>[
        "Read the usage summary fully.",
        "Confirm you understand what is and is not shared.",
        "Return to settings and verify your location toggle preference.",
      ],
      tips: <String>["Revisit disclosure after major app updates that touch location behavior."],
    ),
    "settings:trust_timeline": _HelpContent(
      title: "Trust Timeline",
      summary: "Trust timeline shows what events changed your trust over time.",
      tutorialSteps: <String>[
        "Review recent trust-impact entries.",
        "Open details for significant changes.",
        "Use timeline context when planning next actions.",
      ],
      tips: <String>["Unexpected trust changes should be reported with screenshots."],
    ),
    "settings:trust_rulebook": _HelpContent(
      title: "Trust Rulebook",
      summary: "Rulebook provides readable trust and behavior rules used in app decisions.",
      tutorialSteps: <String>[
        "Find the rule relevant to your question.",
        "Read examples and constraints.",
        "Apply it to your current scenario.",
      ],
      tips: <String>["Use rulebook language directly in support tickets."],
    ),
    "settings:business_avatar": _HelpContent(
      title: "Business Avatar Message",
      summary: "Set a short status or away message for your business avatar assistant.",
      tutorialSteps: <String>[
        "Write a brief status message.",
        "Save and reopen to confirm persistence.",
        "Update message when availability changes.",
      ],
      tips: <String>["Keep status messages concise and action-oriented."],
    ),
    "settings:blocked_users": _HelpContent(
      title: "Blocked Users",
      summary: "Blocked users lets you review and manage local meetup-request blocks.",
      tutorialSteps: <String>[
        "Review current blocked list.",
        "Unblock only if needed.",
        "Verify block status behavior in follow-up interactions.",
      ],
      tips: <String>["Document unblock actions when investigating safety reports."],
    ),
    "settings:account_billing": _HelpContent(
      title: "Account & Billing",
      summary: "Manage account details, billing state, and wallet/payment surfaces.",
      tutorialSteps: <String>[
        "Review account and billing sections.",
        "Check entitlement/subscription status.",
        "Validate any updates save correctly.",
      ],
      tips: <String>["Capture billing verification screenshots for release evidence."],
    ),
    "settings:tester_progress": _HelpContent(
      title: "Tester Progress",
      summary: "Tester progress shows level, trust, and participation milestones.",
      tutorialSteps: <String>[
        "Review current level and signals.",
        "Check what milestone is next.",
        "Use progress data to pick your next tester mission step.",
      ],
      tips: <String>["Progress trends help prioritize high-impact test work."],
    ),
    "settings:support_feedback": _HelpContent(
      title: "Support & Feedback",
      summary: "Submit bug reports, feature requests, and general support feedback.",
      tutorialSteps: <String>[
        "Choose the right report type.",
        "Describe exact repro steps.",
        "Attach timestamped evidence before submit.",
      ],
      tips: <String>["Expected vs actual behavior is the most useful report detail."],
    ),
    "support:support_center": _HelpContent(
      title: "Support Center",
      summary: "Support Center is the primary flow for filing and tracking support issues.",
      tutorialSteps: <String>[
        "Select issue category.",
        "Provide clear reproduction details.",
        "Submit and track follow-up state.",
      ],
      tips: <String>["Include app version and device details for faster triage."],
    ),
    "support:ticket_dashboard": _HelpContent(
      title: "Ticket Dashboard",
      summary: "Ticket dashboard lists your existing support submissions and statuses.",
      tutorialSteps: <String>[
        "Open the latest active ticket.",
        "Read requested follow-up actions.",
        "Provide updates or evidence as needed.",
      ],
      tips: <String>["Keep ticket updates short and focused on new information."],
    ),
    "support:support_mode": _HelpContent(
      title: "Support Mode",
      summary: "Support mode tools help testers assist users and maintain support quality.",
      tutorialSteps: <String>[
        "Review available support tasks.",
        "Complete one support action fully.",
        "Log a clear outcome before exiting.",
      ],
      tips: <String>["Consistent action logs make support quality auditable."],
    ),
    "support:compose_message": _HelpContent(
      title: "Compose Support Message",
      summary: "Use this form to submit clear bug reports, confusion points, or feature ideas.",
      tutorialSteps: <String>[
        "Write a concise subject line.",
        "Describe exact steps and expected vs actual behavior.",
        "Attach evidence details before submitting.",
      ],
      tips: <String>["Short repro steps with timestamps are easiest to triage."],
    ),
    "support:draft_edit": _HelpContent(
      title: "Edit Support Draft",
      summary: "Draft editing lets you refine and complete support tickets saved on this device.",
      tutorialSteps: <String>[
        "Open draft and validate details.",
        "Add missing evidence or clarifications.",
        "Submit when report quality is complete.",
      ],
      tips: <String>["Keep drafts focused on one issue per ticket."],
    ),
    "notifications:center": _HelpContent(
      title: "Notification Center",
      summary: "Notification Center shows recent alerts, status updates, and action reminders.",
      tutorialSteps: <String>[
        "Open notifications from top actions or app bar.",
        "Review newest alerts first.",
        "Open relevant destination screens to clear follow-ups.",
      ],
      tips: <String>["If notifications look stale, capture timestamps before reporting sync issues."],
    ),
    "auth:entry": _HelpContent(
      title: "Authentication",
      summary: "Authentication signs you into your account so profile, chat, and progress data can load.",
      tutorialSteps: <String>[
        "Open sign in from splash entry.",
        "Complete account authentication.",
        "Continue to onboarding or home based on account state.",
      ],
      tips: <String>["If sign-in fails, capture the exact error and timestamp."],
    ),
    "profile:edit": _HelpContent(
      title: "Profile Edit",
      summary: "Profile edit updates identity, keywords, and availability signals used for matching.",
      tutorialSteps: <String>[
        "Update required fields and profile keywords.",
        "Save and confirm validation passes.",
        "Return and verify updates render in profile views.",
      ],
      tips: <String>["Accurate keywords improve discovery quality and trust context."],
    ),
    "account:subscription_renewal": _HelpContent(
      title: "Subscription & Renewal",
      summary: "Review plan status, billing cycle, and renewal behavior for this account.",
      tutorialSteps: <String>[
        "Check active plan details.",
        "Verify renewal timing and billing state.",
        "Capture evidence if status looks inconsistent.",
      ],
      tips: <String>["Always include account ID and timestamp in billing reports."],
    ),
    "account:prox_points_wallet": _HelpContent(
      title: "Prox Points Wallet",
      summary: "Wallet view tracks current points, earning events, and spending options.",
      tutorialSteps: <String>[
        "Review current and total points.",
        "Open recent events for context.",
        "Use wallet actions to test earning and spending paths.",
      ],
      tips: <String>["Check event history after each test purchase."],
    ),
    "account:business_mode_learn_more": _HelpContent(
      title: "Business Mode Learn More",
      summary: "This path explains Business Mode requirements, behavior, and setup expectations before activation.",
      tutorialSteps: <String>[
        "Review eligibility and required profile signals.",
        "Read how Business Mode affects discovery and leads.",
        "Return to billing and continue only when requirements are clear.",
      ],
      tips: <String>["Capture any gate mismatch with timestamp and visible account state."],
    ),
    "points:tester_progress": _HelpContent(
      title: "Tester Progress",
      summary: "Tester progress summarizes trust, meetups, and level advancement signals.",
      tutorialSteps: <String>[
        "Open current level and signal breakdown.",
        "Confirm expected values after test actions.",
        "Record regressions with before/after screenshots.",
      ],
      tips: <String>["Progress deltas are useful for validating reward systems."],
    ),
    "points:buy_points": _HelpContent(
      title: "Buy Points",
      summary: "This flow handles points top-up and purchase confirmation.",
      tutorialSteps: <String>[
        "Select package and review price.",
        "Complete purchase path.",
        "Verify wallet balance updates afterward.",
      ],
      tips: <String>["If balance does not update, capture receipt and event history."],
    ),
    "points:featured_deals": _HelpContent(
      title: "Deals & Discounts",
      summary: "Featured deals show points-enabled offers and limited promotions.",
      tutorialSteps: <String>[
        "Browse current offers.",
        "Open one offer and review terms.",
        "Validate redemption behavior where applicable.",
      ],
      tips: <String>["Offer eligibility checks are common regression points."],
    ),
    "policy:code_of_conduct": _HelpContent(
      title: "Code of Conduct",
      summary: "This policy explains expected behavior standards for all Prox users.",
      tutorialSteps: <String>[
        "Read core behavior expectations.",
        "Review prohibited actions and examples.",
        "Use policy wording when reporting violations.",
      ],
      tips: <String>["Reference exact sections when filing policy tickets."],
    ),
    "policy:business_rules": _HelpContent(
      title: "Business Rules",
      summary: "Business rules define usage standards and guardrails for Business Mode.",
      tutorialSteps: <String>[
        "Review eligibility and obligations.",
        "Check compliance examples.",
        "Confirm you understand consequence paths.",
      ],
      tips: <String>["Business rule acknowledgments reduce support friction."],
    ),
    "policy:violations_consequences": _HelpContent(
      title: "Violations & Consequences",
      summary: "This section maps rule violations to warnings, restrictions, and bans.",
      tutorialSteps: <String>[
        "Identify violation category.",
        "Review consequence ladder.",
        "Use appeal guidance if action seems incorrect.",
      ],
      tips: <String>["Collect evidence before escalating enforcement disputes."],
    ),
    "policy:appeal_process": _HelpContent(
      title: "Appeal Process",
      summary: "Appeals explain how users submit evidence and request decision review.",
      tutorialSteps: <String>[
        "Read required appeal inputs.",
        "Prepare concise timeline and evidence.",
        "Submit and track decision updates.",
      ],
      tips: <String>["Appeals are strongest when evidence is chronological and specific."],
    ),
    "referrals:manage": _HelpContent(
      title: "Referrals",
      summary: "Manage invite links, QR sharing, and referral lifecycle tracking from this screen.",
      tutorialSteps: <String>[
        "Generate or reuse your referral code.",
        "Share QR or link with invitees.",
        "Monitor joined and verified progression.",
      ],
      tips: <String>["Document invite-to-verify path with timestamps for validation."],
    ),
    "referrals:gate_sign_in": _HelpContent(
      title: "Referral Gate Sign In",
      summary: "Use this sign-in route when entering from a referral access gate or invite path.",
      tutorialSteps: <String>[
        "Open sign in from the referral gate.",
        "Authenticate with your existing account.",
        "Return and confirm referral state resumes correctly.",
      ],
      tips: <String>["If access loops, capture the exact gate message and account used."],
    ),
    "support:technician_dashboard": _HelpContent(
      title: "Technician Dashboard",
      summary: "Technician dashboard provides support-operator workflows and queue visibility.",
      tutorialSteps: <String>[
        "Review current queue and priorities.",
        "Open one case and complete a full support action.",
        "Log clear outcomes before closing.",
      ],
      tips: <String>["Consistent case notes improve escalation quality."],
    ),
    "rollout:host_packet": _HelpContent(
      title: "Host Packet",
      summary: "Host packet centralizes launch goals, run order, and operator instructions.",
      tutorialSteps: <String>[
        "Review goals and event timeline.",
        "Confirm host responsibilities.",
        "Share packet with rollout leads.",
      ],
      tips: <String>["Keep packet language short and action-focused."],
    ),
    "rollout:go_no_go_checklist": _HelpContent(
      title: "Go/No-Go Checklist",
      summary: "Checklist confirms release readiness before sending go-live communication.",
      tutorialSteps: <String>[
        "Run each checklist gate in order.",
        "Capture pass/fail evidence.",
        "Hold rollout if critical gates fail.",
      ],
      tips: <String>["Use the same gate order for every release cycle."],
    ),
    "rollout:communication_playbook": _HelpContent(
      title: "Communication Playbook",
      summary: "Playbook provides staged message templates for pre-launch and live updates.",
      tutorialSteps: <String>[
        "Select correct phase template.",
        "Customize minimal required details.",
        "Send and log message timestamp.",
      ],
      tips: <String>["Template consistency reduces launch confusion."],
    ),
    "rollout:day_of_runbook": _HelpContent(
      title: "Day-Of Runbook",
      summary: "Runbook defines roles, timeline, and response priorities for launch day.",
      tutorialSteps: <String>[
        "Assign owners to each checkpoint.",
        "Follow timeline gates during execution.",
        "Escalate blockers immediately.",
      ],
      tips: <String>["Treat runbook deviations as incidents to document."],
    ),
    "rollout:tester_prep_sheet": _HelpContent(
      title: "Tester Prep Sheet",
      summary: "Prep sheet gives testers a concise startup checklist and success path.",
      tutorialSteps: <String>[
        "Review install and permission prerequisites.",
        "Follow the first-run path exactly.",
        "Report blockers with evidence.",
      ],
      tips: <String>["Prep sheets reduce repetitive onboarding support requests."],
    ),
    "rollout:referrals_invites": _HelpContent(
      title: "Rollout Referrals",
      summary: "This rollout flow focuses on referral code creation and verification tracking.",
      tutorialSteps: <String>[
        "Create active referral code.",
        "Share invites and monitor join status.",
        "Validate verified conversion events.",
      ],
      tips: <String>["Capture referral state transitions for post-launch review."],
    ),
    "rollout:metrics_dashboard": _HelpContent(
      title: "Rollout Metrics",
      summary: "Metrics dashboard tracks core launch events like chat, meetup, rating, and referral signals.",
      tutorialSteps: <String>[
        "Review event counts and trend direction.",
        "Check for missing expected signals.",
        "Escalate anomalies with timestamps.",
      ],
      tips: <String>["Correlate metrics spikes with specific launch actions."],
    ),
    "incident:create_draft": _HelpContent(
      title: "Create Incident Draft",
      summary: "Draft mode lets you prepare reports or appeals locally before submission.",
      tutorialSteps: <String>[
        "Fill title, narrative, and optional evidence.",
        "Save draft as you refine details.",
        "Submit when evidence quality is complete.",
      ],
      tips: <String>["Chronological narratives improve review outcomes."],
    ),
    "incident:view_detail": _HelpContent(
      title: "Incident Detail",
      summary: "Incident detail shows status, facts, timeline, and transparency export options.",
      tutorialSteps: <String>[
        "Review current status and decision text.",
        "Inspect timeline updates.",
        "Use copy export for support escalation when needed.",
      ],
      tips: <String>["Always verify incident ID when discussing a case."],
    ),
    "incident:submitted_detail": _HelpContent(
      title: "Submitted Incident",
      summary: "After submitting a draft, this screen tracks the newly created server incident.",
      tutorialSteps: <String>[
        "Confirm submission status changed from draft.",
        "Review generated timeline entries.",
        "Use Add info if follow-up evidence is needed.",
      ],
      tips: <String>["Capture submission timestamp for audit trails."],
    ),
    "incident:add_info": _HelpContent(
      title: "Incident Add Info",
      summary: "Add Info lets you append clarifications or new evidence to an existing incident.",
      tutorialSteps: <String>[
        "Summarize new facts clearly.",
        "Attach supporting references.",
        "Submit update and verify timeline entry appears.",
      ],
      tips: <String>["Keep updates focused on new information only."],
    ),
    "trust:rulebook": _HelpContent(
      title: "Trust Rulebook",
      summary: "Rulebook provides readable trust and behavior rules used in moderation and trust decisions.",
      tutorialSteps: <String>[
        "Open the rulebook section relevant to your question.",
        "Read examples and constraints for that rule.",
        "Use exact rule wording in support or incident follow-up.",
      ],
      tips: <String>["Rule citations are most useful when paired with timeline evidence."],
    ),
    "party:member_profile": _HelpContent(
      title: "Party Member Profile",
      summary: "Member profile shows trust-facing details, relationship context, and recent activity signals.",
      tutorialSteps: <String>[
        "Open a member from party list.",
        "Review profile details and relationship indicators.",
        "Return to party list and continue managing members.",
      ],
      tips: <String>["Use member profile context before escalating party-related reports."],
    ),
    "tutorial:playback": _HelpContent(
      title: "Tutorial Playback",
      summary: "Tutorial playback walks through feature behavior with guided, repeatable demo steps.",
      tutorialSteps: <String>[
        "Run the tutorial from start to finish once.",
        "Confirm each step matches current app behavior.",
        "Mark completion and report mismatches with screenshots.",
      ],
      tips: <String>["Playback regressions are strong early indicators of UI flow breakage."],
    ),
    "onboarding:profile_setup": _HelpContent(
      title: "Onboarding Profile Setup",
      summary: "This transition moves onboarding users into profile setup before full app access.",
      tutorialSteps: <String>[
        "Open profile setup from onboarding.",
        "Complete required fields and save.",
        "Return and verify onboarding can continue cleanly.",
      ],
      tips: <String>["Missing required profile fields can block referral and matching flows."],
    ),
    "chats:thread": _HelpContent(
      title: "Chat Thread",
      summary: "Chat thread view is where direct conversations progress toward clear next actions.",
      tutorialSteps: <String>[
        "Open a thread from the chat list.",
        "Review latest messages and context.",
        "Reply with a concrete next step.",
      ],
      tips: <String>["Short, specific replies usually produce faster follow-up."],
    ),
    "business:setup": _HelpContent(
      title: "Business Setup",
      summary: "Business setup creates or edits your business profile and service details.",
      tutorialSteps: <String>[
        "Complete business basics and category.",
        "Review profile accuracy.",
        "Save and confirm visibility state.",
      ],
      tips: <String>["Precise category and description improve lead quality."],
    ),
    "business:paywall": _HelpContent(
      title: "Business Paywall",
      summary: "This paywall handles one-time or subscription unlock actions for Business Mode.",
      tutorialSteps: <String>[
        "Review available unlock options and point costs.",
        "Complete the intended unlock action.",
        "Return and confirm entitlement status updates.",
      ],
      tips: <String>["Capture transaction errors with selected option and account state."],
    ),
    "meetup:color_match": _HelpContent(
      title: "Meetup Color Match",
      summary: "Color Match helps meetup participants identify each other visually in crowded spaces.",
      tutorialSteps: <String>[
        "Choose a bright, distinctive color.",
        "Launch full-screen color mode during meetup.",
        "Dismiss and continue coordination once matched.",
      ],
      tips: <String>["High-contrast colors work best outdoors and in low light."],
    ),
    "meetup:post_flow": _HelpContent(
      title: "Post-Meetup Flow",
      summary: "Post-meetup flow captures outcomes and transitions the interaction into trust/rating updates.",
      tutorialSteps: <String>[
        "Open post-meetup flow after completion.",
        "Confirm outcome and submit feedback steps.",
        "Verify trust and progression effects appear as expected.",
      ],
      tips: <String>["Run post-flow quickly after meetup while details are fresh."],
    ),
    "business:profile_edit": _HelpContent(
      title: "Business Profile Edit",
      summary: "Edit public-facing profile details used in discovery and trust signals.",
      tutorialSteps: <String>[
        "Update headline and service keywords.",
        "Save changes.",
        "Validate rendering in profile surfaces.",
      ],
      tips: <String>["Keep keywords aligned with real offerings."],
    ),
    "business:mode_setup": _HelpContent(
      title: "Business Mode Setup",
      summary: "Mode setup configures Business Mode readiness and profile requirements.",
      tutorialSteps: <String>[
        "Review gate requirements.",
        "Complete setup steps.",
        "Return to verify active eligibility.",
      ],
      tips: <String>["Use this flow whenever eligibility status changes unexpectedly."],
    ),
    "business:live_leads": _HelpContent(
      title: "Business Live Leads",
      summary: "Live leads opens the real-time inbox for nearby business opportunities.",
      tutorialSteps: <String>[
        "Review current lead cards.",
        "Open high-intent matches quickly.",
        "Move viable leads into chat and meetup flow.",
      ],
      tips: <String>["Fast first response helps conversion."],
    ),
    "business:active_chats": _HelpContent(
      title: "Business Active Chats",
      summary: "Active chats view ongoing customer conversations and follow-up needs.",
      tutorialSteps: <String>[
        "Open newest conversations first.",
        "Resolve pending replies.",
        "Escalate to meetup planning where relevant.",
      ],
      tips: <String>["Clear next-action messages reduce drop-off."],
    ),
    "business:hq_profile_edit": _HelpContent(
      title: "Business HQ Profile Edit",
      summary: "Quick edit from Business HQ to keep profile and availability up to date.",
      tutorialSteps: <String>[
        "Open profile edit from HQ.",
        "Update availability or positioning text.",
        "Save and verify dashboard consistency.",
      ],
      tips: <String>["Refresh profile copy as service focus changes."],
    ),
    "matches:chat_thread": _HelpContent(
      title: "Match Chat Thread",
      summary: "Thread view is where match conversations move toward clear next actions.",
      tutorialSteps: <String>[
        "Read latest context.",
        "Reply with concrete next step.",
        "Transition qualified matches to meetup planning.",
      ],
      tips: <String>["Short operational replies keep momentum high."],
    ),
    "matches:mode_chooser": _HelpContent(
      title: "Matching Mode Chooser",
      summary: "Mode chooser switches between normal, travel, treasure, and off behavior.",
      tutorialSteps: <String>[
        "Pick mode matching current goal.",
        "Adjust related radius/settings.",
        "Return to inbox and verify behavior change.",
      ],
      tips: <String>["Mode mismatches are a common reason for weak match quality."],
    ),
    "matches:treasure_hunt": _HelpContent(
      title: "Treasure Hunt",
      summary: "Treasure Hunt uses directional cues and keyword overlap to guide exploration.",
      tutorialSteps: <String>[
        "Open compass and identify top clue.",
        "Move toward bearing while monitoring clues.",
        "Open chat when target becomes relevant.",
      ],
      tips: <String>["Treasure mode performs best with active movement and fresh location."],
    ),
  };

  static const Map<String, _HelpContent> _routeHelp = <String, _HelpContent>{
    "/": _HelpContent(
      title: "Startup",
      summary: "This is the startup/splash phase while Prox initializes core services.",
      tutorialSteps: <String>[
        "Wait for startup checks to complete.",
        "If startup stalls, reopen app once.",
        "Report persistent startup failures with screenshot evidence.",
      ],
      tips: <String>["Include device model and app build when reporting startup issues."],
    ),
    "/auth": _HelpContent(
      title: "Authentication",
      summary: "Sign in to unlock your user profile, data sync, and messaging.",
      tutorialSteps: <String>[
        "Enter credentials and complete sign-in.",
        "Confirm account state loads without errors.",
        "Proceed to onboarding/profile completion.",
      ],
      tips: <String>["If password reset is needed, verify mailbox delivery time."],
    ),
    "/onboarding": _HelpContent(
      title: "Onboarding",
      summary: "Onboarding collects required setup details to personalize the app.",
      tutorialSteps: <String>[
        "Complete each required onboarding step.",
        "Review permissions prompts and grant required ones.",
        "Finish setup and continue to Home.",
      ],
      tips: <String>["Missing onboarding fields can block downstream features."],
    ),
    "/profile_setup": _HelpContent(
      title: "Profile Setup",
      summary: "Profile Setup finalizes your identity, visibility, and core account fields.",
      tutorialSteps: <String>[
        "Fill profile basics completely.",
        "Save changes and verify no validation errors.",
        "Continue into Home after completion.",
      ],
      tips: <String>["Complete profiles generally perform better in matching."],
    ),
    "/home": _HelpContent(
      title: "Home",
      summary: "Home is the root shell with swipe tabs for all major areas.",
      tutorialSteps: <String>[
        "Use bottom tabs and swipe to access all sections.",
        "Start from Nearby/Matches for active usage.",
        "Use HQ for high-level status and quick actions.",
      ],
      tips: <String>["If you cannot find a feature, swipe nav to reveal the next tab page."],
    ),
    "/nearby": _HelpContent(
      title: "Nearby",
      summary: "Nearby shows currently discoverable users near your location context.",
      tutorialSteps: <String>[
        "Validate location and mode settings.",
        "Review candidate cards and open relevant chats.",
        "Adjust filters/radius when result quality drops.",
      ],
      tips: <String>["Mode and radius tuning can dramatically change feed quality."],
    ),
    "/matches": _HelpContent(
      title: "Matches",
      summary: "Matches tracks active conversations and relationship progress.",
      tutorialSteps: <String>[
        "Open recent matches and respond quickly.",
        "Qualify intent before meetup planning.",
        "Escalate active threads to meetup flow.",
      ],
      tips: <String>["Fast first response improves retention and conversion."],
    ),
    "/inbox": _HelpContent(
      title: "Inbox",
      summary: "Inbox lists your chats and helps you manage unread work.",
      tutorialSteps: <String>[
        "Open newest thread first.",
        "Resolve unread items with clear next actions.",
        "Move high-intent chats into meetup planning.",
      ],
      tips: <String>["Unread badge is a quick health signal for conversation backlog."],
    ),
    "/chat": _HelpContent(
      title: "Chat Thread",
      summary: "Chat is for direct conversation, coordination, and follow-up.",
      tutorialSteps: <String>[
        "Read latest message context first.",
        "Send concise, action-oriented replies.",
        "Transition to meetup planning once both sides align.",
      ],
      tips: <String>["Keep messages specific to reduce scheduling friction."],
    ),
    "/meetup_plan": _HelpContent(
      title: "Meetup Planner",
      summary: "Planner sets meetup location, timing, and confirmation path.",
      tutorialSteps: <String>[
        "Pick location and timing details.",
        "Share and confirm with the other participant.",
        "Start live meetup flow when heading out.",
      ],
      tips: <String>["Short, precise planning details reduce cancellations."],
    ),
    "/meetup_live": _HelpContent(
      title: "Meetup Live",
      summary: "Live meetup supports real-time coordination through arrival/completion.",
      tutorialSteps: <String>[
        "Open live mode when meetup starts.",
        "Use progress/arrival actions as needed.",
        "Complete and proceed to rating.",
      ],
      tips: <String>["Use timestamped screenshots when validating live flow."],
    ),
    "/rate": _HelpContent(
      title: "Rating",
      summary: "Rating closes the meetup loop and contributes trust signal quality.",
      tutorialSteps: <String>[
        "Submit fair, accurate post-meetup rating.",
        "Include relevant feedback when prompted.",
        "Confirm rating state is saved successfully.",
      ],
      tips: <String>["Consistent rating completion keeps trust data healthy."],
    ),
    "/dashboard": _HelpContent(
      title: "HQ Dashboard",
      summary: "Dashboard is your operations hub for announcements and progress tracking.",
      tutorialSteps: <String>[
        "Read announcements at top first.",
        "Check business/network snapshot cards.",
        "Use quick actions for support/referrals/tester tools.",
      ],
      tips: <String>["Use Dashboard as your daily operational checklist."],
    ),
    "/store": _HelpContent(
      title: "Store",
      summary: "Store shows points-based unlocks, packs, and monetization previews.",
      tutorialSteps: <String>[
        "Review available items and requirements.",
        "Check lock conditions when purchase is blocked.",
        "Confirm ownership/entitlement state after purchase.",
      ],
      tips: <String>["Document purchase flow outcomes during release testing."],
    ),
    "/support": _HelpContent(
      title: "Support Hub",
      summary: "Support Hub centralizes feedback, issues, and support-mode tools.",
      tutorialSteps: <String>[
        "Open support center to create reports.",
        "Use ticket dashboard for ongoing issues.",
        "Attach concise repro steps plus evidence.",
      ],
      tips: <String>["High-signal reports include expected vs actual behavior."],
    ),
    "/referrals": _HelpContent(
      title: "Referrals Hub",
      summary: "Referrals Hub manages invite sharing and reward lifecycle tracking.",
      tutorialSteps: <String>[
        "Share referral via QR/link.",
        "Track conversion stages in-app.",
        "Escalate mismatches with timestamped proof.",
      ],
      tips: <String>["Referral quality improves with clear invite onboarding instructions."],
    ),
    "/account": _HelpContent(
      title: "Account & Billing",
      summary: "Account handles billing, business eligibility, and financial controls.",
      tutorialSteps: <String>[
        "Review account and billing status.",
        "Check business mode eligibility conditions.",
        "Validate any payment/entitlement updates.",
      ],
      tips: <String>["Capture billing flow evidence for release confidence."],
    ),
    "/policy": _HelpContent(
      title: "Policy Hub",
      summary: "Policy Hub explains trust, safety, enforcement, and appeals flows.",
      tutorialSteps: <String>[
        "Read policy section relevant to your issue.",
        "Use linked report/appeal paths where needed.",
        "Confirm policy expectations before escalation.",
      ],
      tips: <String>["Link policy citations in support tickets for faster resolution."],
    ),
    "/notifications": _HelpContent(
      title: "Notifications",
      summary: "Notifications shows events and what still needs your attention.",
      tutorialSteps: <String>[
        "Open unread notifications first.",
        "Mark each item seen as you process it.",
        "Use bulk actions when queue is complete.",
      ],
      tips: <String>["Keep unread count low to avoid missing important events."],
    ),
    "/settings": _HelpContent(
      title: "Settings",
      summary: "Settings controls privacy, discovery behavior, support options, and accessibility.",
      tutorialSteps: <String>[
        "Review location/privacy and discovery controls.",
        "Use text size slider for readability.",
        "Check build/changelog and tester tools as needed.",
      ],
      tips: <String>["Set text scale above 1.0x for older users needing larger UI text."],
    ),
    "/rc_checklist": _HelpContent(
      title: "Release Checklist",
      summary: "This checklist validates core release readiness before ship decisions.",
      tutorialSteps: <String>[
        "Run each checklist item end-to-end.",
        "Capture proof for each critical gate.",
        "Log blockers in support/release docs.",
      ],
      tips: <String>["Use the same checklist order every cycle for consistency."],
    ),
    "/tester-mission": _HelpContent(
      title: "Tester Mission",
      summary: "Tester Mission defines referral-first goals and Big-5 validation steps.",
      tutorialSteps: <String>[
        "Complete referral invite targets.",
        "Execute Big-5 user journey checkpoints.",
        "Submit timestamped evidence with feedback.",
      ],
      tips: <String>["Use mission screen as canonical tester playbook."],
    ),
    "/tester-insight": _HelpContent(
      title: "Tester Insight Mode",
      summary: "Insight mode centralizes report templates, quality scoring, and tester progress outputs.",
      tutorialSteps: <String>[
        "Start with structured feedback or quick bug capture.",
        "Use mission and progress links to complete the feedback loop.",
        "Review score/counters to improve next report quality.",
      ],
      tips: <String>["High-quality reports include expected vs actual behavior and timestamped evidence."],
    ),
    "/dev": _HelpContent(
      title: "Developer Panel",
      summary: "Developer Panel exposes diagnostics and test-only operational tools.",
      tutorialSteps: <String>[
        "Open only in tester/dev workflows.",
        "Run diagnostics required for current triage.",
        "Capture outputs in bug reports when needed.",
      ],
      tips: <String>["Avoid changing unrelated flags during active test sessions."],
    ),
    "/dev/menu": _HelpContent(
      title: "Developer Menu",
      summary: "Developer Menu routes to focused internal tools and debug actions.",
      tutorialSteps: <String>[
        "Select the specific tool needed for your test.",
        "Run action and observe expected behavior.",
        "Document any mismatch with build and timestamp.",
      ],
      tips: <String>["Use smallest-scope debug action first to isolate cause."],
    ),
    "/dev/bug_reports": _HelpContent(
      title: "Bug Reports",
      summary: "Bug Reports list helps triage, validate, and track report quality.",
      tutorialSteps: <String>[
        "Open report and confirm repro details.",
        "Verify evidence completeness.",
        "Update status once confirmed.",
      ],
      tips: <String>["Reports missing timestamps should be sent back for completion."],
    ),
    "/dev/sweep": _HelpContent(
      title: "Missing Sweep Check",
      summary: "Sweep check verifies policy/background sweeper health for active mode.",
      tutorialSteps: <String>[
        "Run check and inspect latest health values.",
        "Confirm schedule/manual sweep behavior.",
        "Escalate if stale/errored states persist.",
      ],
      tips: <String>["Use admin observability endpoints to corroborate results."],
    ),
  };

  static _HelpContent _deriveFallback(String routeName, String? contextKey) {
    final source = (contextKey ?? routeName).trim();
    final normalized = source.toLowerCase();
    final label = source
        .replaceAll("home:", "")
        .replaceAll("/", " ")
        .replaceAll("_", " ")
        .trim();
    final niceLabel = label.isEmpty
        ? "Current Screen"
        : label
            .split(RegExp(r"\s+"))
            .map((w) => w.isEmpty ? w : "${w[0].toUpperCase()}${w.substring(1)}")
            .join(" ");

    if (normalized.contains("chat") || normalized.contains("inbox")) {
      return const _HelpContent(
        title: "Messaging",
        summary: "This screen is part of Prox messaging and conversation management.",
        tutorialSteps: <String>[
          "Read context before replying.",
          "Respond with a clear next action.",
          "Advance high-intent threads toward meetup flow.",
        ],
        tips: <String>["Short responses with explicit next steps work best."],
      );
    }

    if (normalized.contains("meetup") || normalized.contains("rate")) {
      return const _HelpContent(
        title: "Meetup Flow",
        summary: "This screen belongs to planning/live/completion flow for meetups.",
        tutorialSteps: <String>[
          "Complete required meetup step on this screen.",
          "Confirm status transition is saved.",
          "Proceed to next meetup stage when done.",
        ],
        tips: <String>["Capture time-stamped proof during live meetup testing."],
      );
    }

    if (normalized.contains("dev") || normalized.contains("debug")) {
      return const _HelpContent(
        title: "Developer Tooling",
        summary: "This appears to be a developer/test utility surface.",
        tutorialSteps: <String>[
          "Run only the tool required for your task.",
          "Observe output and expected behavior.",
          "Record evidence if behavior diverges.",
        ],
        tips: <String>["Avoid changing unrelated debug state in active sessions."],
      );
    }

    return _HelpContent(
      title: niceLabel,
      summary: "You are viewing $niceLabel. Use this page to complete its primary action in your current Prox flow.",
      tutorialSteps: const <String>[
        "Identify the main purpose of this screen.",
        "Complete one full action on this screen.",
        "Confirm the result saved or navigated as expected.",
      ],
      tips: const <String>[
        "If behavior is unclear, capture screenshot + timestamp for support.",
        "Use the support button below when blocked.",
      ],
    );
  }

  static _HelpContent _contentFor(String routeName, String? contextKey) {
    final contextNorm = contextKey?.toLowerCase().trim();
    final routeNorm = routeName.toLowerCase().trim();

    if (contextNorm != null && _contextHelp.containsKey(contextNorm)) {
      return _contextHelp[contextNorm]!;
    }
    if (_routeHelp.containsKey(routeNorm)) {
      return _routeHelp[routeNorm]!;
    }
    return _deriveFallback(routeName, contextKey);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final content = _contentFor(routeName, contextKey);

    return Scaffold(
      appBar: AppBar(
        title: const Text("How to Use This Page"),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  content.summary,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            context,
            title: "Quick tutorial",
            icon: Icons.play_circle_outline,
            lines: content.tutorialSteps,
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: "Tips to explore",
            icon: Icons.lightbulb_outline,
            lines: content.tips,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushNamed(supportRoute),
            icon: const Icon(Icons.support_agent_outlined),
            label: const Text("Still having trouble? Contact support"),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> lines,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : 8),
              child: Text(
                "${i + 1}. ${lines[i]}",
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.32),
              ),
            ),
        ],
      ),
    );
  }
}

class _HelpContent {
  final String title;
  final String summary;
  final List<String> tutorialSteps;
  final List<String> tips;

  const _HelpContent({
    required this.title,
    required this.summary,
    required this.tutorialSteps,
    required this.tips,
  });
}
