import "package:flutter/material.dart";

import "package:prox/services/policy_ack_service.dart";

class LegalAgreementScreen extends StatefulWidget {
  const LegalAgreementScreen({
    super.key,
    this.requireAcceptance = false,
  });

  final bool requireAcceptance;

  @override
  State<LegalAgreementScreen> createState() => _LegalAgreementScreenState();
}

class _LegalAgreementScreenState extends State<LegalAgreementScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _hasReachedEnd = false;
  bool _saving = false;

  static const String _title =
      "Prox User Agreement, Safety Waiver & Platform Rules";
  static const String _versionLabel = "Version 1 - effective June 20, 2026";

  static final String _agreementText = <String>[
    _title,
    _versionLabel,
    "",
    "Important notice",
    "This in-app agreement is a product safeguard and user-facing consent record. It is not a substitute for legal advice from a qualified attorney. By accepting, you confirm that you have read and understand the rules below and agree to use Prox responsibly.",
    "",
    "1. Your responsibility when using Prox",
    "Prox helps people discover nearby intent-based connections, chats, services, referrals, meetups, support interactions, and related tools. You are responsible for your own decisions, communications, travel, transactions, meetups, conduct, safety precautions, and compliance with the law.",
    "",
    "2. No guarantee of outcomes or safety",
    "Prox does not guarantee that any user, match, meetup, service, offer, referral, business lead, support interaction, location suggestion, route, payment, profile, message, or third-party action will be safe, accurate, lawful, ethical, available, reliable, successful, or free from harm. You agree to use your own judgment and leave or report any situation that feels unsafe, fraudulent, illegal, coercive, or inappropriate.",
    "",
    "3. Limitation of liability",
    "To the fullest extent allowed by law, Prox, its creator, owners, operators, employees, contractors, affiliates, successors, and eventual company entity are not liable for harm, loss, injury, dispute, damages, crime, misconduct, fraud, property damage, financial loss, emotional distress, data loss, account action, missed opportunity, business loss, or any other claim arising from or related to your use of the app, interactions with other users, real-world meetings, third-party services, payment activity, or reliance on information shown in Prox.",
    "",
    "4. Illegal, harmful, or unethical activity is prohibited",
    "You may not use Prox to plan, request, offer, facilitate, hide, promote, or participate in illegal activity, fraud, exploitation, harassment, threats, stalking, violence, theft, scams, deception, impersonation, abuse, unsafe services, unauthorized access, platform manipulation, referral abuse, payment abuse, intellectual-property infringement, or unethical activity that could harm users, Prox, or the public.",
    "",
    "5. Enforcement and account action",
    "If Prox detects or receives credible reports of illegal, unsafe, abusive, fraudulent, exploitative, unethical, or platform-harming activity, Prox may restrict, suspend, ban, hide, remove, downgrade, investigate, or preserve the account, profile, content, chats, meetups, referrals, payments, rewards, business features, support privileges, or related access. Prox may take action before notifying you when needed to protect users, evidence, the platform, or legal obligations.",
    "",
    "6. Data review, preservation, and sharing",
    "You understand that Prox may review, preserve, export, and share account data, profile data, messages, reports, support tickets, location-related records, device or diagnostic data, payment or transaction records, referral data, trust or enforcement records, and other relevant information when necessary to enforce these rules, protect users or Prox, investigate suspected misconduct, comply with law, respond to legal process, prevent fraud or abuse, or cooperate with law enforcement, regulators, payment processors, safety partners, attorneys, insurers, service providers, or other appropriate third parties.",
    "",
    "7. Intellectual property and platform rights",
    "Prox, the Prox name, logo, app design, user experience, features, code, text, graphics, systems, matching logic, trust mechanics, reward mechanics, policy language, documentation, and related materials are owned by Prox or its creator unless otherwise stated. You may not copy, scrape, reverse engineer, clone, resell, misuse, impersonate, reproduce, distribute, or create confusingly similar products, branding, content, workflows, or services from Prox without written permission, except where allowed by law.",
    "",
    "8. User content and feedback",
    "You keep ownership of content you submit, but you grant Prox a worldwide, non-exclusive, royalty-free license to host, store, process, display, analyze, moderate, transmit, and use that content as needed to operate, improve, secure, support, market, and enforce the app. Ideas, feedback, bug reports, suggestions, and tester notes may be used by Prox without compensation or obligation.",
    "",
    "9. No misuse of Prox data or users",
    "You may not harvest user data, track people outside the intended app experience, use Prox to build datasets, contact lists, competing services, spam systems, surveillance workflows, or automated accounts, or attempt to bypass privacy, trust, safety, location, entitlement, payment, referral, support, or enforcement systems.",
    "",
    "10. Assumption of risk",
    "Real-world interactions can involve risk. You voluntarily assume the risks connected to meeting, chatting, sharing information with, traveling to, receiving services from, providing services to, paying, being paid by, or otherwise interacting with other people or third parties through Prox.",
    "",
    "11. Updates",
    "Prox may update this agreement and require you to accept a new version before continuing to use some or all app features. Continued use after acceptance means you agree to the active version.",
    "",
    "12. Acceptance",
    "By tapping the acceptance button, you confirm that you have scrolled through and read this agreement, understand it, and agree to follow it. If you do not agree, do not use Prox.",
  ].join("\n");

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    // ignore: discarded_futures
    PolicyAckService.instance.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atEnd = position.maxScrollExtent <= 0 ||
        position.pixels >= position.maxScrollExtent - 24;
    if (atEnd != _hasReachedEnd && mounted) {
      setState(() => _hasReachedEnd = atEnd);
    }
  }

  Future<void> _accept() async {
    if (_saving || !_hasReachedEnd) return;
    setState(() => _saving = true);
    try {
      await PolicyAckService.instance.setAcked(
        PolicyAckService.legalAgreementVersion,
        true,
        metadata: const <String, Object?>{
          "title": _title,
          "versionLabel": _versionLabel,
          "source": "in_app_scroll_acceptance",
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Accepted: Prox user agreement")),
      );
      if (widget.requireAcceptance) {
        Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
          "/home",
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not save acceptance: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: !widget.requireAcceptance ||
          PolicyAckService.instance
              .isAcked(PolicyAckService.legalAgreementVersion),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.requireAcceptance,
          title: const Text("Legal agreement"),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (widget.requireAcceptance)
                MaterialBanner(
                  content: const Text(
                      "Review and accept this agreement before continuing into Prox."),
                  leading: const Icon(Icons.verified_user_outlined),
                  actions: const [SizedBox.shrink()],
                ),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: cs.outline.withValues(alpha: 0.22)),
                      ),
                      child: SelectableText(
                        _agreementText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: PolicyAckService.instance,
                builder: (context, _) {
                  final accepted = PolicyAckService.instance
                      .isAcked(PolicyAckService.legalAgreementVersion);
                  final canAccept = _hasReachedEnd && !_saving && !accepted;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(
                          top: BorderSide(
                              color: cs.outline.withValues(alpha: 0.16))),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          accepted
                              ? "Accepted for this account."
                              : _hasReachedEnd
                                  ? "You can accept now."
                                  : "Scroll to the bottom to enable acceptance.",
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: canAccept ? _accept : null,
                          icon: Icon(
                              accepted ? Icons.check_circle : Icons.done_all),
                          label: Text(
                            accepted
                                ? "Accepted"
                                : _saving
                                    ? "Saving..."
                                    : "I have read and accept",
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
