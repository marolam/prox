// lib/screens/support/support_compose_screen.dart
//
// Simple composer for a support ticket draft. Drafts live locally and can
// be sent via email when the tester is ready.

import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:url_launcher/url_launcher.dart";

import "package:prox/models/support_ticket.dart";
import "package:prox/models/support_ticket_draft.dart";
import "package:prox/services/support_service.dart";
import "package:prox/services/support_ticket_queue.dart";
import "package:prox/widgets/retry_banner.dart";
import "package:prox/widgets/safe_snack.dart";

class SupportComposeScreen extends StatefulWidget {
  const SupportComposeScreen({
    super.key,
    this.existingDraft,
  });

  final SupportTicketDraft? existingDraft;

  @override
  State<SupportComposeScreen> createState() => _SupportComposeScreenState();
}

class _SupportComposeScreenState extends State<SupportComposeScreen> {
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  late final String _draftId;
  late final DateTime _createdAt;

  @override
  void initState() {
    super.initState();
    final SupportTicketDraft? draft = widget.existingDraft;
    _draftId =
        draft?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    _createdAt = draft?.createdAt ?? DateTime.now();
    _subjectController = TextEditingController(text: draft?.subject ?? "");
    _messageController = TextEditingController(text: draft?.message ?? "");
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final bool isEditing = widget.existingDraft != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Edit support message" : "New support message"),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
          const RetryBanner(
            message:
                "If sending fails, your draft stays here so you can try again later.",
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _subjectController,
            textInputAction: TextInputAction.next,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              labelText: "Subject",
              hintText: "Short summary (e.g. \"Match screen froze\")",
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            keyboardType: TextInputType.multiline,
            maxLines: 8,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              labelText: "What happened?",
              hintText:
                  "Tell us what you were trying to do, what actually happened, and anything else that would help.",
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Tip: Including steps to reproduce and your phone model helps us fix things much faster.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _saveDraft,
                icon: const Icon(Icons.save_outlined),
                label: const Text("Save draft"),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _submitInAppTicket,
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text("Submit in app"),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _sendViaEmail,
                icon: const Icon(Icons.send),
                label: const Text("Send via email"),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  void _saveDraft() {
    final String subject = _subjectController.text.trim();
    final String message = _messageController.text.trim();

    if (subject.isEmpty && message.isEmpty) {
      safeShowSnackBar(
        context,
        "Add a subject or message before saving a draft.",
      );
      return;
    }

    final SupportTicketDraft draft = SupportTicketDraft(
      id: _draftId,
      createdAt: _createdAt,
      subject: subject,
      message: message,
      context: null,
    );

    SupportTicketQueue.instance.upsertDraft(draft);

    safeShowSnackBar(
      context,
      "Draft saved on this device.",
    );
  }

  Future<void> _sendViaEmail() async {
    final String subject = _subjectController.text.trim();
    final String message = _messageController.text.trim();

    if (subject.isEmpty && message.isEmpty) {
      safeShowSnackBar(
        context,
        "Please add a subject or message before sending.",
      );
      return;
    }

    final Uri uri = Uri(
      scheme: "mailto",
      path: "support@prox-us.com",
      query: Uri.encodeQueryComponent(
        "subject=Prox tester feedback: $subject"
        "&body=$message",
      ),
    );

    final bool ok = await launchUrl(uri);
    if (!mounted) return;

    if (!ok) {
      safeShowSnackBar(
        context,
        "Could not open email app. Draft is still saved.",
      );
      _saveDraft();
      return;
    }

    // Consider the draft "sent" and remove it from the local queue.
    SupportTicketQueue.instance.removeDraft(_draftId);

    safeShowSnackBar(
      context,
      "Email app opened. Once sent, this draft is cleared.",
    );

    Navigator.of(context).maybePop();
  }

  Future<void> _submitInAppTicket() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final String subject = _subjectController.text.trim();
    final String message = _messageController.text.trim();

    if (uid.isEmpty) {
      safeShowSnackBar(context, "Sign in first to submit support tickets.");
      return;
    }

    if (subject.isEmpty || message.isEmpty) {
      safeShowSnackBar(context, "Please add both subject and message before submitting.");
      return;
    }

    try {
      final ticket = SupportTicket(
        id: "",
        userId: uid,
        technicianId: "",
        subject: subject,
        description: message,
        status: SupportTicketStatus.open,
        createdAt: DateTime.now(),
        resolvedAt: null,
      );

      await SupportService.instance.createTicket(ticket);
      SupportTicketQueue.instance.removeDraft(_draftId);

      if (!mounted) return;
      safeShowSnackBar(context, "Support ticket submitted.");
      Navigator.of(context).maybePop();
    } catch (e) {
      _saveDraft();
      if (!mounted) return;
      safeShowSnackBar(context, "Submit failed; draft saved locally. Error: $e");
    }
  }
}
