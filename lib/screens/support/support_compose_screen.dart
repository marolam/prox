import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:prox/models/support_ticket_draft.dart';
import 'package:prox/services/support_service.dart';
import 'package:prox/services/support_ticket_queue.dart';
import 'package:prox/services/support_email.dart';
import 'package:prox/widgets/safe_snack.dart';

class SupportComposeScreen extends StatefulWidget {
  const SupportComposeScreen({super.key, this.existingDraft});
  final SupportTicketDraft? existingDraft;
  @override
  State<SupportComposeScreen> createState() => _SupportComposeScreenState();
}

class _SupportComposeScreenState extends State<SupportComposeScreen> {
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  late final String _draftId;
  late final DateTime _createdAt;
  late final String? _ownerUid;
  Timer? _debounce;
  bool _busy = false;
  bool _submitted = false;
  String? _error;
  SupportCategory _category = SupportCategory.question;
  SupportAttachment? _attachment;
  Map<String, String> _metadata = const {};
  SupportReportRequest? _pendingReport;

  String? _currentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.existingDraft;
    _ownerUid = _currentUid();
    _draftId = draft?.id ?? SupportService.newRequestId();
    _createdAt = draft?.createdAt ?? DateTime.now();
    _subjectController = TextEditingController(text: draft?.subject ?? '');
    _messageController = TextEditingController(text: draft?.message ?? '');
    _category = SupportCategory.values.firstWhere(
      (value) => value.name == draft?.category,
      orElse: () => SupportCategory.question,
    );
    SupportService.collectMetadata()
        .then((value) {
          if (mounted) setState(() => _metadata = value);
        })
        .catchError((Object _) {});
    SupportTicketQueue.instance.ensureLoaded().catchError((Object _) {
      if (mounted)
        setState(
          () => _error =
              'Saved drafts could not be loaded. Retry saving before leaving.',
        );
    });
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _saveDraft(showMessage: false),
    );
  }

  Future<bool> _saveDraft({bool showMessage = true}) async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty && message.isEmpty) return false;
    if (_ownerUid != _currentUid()) return false;
    try {
      await SupportTicketQueue.instance.upsertDraft(
        SupportTicketDraft(
          id: _draftId,
          createdAt: _createdAt,
          subject: subject,
          message: message,
          category: _category.name,
          firstHuhMoment: widget.existingDraft?.firstHuhMoment ?? '',
        ),
      );
      if (mounted && showMessage)
        safeShowSnackBar(context, 'Draft saved on this device.');
      return true;
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not save the draft. Keep this screen open and try again.',
        );
      return false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (!_submitted) _saveDraft(showMessage: false);
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendViaEmail() async {
    if (_busy) return;
    if (_subjectController.text.trim().isEmpty &&
        _messageController.text.trim().isEmpty) {
      safeShowSnackBar(context, 'Add a subject or message first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _debounce?.cancel();
    await _saveDraft(showMessage: false);
    if (!mounted) return;
    try {
      final uri = supportEmailUri(
        subject: 'Prox feedback: ${_subjectController.text.trim()}',
        body: _messageController.text.trim(),
      );
      final opened = await launchUrl(uri);
      if (!mounted) return;
      if (!opened) {
        setState(
          () => _error =
              'Could not open an email app. You can submit in app or retry.',
        );
        return;
      }
      safeShowSnackBar(
        context,
        'Email app opened. Your draft is kept until you delete it; sending is confirmed in your email app.',
      );
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'Could not open an email app. Try submitting in app.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitInAppTicket() async {
    if (_busy) return;
    final uid = _currentUid();
    if (uid == null || uid != _ownerUid) {
      safeShowSnackBar(context, 'Sign in to submit this support ticket.');
      return;
    }
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      safeShowSnackBar(context, 'Add both a subject and message.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _debounce?.cancel();
    await _saveDraft(showMessage: false);
    try {
      _pendingReport ??= SupportReportRequest(
        requestId: _draftId,
        category: _category,
        subject: subject,
        message: message,
        expectedUid: _ownerUid,
        metadata: Map.unmodifiable(_metadata),
        attachment: _attachment,
        source: 'support_compose',
        firstHuhMoment: widget.existingDraft?.firstHuhMoment ?? '',
      );
      await SupportService.instance.submitReport(_pendingReport!);
      _submitted = true;
      try {
        await SupportTicketQueue.instance.removeDraft(_draftId);
      } catch (_) {
        /* Submission is confirmed even if local cleanup fails. */
      }
      if (!mounted) return;
      safeShowSnackBar(context, 'Support ticket submitted.');
      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Submission could not be confirmed. Check your connection and retry; your saved draft stays on this device.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existingDraft == null
            ? 'New support message'
            : 'Edit support message',
      ),
    ),
    body: ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Drafts are saved on this device as you type. Submit in app to track your ticket, or open an email draft.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _subjectController,
          enabled: !_busy && _pendingReport == null,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          onChanged: _changed,
          decoration: const InputDecoration(
            labelText: 'Subject',
            hintText: 'Short summary of the problem',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _messageController,
          enabled: !_busy && _pendingReport == null,
          maxLength: 5000,
          keyboardType: TextInputType.multiline,
          minLines: 5,
          maxLines: 10,
          onChanged: _changed,
          decoration: const InputDecoration(
            labelText: 'What happened?',
            hintText:
                'What did you expect, what happened instead, and how can we reproduce it?',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SupportCategory>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            for (final value in SupportCategory.values)
              DropdownMenuItem(value: value, child: Text(value.label)),
          ],
          onChanged: _busy || _pendingReport != null
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _category = value);
                    _changed('');
                  }
                },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy || _pendingReport != null
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final image = await SupportService.pickScreenshot();
                    if (mounted && image != null)
                      setState(() => _attachment = image);
                  } on ArgumentError catch (error) {
                    if (mounted) setState(() => _error = '${error.message}');
                  } catch (_) {
                    if (mounted)
                      setState(
                        () => _error = 'Could not open your photos. Try again.',
                      );
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Attach screenshot (optional)'),
        ),
        if (_attachment != null)
          ListTile(
            title: const Text('Screenshot attached'),
            subtitle: const Text(
              'Private to you and support. Reselect it if you reopen this draft.',
            ),
            trailing: IconButton(
              tooltip: 'Remove screenshot',
              icon: const Icon(Icons.close),
              onPressed: _busy || _pendingReport != null
                  ? null
                  : () => setState(() => _attachment = null),
            ),
          ),
        Text(
          'App version and device details are attached automatically. Avoid passwords or payment details.'
          '${_metadata.isEmpty ? '' : '\n${_metadata['version']} (build ${_metadata['build']}) · ${_metadata['platform']} · ${_metadata['device']}'}',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        if (_busy)
          const LinearProgressIndicator(
            semanticsLabel: 'Sending support message',
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _saveDraft(),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save draft'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _submitInAppTicket,
              icon: const Icon(Icons.support_agent_outlined),
              label: const Text('Submit in app'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _sendViaEmail,
              icon: const Icon(Icons.email_outlined),
              label: const Text('Open email draft'),
            ),
          ],
        ),
      ],
    ),
  );
}
