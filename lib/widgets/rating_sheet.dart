import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "package:prox/services/meetup_service.dart";
import "package:prox/services/ratings_service.dart";

class RatingSheet extends StatefulWidget {
  final String chatId;
  final String peerUid;
  final String? meetupId;

  const RatingSheet({
    super.key,
    required this.chatId,
    required this.peerUid,
    this.meetupId,
  });

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  bool _thumbUp = true;
  bool _addToParty = true;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _meetupDocId => (widget.meetupId ?? widget.chatId).trim();

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<bool> _ensureOpenWindow() async {
    if (_meetupDocId.isEmpty) return true;

    // Best-effort: keep existing RatingService window logic in place.
    try {
      await RatingsService.instance.ensureRatingWindow(_meetupDocId);
      return await RatingsService.instance.isRatingWindowOpen(_meetupDocId);
    } catch (_) {
      return true; // don't block testers on transient failures
    }
  }

  Future<void> _submit() async {
    HapticFeedback.selectionClick();
    if (_saving) return;

    setState(() => _saving = true);

    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      _snack("Sign in to submit a rating.");
      if (mounted) setState(() => _saving = false);
      return;
    }

    final myUid = me.uid;
    final peerUid = widget.peerUid.trim();
    if (peerUid.isEmpty) {
      _snack("Missing peer.");
      if (mounted) setState(() => _saving = false);
      return;
    }

    try {
      final open = await _ensureOpenWindow();
      if (!open) {
        _snack("Rating window closed.");
        if (mounted) Navigator.of(context).maybePop();
        return;
      }

      await MeetupService.instance.submitThumb(
        chatId: widget.chatId,
        raterUid: myUid,
        ratedUid: peerUid,
        thumb: _thumbUp,
        reason: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );

      if (_thumbUp && _addToParty) {
        await MeetupService.instance.addToParty(
          meUid: myUid,
          friendUid: peerUid,
          source: "postMeetup",
        );
      }

      _snack(_thumbUp ? "Saved. Thanks!" : "Saved. Feedback noted.");
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      _snack("Could not submit: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget choiceButton({
      required bool selected,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      final Widget inner = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      );

      if (selected) {
        return FilledButton(
          onPressed: _saving ? null : onTap,
          child: inner,
        );
      }

      return OutlinedButton(
        onPressed: _saving ? null : onTap,
        child: inner,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Quick review",
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                "Would you meet up with them again?",
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: choiceButton(
                      selected: _thumbUp,
                      icon: Icons.thumb_up_alt_outlined,
                      label: "Yes",
                      onTap: () => setState(() => _thumbUp = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: choiceButton(
                      selected: !_thumbUp,
                      icon: Icons.thumb_down_alt_outlined,
                      label: "No",
                      onTap: () => setState(() => _thumbUp = false),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              TextField(
                controller: _note,
                maxLines: 3,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: "Optional note",
                ),
              ),

              if (_thumbUp) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Add to your Party?",
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Switch(
                      value: _addToParty,
                      onChanged: _saving ? null : (v) => setState(() => _addToParty = v),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? "Saving..." : "Submit"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}