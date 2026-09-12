import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

typedef SaveMeetupRating =
    Future<String> Function(bool thumb, String partyDecision, String comment);

Future<bool> confirmPartyDecision(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ==
    true;

class MeetupRatingForm extends StatefulWidget {
  const MeetupRatingForm({
    super.key,
    required this.save,
    this.onCompleted,
    this.partyRequiresNormalMode = false,
  });
  final bool partyRequiresNormalMode;
  final SaveMeetupRating save;
  final void Function(String status)? onCompleted;
  @override
  State<MeetupRatingForm> createState() => _MeetupRatingFormState();
}

class _MeetupRatingFormState extends State<MeetupRatingForm> {
  bool _upSelected = false;
  bool _busy = false;
  String? _error;
  String? _saved;
  String _commentDraft = '';
  Future<void> _save(bool thumb, String choice, String comment) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await widget
          .save(thumb, choice, comment)
          .timeout(const Duration(seconds: 35));
      if (!mounted) return;
      setState(
        () => _saved = status == 'connected'
            ? 'You are now in each other’s Party.'
            : status == 'pending'
            ? 'Rating saved. Find this connection in Pending Party Add.'
            : 'Your feedback is saved.',
      );
      widget.onCompleted?.call(status);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is FirebaseFunctionsException
            ? (error.message ?? 'Could not save. Please try again.')
            : 'Could not save your response. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseParty(bool add) async {
    final confirmed = await confirmPartyDecision(
      context,
      title: add ? 'Add to Party?' : 'Not Right Now?',
      message:
          (add && widget.partyRequiresNormalMode
              ? 'This also switches you to Normal Mode so you can open Party. '
              : '') +
          (add
              ? 'When you both choose Add to Party, you will appear in each other’s Party and share the profile information each of you marked Party Visible.'
              : 'You will not be added to each other’s Party. You can reconsider in Pending Party Add, which expires after 7 days without activity.'),
      confirmLabel: add ? 'Add to Party' : 'Not Right Now',
    );
    if (confirmed && mounted) await _save(true, add ? 'add' : 'later', '');
  }

  Future<void> _thumbDown() async {
    final note = TextEditingController(text: _commentDraft);
    final comment = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How Did The Meetup Go?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Submit a thumbs-down rating? You may add details below. Your comment is not shared with your meetup partner.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, note.text.trim()),
            child: const Text('Submit feedback'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    note.dispose();
    if (comment != null && mounted) {
      _commentDraft = comment;
      await _save(false, 'later', comment);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'How Did The Meetup Go?',
        style: Theme.of(context).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      if (_saved == null) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Thumbs up',
              isSelected: _upSelected,
              icon: const Icon(Icons.thumb_up_outlined, size: 40),
              selectedIcon: const Icon(Icons.thumb_up, size: 40),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _upSelected = true;
                      _error = null;
                    }),
            ),
            const SizedBox(width: 32),
            IconButton(
              tooltip: 'Thumbs down',
              icon: const Icon(Icons.thumb_down_outlined, size: 40),
              onPressed: _busy ? null : _thumbDown,
            ),
          ],
        ),
        if (_upSelected) ...[
          const SizedBox(height: 20),
          const Text('Would you like to add this person to Party?'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _chooseParty(true),
                child: const Text('Add to Party'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _chooseParty(false),
                child: const Text('Not Right Now'),
              ),
            ],
          ),
        ],
      ],
      if (_busy)
        const Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (_saved != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_saved!, textAlign: TextAlign.center),
        ),
    ],
  );
}
