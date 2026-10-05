import 'dart:async';
import 'package:flutter/material.dart';
import 'package:prox/screens/business/business_offers_screen.dart';
import 'package:prox/screens/profile/profile_edit_screen.dart';
import 'package:prox/services/business_mode/business_storefront_service.dart';

class ProStorefrontScreen extends StatefulWidget {
  const ProStorefrontScreen({super.key, this.repository});
  final BusinessStorefrontRepository? repository;

  @override
  State<ProStorefrontScreen> createState() => _ProStorefrontScreenState();
}

class _ProStorefrontScreenState extends State<ProStorefrontScreen> {
  late final BusinessStorefrontRepository _repository;
  String? _uid;
  StreamSubscription<String?>? _account;
  BusinessStorefrontDetails? _details;
  bool _loading = true;
  bool _saving = false;
  bool _accountChanged = false;
  bool _failed = false;
  final _hours = TextEditingController();
  final _area = TextEditingController();
  final _terms = TextEditingController();

  bool get _sameAccount =>
      !_accountChanged && _uid != null && _repository.currentUid == _uid;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? BusinessStorefrontService.instance;
    _uid = _repository.currentUid;
    _account = _repository.watchUid().listen((uid) {
      if (!mounted || uid == _uid) return;
      _hours.clear();
      _area.clear();
      _terms.clear();
      setState(() {
        _details = null;
        _accountChanged = true;
      });
    });
    _load();
  }

  Future<void> _load() async {
    if (!_sameAccount) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final details = await _repository.load(_uid!);
      if (!mounted || !_sameAccount) return;
      _hours.text = details.hoursText;
      _area.text = details.serviceAreaText;
      _terms.text = details.meetupTerms;
      setState(() => _details = details);
    } catch (_) {
      if (mounted && _sameAccount) setState(() => _failed = true);
    } finally {
      if (mounted && _sameAccount) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_sameAccount || _saving) return;
    final details = BusinessStorefrontDetails(
      hoursText: _hours.text,
      serviceAreaText: _area.text,
      meetupTerms: _terms.text,
    );
    setState(() => _saving = true);
    try {
      await _repository.save(_uid!, details);
      if (!mounted || !_sameAccount) return;
      setState(() => _details = details);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Service details saved.')));
    } catch (_) {
      if (!mounted || !_sameAccount) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save your service details. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _open(Widget page) {
    if (!_sameAccount || _saving) return;
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  @override
  void dispose() {
    _account?.cancel();
    _hours.dispose();
    _area.dispose();
    _terms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Storefront')),
    body: !_sameAccount
        ? const Center(
            child: Text('Sign in and reopen Storefront to continue.'),
          )
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : _failed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your storefront settings.'),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                'Your service details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Save your hours, service area, and terms for future offers. Review each offer before sharing it with customers.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hours,
                enabled: !_saving,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Hours and service windows',
                  hintText:
                      'Mon–Fri 9am–5pm, by appointment. Include your time zone.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _area,
                enabled: !_saving,
                maxLength: 500,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Service area',
                  hintText: 'Cities, neighborhoods, or travel radius',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _terms,
                enabled: !_saving,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Meetup and service terms',
                  hintText: 'Confirm price, preparation, and location in chat.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save service details'),
              ),
              if (_details != null &&
                  _details!.hoursText.isEmpty &&
                  _details!.serviceAreaText.isEmpty &&
                  _details!.meetupTerms.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No service details saved yet.'),
                ),
              const Divider(height: 32),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Availability and public profile'),
                subtitle: const Text(
                  'Set ready-now status and the details on your profile',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _saving
                    ? null
                    : () =>
                          _open(const ProfileEditScreen(fromOnboarding: false)),
              ),
              ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: const Text('Deals and local offers'),
                subtitle: const Text('Create, review, and manage your offers'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _saving
                    ? null
                    : () => _open(const BusinessOffersScreen()),
              ),
            ],
          ),
  );
}
