import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:prox/models/support_ticket.dart';
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
    _draftId = draft?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _createdAt = draft?.createdAt ?? DateTime.now();
    _subjectController = TextEditingController(text: draft?.subject ?? '');
    _messageController = TextEditingController(text: draft?.message ?? '');
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
      await SupportService.instance
          .createTicket(
            SupportTicket(
              id: _draftId,
              userId: uid,
              subject: subject,
              description: message,
              status: SupportTicketStatus.open,
              createdAt: _createdAt,
            ),
          )
          .timeout(const Duration(seconds: 20));
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
          enabled: !_busy,
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
          enabled: !_busy,
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
        const Text(
          'Include your phone model and app version. Avoid passwords or payment details.',
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
