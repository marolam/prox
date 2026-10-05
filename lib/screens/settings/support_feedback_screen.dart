import 'dart:async';

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import 'package:firebase_auth/firebase_auth.dart';

import "package:prox/services/feedback_service.dart";
import 'package:prox/services/support_service.dart';
import 'package:prox/screens/support/user_support_screen.dart';
import 'package:prox/models/support_ticket_draft.dart';
import 'package:prox/services/support_ticket_queue.dart';

typedef FeedbackSubmitter =
    Future<void> Function({
      required ProxFeedbackType type,
      required String text,
      String? firstHuhMoment,
      String source,
    });

class SupportFeedbackScreen extends StatefulWidget {
  const SupportFeedbackScreen({
    super.key,
    this.submitFeedback,
    this.submitReport,
    this.pickScreenshot,
    this.loadMetadata,
  });

  final FeedbackSubmitter? submitFeedback;
  final Future<String> Function(SupportReportRequest request)? submitReport;
  final Future<SupportAttachment?> Function()? pickScreenshot;
  final Future<Map<String, String>> Function()? loadMetadata;

  @override
  State<SupportFeedbackScreen> createState() => _SupportFeedbackScreenState();
}

class _SupportFeedbackScreenState extends State<SupportFeedbackScreen> {
  ProxFeedbackType _type = ProxFeedbackType.bug;
  SupportCategory _category = SupportCategory.bug;
  int _devComboStep = 0;
  String _requestId = SupportService.newRequestId();
  String? _ownerUid;
  Map<String, String> _metadata = const {};
  SupportAttachment? _attachment;
  SupportReportRequest? _pendingRequest;
  String? _lastTicketId;
  String? _attachmentError;
  bool _picking = false;
  Timer? _saveTimer;
  final DateTime _draftCreated = DateTime.now();

  String _subject(String body) {
    final subject = '${_category.label}: ${body.split('\n').first}';
    return subject.substring(0, subject.length.clamp(0, 120));
  }

