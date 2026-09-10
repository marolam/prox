import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReportComposeScreen extends StatefulWidget {
  const ReportComposeScreen({super.key, required this.incident});
  final bool incident;

  @override
  State<ReportComposeScreen> createState() => _ReportComposeScreenState();
}

class _ReportComposeScreenState extends State<ReportComposeScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _detail = TextEditingController();
  late final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  late final String _collection = widget.incident ? 'incidents' : 'bugReports';
  late final String _draftKey = 'report.draft.$_collection.$_uid';
  late String _reportId = FirebaseFirestore.instance
      .collection(_collection)
      .doc()
      .id;
  bool _loading = true;
  bool _sending = false;
  bool _submitted = false;
  String? _error;
  Timer? _debounce;
  Future<void> _pendingSave = Future.value();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (!mounted) return;
      if (raw != null) {
        final draft = jsonDecode(raw) as Map<String, dynamic>;
        _title.text = draft['title'] as String? ?? '';
        _detail.text = draft['detail'] as String? ?? '';
        _reportId = draft['id'] as String? ?? _reportId;
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not restore a saved draft.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDraft() {
    if (FirebaseAuth.instance.currentUser?.uid != _uid) return Future.value();
    final data = jsonEncode({
      'title': _title.text,
      'detail': _detail.text,
      'id': _reportId,
    });
    _pendingSave = _pendingSave.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(_draftKey, data))
          throw StateError('Storage unavailable');
      } catch (_) {
        if (mounted)
          setState(
            () => _error =
                'Draft could not be saved on this device. Keep this screen open and retry.',
          );
      }
    });
    return _pendingSave;
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_uid == null || FirebaseAuth.instance.currentUser?.uid != _uid) {
      setState(() => _error = 'Sign in again before submitting this report.');
      return;
    }
    _debounce?.cancel();
    setState(() {
      _sending = true;
      _error = null;
    });
    await _saveDraft();
    try {
      final data = widget.incident
          ? <String, dynamic>{
              'reporterUid': _uid,
              'otherUid': '',
              'meetupId': '',
              'reason': _title.text.trim(),
              'detail': _detail.text.trim(),
              'severity': 'review',
            }
          : <String, dynamic>{
              'ownerUid': _uid,
              'title': _title.text.trim(),
              'description': _detail.text.trim(),
              'route': 'manual_report',
            };
      final ref = FirebaseFirestore.instance
          .collection(_collection)
          .doc(_reportId);
      await ref
          .set({
            ...data,
            'status': 'open',
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 20));
      _submitted = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_draftKey);
      } catch (_) {
        /* The confirmed server record remains the source of truth. */
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. Track its status in your reports.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Submission could not be confirmed. Your draft is kept; reconnect and retry.',
        );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (!_loading && !_sending && !_submitted) _saveDraft();
    _title.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.incident ? 'Report an incident or appeal' : 'Report a bug',
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.incident
                      ? 'Describe the incident, or include the original report reference when appealing a decision. For an immediate emergency, contact local emergency services.'
                      : 'Describe what you expected, what happened instead, and the steps that reproduce the problem.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  enabled: !_sending,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Summary'),
                  onChanged: _changed,
                  validator: (v) => (v?.trim().length ?? 0) < 3
                      ? 'Add a short summary (at least 3 characters).'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _detail,
                  enabled: !_sending,
                  maxLength: 5000,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Details',
                    hintText:
                        'Include relevant dates and a meetup or report reference, if available.',
                  ),
                  onChanged: _changed,
                  validator: (v) => (v?.trim().length ?? 0) < 10
                      ? 'Please provide at least 10 characters of detail.'
                      : null,
                ),
                const Text(
                  'Your draft is saved on this device as you type. Avoid including passwords or payment details.',
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(_sending ? 'Submitting…' : 'Submit report'),
                ),
              ],
            ),
          ),
  );
}
