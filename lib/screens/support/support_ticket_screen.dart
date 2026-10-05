import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:prox/services/support_service.dart';
import 'package:prox/widgets/support_attachment_preview.dart';

typedef SupportReplySender =
    Future<void> Function({
      required String ticketId,
      required String requestId,
      required String message,
    });

class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen({
    super.key,
    required this.ticket,
    this.ticketUpdates,
    this.replies,
    this.sendReply,
    this.loadAttachment,
    this.allowReply = true,
  });
  factory SupportTicketScreen.forTicketId({
    Key? key,
    required String ticketId,
    bool allowReply = false,
  }) => SupportTicketScreen(
    key: key,
    ticket: TrackedSupportTicket(
      id: ticketId,
      subject: 'Support report',
      message: '',
    ),
    allowReply: allowReply,
  );
  final TrackedSupportTicket ticket;
  final Stream<TrackedSupportTicket>? ticketUpdates;
  final Stream<List<SupportReply>>? replies;
  final SupportReplySender? sendReply;
  final Future<Uint8List?> Function(String path)? loadAttachment;
  final bool allowReply;

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  final _reply = TextEditingController();
  late Stream<TrackedSupportTicket> _tickets;
  late Stream<List<SupportReply>> _replies;
  bool _sending = false;
  String? _error;
  String? _pendingMessage;
  String _requestId = SupportService.newRequestId();
  StreamSubscription<User?>? _auth;
  bool _accessLost = false;
  @override
  void initState() {
    super.initState();
    _tickets =
        widget.ticketUpdates ??
        SupportService.instance.watchTicket(widget.ticket.id);
    _replies =
        widget.replies ??
        SupportService.instance.watchReplies(widget.ticket.id);
    if (widget.ticketUpdates == null) {
      final ownerUid = FirebaseAuth.instance.currentUser?.uid;
      _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user?.uid != ownerUid && mounted) {
          setState(() {
            _accessLost = true;
            _reply.clear();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _auth?.cancel();
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_accessLost || _sending || _reply.text.trim().isEmpty) return;
    _pendingMessage ??= _reply.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await (widget.sendReply ?? SupportService.instance.sendReply)(
        ticketId: widget.ticket.id,
        requestId: _requestId,
        message: _pendingMessage!,
      );
      if (!mounted) return;
      _reply.clear();
      _pendingMessage = null;
      _requestId = SupportService.newRequestId();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reply sent.')));
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Your reply could not be confirmed. Retry to send the same reply once.',
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Support ticket')),
    body: StreamBuilder<TrackedSupportTicket>(
      stream: _tickets,
      initialData: widget.ticket,
      builder: (context, snapshot) {
        // Access can change after sign-out; never keep showing cached private content.
        if (_accessLost || snapshot.hasError)
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This ticket is unavailable. Sign in to the reporting account and reopen it.',
              ),
            ),
          );
        final ticket = snapshot.data ?? widget.ticket;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(ticket.subject, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${ticket.statusLabel} · ${ticket.category}'),
            if (ticket.acknowledgement.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(ticket.acknowledgement),
              ),
            if (ticket.fixedLabel.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline),
                      const SizedBox(width: 12),
                      Expanded(child: Text(ticket.fixedLabel)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SelectableText(ticket.message),
            for (final path in ticket.attachmentPaths)
              SupportAttachmentPreview(
                path: path,
                loadAttachment: widget.loadAttachment,
              ),
            const SizedBox(height: 12),
            SelectableText(
              'Reference: ${ticket.id}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 32),
            Text(
              'Conversation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            StreamBuilder<List<SupportReply>>(
              stream: _replies,
              builder: (context, replies) {
                if (replies.hasError)
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Replies could not be loaded. Reopen this ticket to retry.',
                    ),
                  );
                if (!replies.hasData)
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  );
                if (replies.data!.isEmpty)
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No replies yet. Support replies will appear here.',
                    ),
                  );
                return Column(
                  children: [
                    for (final reply in replies.data!)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reply.fromSupport ? 'Prox support' : 'You',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(reply.message),
                              if (reply.createdAt != null)
                                Text(
                                  '${reply.createdAt!.toLocal()}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (widget.allowReply)
              TextField(
                controller: _reply,
                enabled: !_sending && _pendingMessage == null,
                minLines: 2,
                maxLines: 5,
                maxLength: 5000,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Add a reply',
                  hintText: 'Share more details or ask a follow-up question.',
                ),
              ),
            if (widget.allowReply && _error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (widget.allowReply)
              FilledButton.icon(
                onPressed: _sending || _reply.text.trim().isEmpty
                    ? null
                    : _send,
                icon: const Icon(Icons.send),
                label: Text(_sending ? 'Sending...' : 'Send reply'),
              ),
          ],
        );
      },
    ),
  );
}