  void _changed() {
    setState(() {});
    if (_ownerUid == null ||
        widget.submitFeedback != null ||
        widget.submitReport != null)
      return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  Future<void> _saveDraft() async {
    final body = _text.text.trim();
    if (_ownerUid == null ||
        body.isEmpty ||
        widget.submitFeedback != null ||
        widget.submitReport != null)
      return;
    final draft = SupportTicketDraft(
      id: _requestId,
      subject: _subject(body),
      message: body,
      createdAt: _draftCreated,
      category: _category.name,
      firstHuhMoment: _huh.text.trim(),
    );
    try {
      if (FirebaseAuth.instance.currentUser?.uid != _ownerUid) return;
      await SupportTicketQueue.instance.upsertDraft(draft);
    } catch (_) {
      /* Keep entered text available for an immediate retry. */
    }
  }

  final TextEditingController _text = TextEditingController();
  final TextEditingController _huh = TextEditingController();

  bool _submitting = false;

  bool get _canSubmit => _text.text.trim().isNotEmpty;
  bool get _locked => _submitting || _pendingRequest != null;

  @override
  void initState() {
    super.initState();
    try {
      _ownerUid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {}
    if (_ownerUid != null || widget.loadMetadata != null) {
      _refreshMetadata();
    }
  }

  Future<void> _refreshMetadata() async {
    try {
      final metadata =
          await (widget.loadMetadata ?? SupportService.collectMetadata)();
      if (mounted) setState(() => _metadata = metadata);
    } catch (_) {
      /* Metadata availability must not block reporting. */
    }
  }

  Future<void> _pickAttachment() async {
    if (_locked || _picking) return;
    setState(() {
      _picking = true;
      _attachmentError = null;
    });
    try {
      final image =
          await (widget.pickScreenshot ?? SupportService.pickScreenshot)();
      if (mounted && image != null) setState(() => _attachment = image);
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _attachmentError = '${error.message}');
    } catch (_) {
      if (mounted)
        setState(
          () => _attachmentError = 'Could not open your photos. Try again.',
        );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  static const String _elaborateUrl = "https://prox-us.com/support";
  static const List<ProxFeedbackType> _devComboPattern = <ProxFeedbackType>[
    ProxFeedbackType.feedback,
    ProxFeedbackType.bug,
    ProxFeedbackType.comment,
  ];
  static const int _devComboCycles = 5;

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveDraft();
    _text.dispose();
    _huh.dispose();
    super.dispose();
  }

  Future<void> _copyElaborateLink() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(const ClipboardData(text: _elaborateUrl));
    messenger.showSnackBar(
      const SnackBar(
        content: Text("Link copied. Paste into your browser to elaborate."),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || _picking) return;
    final messenger = ScaffoldMessenger.of(context);

    final body = _text.text.trim();
    if (body.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text("Type a quick note first.")),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (widget.submitFeedback case final FeedbackSubmitter submitter) {
        await submitter(
          type: _type,
          text: body,
          firstHuhMoment: _huh.text.trim(),
          source: 'settings_support_feedback',
        );
      } else {
        _saveTimer?.cancel();
        await _saveDraft();
        _pendingRequest ??= SupportReportRequest(
          requestId: _requestId,
          category: _category,
          subject: _subject(body),
          message: body,
          firstHuhMoment: _huh.text.trim(),
          source: 'settings_support_feedback',
          metadata: Map.unmodifiable(_metadata),
          attachment: _attachment,
          expectedUid: _ownerUid,
        );
        _lastTicketId =
            await (widget.submitReport ?? SupportService.instance.submitReport)(
              _pendingRequest!,
            );
        if (widget.submitReport == null) {
          try {
            await SupportTicketQueue.instance.removeDraft(_requestId);
          } catch (_) {}
        }
      }

      if (!mounted) return;

      _text.clear();
      _huh.clear();
      _pendingRequest = null;
      _requestId = SupportService.newRequestId();
      _attachment = null;

      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text("${_category.label} sent. Thank you.")),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't send right now. Please try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _selectTypeFromChip(ProxFeedbackType selectedType) {
    setState(() => _type = selectedType);
    _trackDevCombo(selectedType);
  }

  void _selectCategory(SupportCategory category) {
    setState(() => _category = category);
    _selectTypeFromChip(switch (category) {
      SupportCategory.bug => ProxFeedbackType.bug,
      SupportCategory.feature ||
      SupportCategory.ux => ProxFeedbackType.feedback,
      SupportCategory.billing ||
      SupportCategory.question => ProxFeedbackType.comment,
    });
    _changed();
  }

  void _trackDevCombo(ProxFeedbackType selectedType) {
    final expected = _devComboPattern[_devComboStep % _devComboPattern.length];
    if (selectedType == expected) {
      _devComboStep += 1;
    } else {
      _devComboStep = selectedType == _devComboPattern.first ? 1 : 0;
    }

    final neededSteps = _devComboPattern.length * _devComboCycles;
    if (_devComboStep >= neededSteps) {
      _devComboStep = 0;
      if (!mounted) return;
      Navigator.of(context).pushNamed("/dev/menu");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final tip = switch (_type) {
      ProxFeedbackType.bug =>
        "Bug reports that include the screen you were on + what you tapped are legendary.",
      ProxFeedbackType.feedback =>
        "Feature ideas are best when they start with the goal (what you wanted to do).",
      ProxFeedbackType.comment =>
        "Quick vibes are useful too. Confusing? Smooth? Creepy? Great? Tell us.",
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text("Support & feedback"),
        actions: [
          IconButton(
            tooltip: 'My support tickets',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const UserSupportScreen(),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _submitting || _picking || !_canSubmit
                      ? null
                      : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_submitting ? 'Sending...' : 'Send'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _copyElaborateLink,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Elaborate'),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.support_agent_outlined, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Report an issue, suggest a feature, or ask for help.\n"
                      "App version and device details are attached automatically.\n"
                      "Track replies and fixes in My support tickets.",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Text(
              "Category",
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in SupportCategory.values)
                  ChoiceChip(
                    selected: _category == category,
                    label: Text(category.label),
                    onSelected: _locked
                        ? null
                        : (_) => _selectCategory(category),
                  ),
              ],
            ),

            const SizedBox(height: 12),
            Text(
              tip,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _text,
              enabled: !_locked,
              maxLength: 5000,
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => _changed(),
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: _type == ProxFeedbackType.bug
                    ? "What broke?"
                    : "What is on your mind?",
                hintText: _type == ProxFeedbackType.bug
                    ? "Example: Nearby list shows someone as fresh even when they were offline."
                    : "Example: I want a Meetup Now button on the chat header.",
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _huh,
              enabled: !_locked,
              maxLength: 500,
              onChanged: (_) => _changed(),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: "First confusion moment (optional)",
                hintText:
                    "Example: I did not understand Party vs Public at first.",
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _locked || _picking ? null : _pickAttachment,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _picking ? 'Opening photos...' : 'Attach screenshot (optional)',
              ),
            ),
            if (_attachment != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Screenshot attached'),
                  subtitle: Text(
                    '${(_attachment!.bytes.length / 1024).ceil()} KB · Private to you and support',
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove screenshot',
                    onPressed: _locked
                        ? null
                        : () => setState(() => _attachment = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            if (_attachmentError != null)
              Text(_attachmentError!, style: TextStyle(color: cs.error)),
            if (_metadata.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Automatically attached: ${_metadata['version']} '
                  '(build ${_metadata['build']}) · ${_metadata['platform']} · '
                  '${_metadata['device']} · ${_metadata['os']}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (_pendingRequest != null && !_submitting)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Your report is kept unchanged for a safe retry. Tap Send to confirm the same report.',
                ),
              ),
            if (_lastTicketId != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Report received'),
                  subtitle: Text('Reference: $_lastTicketId'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const UserSupportScreen(),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 12),
            Text(
              "Elaborate copies the support link so you can paste it into your browser. "
              "We keep the in-app flow fast to maximize response rate.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
