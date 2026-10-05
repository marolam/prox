import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:prox/models/business_offer.dart';
import 'package:prox/services/business_mode/business_offers_service.dart';

String _offerError(Object error) => error is FirebaseFunctionsException
    ? error.message ?? 'Offer action failed. Retry or refresh.'
    : error is StateError ? '${error.message}' : 'Offers are unavailable. Please retry.';

class BusinessOffersScreen extends StatefulWidget {
  const BusinessOffersScreen({super.key, this.startCreating = false, this.initialBrowse = false, this.repository});
  final bool startCreating, initialBrowse;
  final BusinessOffersRepository? repository;
  @override State<BusinessOffersScreen> createState() => _BusinessOffersScreenState();
}

class _BusinessOffersScreenState extends State<BusinessOffersScreen> {
  late final BusinessOffersRepository _repository;
  String? _uid;
  StreamSubscription<String?>? _account;
  Stream<List<BusinessOffer>>? _owned, _queue;
  bool _canCreate = false, _admin = false, _checking = true, _changed = false, _busy = false;
  bool _browseLoading = false, _browseLoaded = false;
  String? _browseError, _cursor;
  String? _accessError;
  int _tab = 0;
  final _public = <BusinessOffer>[];
  final _requests = <String, String>{};
  @override void initState() {
    super.initState(); _repository = widget.repository ?? BusinessOffersService.instance;
    _uid = _repository.currentUid; _tab = widget.initialBrowse ? 1 : 0;
    if (_uid != null) _owned = _repository.watchOwned(_uid!);
    _account = _repository.watchUid().listen((uid) {
      if (!mounted || uid == _uid) return;
      setState(() { _changed = true; _public.clear(); _owned = null; _queue = null; _requests.clear(); });
    });
    unawaited(_loadAccess());
    if (_tab == 1) unawaited(_browse(refresh: true));
  }
  bool get _sameAccount => !_changed && _uid != null && _repository.currentUid == _uid;
  Future<void> _loadAccess() async {
    final uid = _uid; if (uid == null) { if (mounted) setState(() => _checking = false); return; }
    if (mounted) setState(() { _checking = true; _accessError = null; });
    try {
      final values = await Future.wait([_repository.canCreate(uid), _repository.isAdmin(uid)]);
      if (!mounted || !_sameAccount) return;
      setState(() { _canCreate = values[0]; _admin = values[1]; _checking = false; if (_admin) _queue = _repository.watchReviewQueue(uid); });
      if (widget.startCreating && _canCreate) unawaited(_edit());
    } catch (_) { if (mounted && _sameAccount) setState(() { _checking = false; _accessError = 'Pro access could not be checked. Please retry.'; }); }
  }
  Future<void> _browse({bool refresh = false}) async {
    if (!_sameAccount || _browseLoading) return;
    setState(() { _browseLoading = true; _browseError = null; if (refresh) { _public.clear(); _cursor = null; } });
    try {
      final page = await _repository.browse(_uid!, cursor: refresh ? null : _cursor);
      if (!mounted || !_sameAccount) return;
      setState(() { final ids = _public.map((offer) => offer.id).toSet(); _public.addAll(page.offers.where((offer) => ids.add(offer.id))); _cursor = page.nextCursor; _browseLoaded = true; });
    } catch (error) { if (mounted && _sameAccount) setState(() => _browseError = _offerError(error)); }
    finally { if (mounted && _sameAccount) setState(() => _browseLoading = false); }
  }
  Future<void> _edit([BusinessOffer? offer]) async {
    if (!_sameAccount || !_canCreate) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => _BusinessOfferEditor(repository: _repository, uid: _uid!, offer: offer)));
    if (mounted && _sameAccount && _browseLoaded) unawaited(_browse(refresh: true));
  }
  Future<void> _change(BusinessOffer offer, String action) async {
    if (!_sameAccount || _busy) return;
    if (action == 'delete') {
      final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete this offer?'), content: const Text('The offer and its publication will be removed.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
      if (confirm != true || !mounted || !_sameAccount) return;
    }
    final key = '${offer.id}:${offer.revision}:$action';
    final requestId = _requests.putIfAbsent(key, _repository.newId);
    setState(() => _busy = true);
    try {
      await _repository.change(_uid!, offer, action, requestId);
      if (mounted && _sameAccount) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action == 'submit' ? 'Submitted for human review.' : action == 'delete' ? 'Offer deleted.' : 'Offer paused.')));
    } catch (error) { if (mounted && _sameAccount) _message(_offerError(error)); }
    finally { if (mounted && _sameAccount) setState(() => _busy = false); }
  }
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _review(BusinessOffer offer, String decision) async {
    if (!_sameAccount || !_admin || _busy) return;
    final reason = await showDialog<String>(context: context, builder: (_) => _OfferReviewDialog(decision: decision, repository: _repository, uid: _uid!));
    if (reason == null || !mounted || !_sameAccount) return;
    final requestId = _requests.putIfAbsent('${offer.id}:${offer.revision}:$decision:$reason', _repository.newId);
    setState(() => _busy = true);
    try { await _repository.review(_uid!, offer, decision, reason, requestId); if (mounted && _sameAccount) _message(decision == 'approve' ? 'Offer published.' : 'Changes requested.'); }
    catch (error) { if (mounted && _sameAccount) _message(_offerError(error)); }
    finally { if (mounted && _sameAccount) setState(() => _busy = false); }
  }
  Widget _card(BusinessOffer offer, {bool owned = false, bool review = false}) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(offer.title, style: Theme.of(context).textTheme.titleMedium),
    if (!owned && !review && offer.ownerName.isNotEmpty) Text('From ${offer.ownerName}'),
    const SizedBox(height: 8), Text(offer.description),
    if (offer.discountPercent != null) Text('${offer.discountPercent}% off'),
    if (offer.terms.isNotEmpty) Text('Terms: ${offer.terms}'),
    if (offer.locationLabel.isNotEmpty) Text('Service area: ${offer.locationLabel}'),
    Text('${offer.visibility == 'party' ? 'Confirmed Party' : 'Public'} · Expires ${MaterialLocalizations.of(context).formatMediumDate(offer.expiresAt.toLocal())}'),
    if (owned || review) Text(offer.statusLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
    if (owned && offer.moderationReason.isNotEmpty) Text('Review: ${offer.moderationReason}'),
    if (!owned && !review) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Find this Pro in Nearby to request a conversation. Agree the details before planning a meetup.')),
    if (owned) Wrap(spacing: 8, children: [
      if (_canCreate) TextButton(onPressed: _busy ? null : () => _edit(offer), child: const Text('Edit')),
      if (_canCreate && !offer.expired && ['draft', 'rejected', 'paused'].contains(offer.status)) TextButton(onPressed: _busy ? null : () => _change(offer, 'submit'), child: const Text('Submit for review')),
      if (['active', 'pending_review'].contains(offer.status)) TextButton(onPressed: _busy ? null : () => _change(offer, 'withdraw'), child: const Text('Pause')),
      TextButton(onPressed: _busy ? null : () => _change(offer, 'delete'), child: const Text('Delete')),
    ]),
    if (review) Wrap(spacing: 8, children: [FilledButton(onPressed: _busy ? null : () => _review(offer, 'approve'), child: const Text('Approve')), OutlinedButton(onPressed: _busy ? null : () => _review(offer, 'reject'), child: const Text('Request changes'))]),
  ])));
  Widget _stream(Stream<List<BusinessOffer>>? stream, {bool review = false}) => StreamBuilder<List<BusinessOffer>>(stream: stream, builder: (context, snapshot) {
    if (snapshot.hasError) return const Center(child: Text('Offers unavailable. Reopen or try again later.'));
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    final offers = snapshot.data ?? const <BusinessOffer>[];
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (!review) const Text('Save private drafts, then submit for human review. Up to 20 saved offers and 5 published offers. Published offers are hidden when Pro access ends or they expire.'),
      if (!review && !_canCreate) Text(_checking ? 'Checking Pro access...' : _accessError ?? 'Creating or editing offers requires active paid Pro access. You can still pause or delete existing offers.'),
      if (!review && _accessError != null) TextButton(onPressed: _checking ? null : _loadAccess, child: const Text('Retry access check')),
      if (!review && _canCreate) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: FilledButton.icon(onPressed: _busy ? null : () => _edit(), icon: const Icon(Icons.add), label: const Text('Create offer'))),
      if (review) const Text('Human moderation queue. Check all content before approving; publication never happens automatically.'),
      if (offers.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(review ? 'No offers awaiting review.' : 'No saved offers yet.')),
      ...offers.map((offer) => _card(offer, owned: !review, review: review)),
    ]);
  });
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Local offers')), body:
    !_sameAccount ? Center(child: Text(_changed ? 'Your account changed. Reopen offers.' : 'Sign in to view offers.')) : Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('My offers'), selected: _tab == 0, onSelected: (_) => setState(() => _tab = 0)),
        ChoiceChip(label: const Text('Browse'), selected: _tab == 1, onSelected: (_) { setState(() => _tab = 1); if (!_browseLoaded) unawaited(_browse(refresh: true)); }),
        if (_admin) ChoiceChip(label: const Text('Review'), selected: _tab == 2, onSelected: (_) => setState(() => _tab = 2)),
      ])),
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: _tab == 0 ? _stream(_owned) : _tab == 2 ? _stream(_queue, review: true) : RefreshIndicator(onRefresh: () => _browse(refresh: true), child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        const Text('Reviewed, current local offers. Private contact details and exact meetup locations stay in your conversation.'),
        if (_browseLoading) const LinearProgressIndicator(),
        if (_browseError != null) ...[Text(_browseError!), TextButton(onPressed: () => _browse(refresh: true), child: const Text('Retry'))],
        if (_browseLoaded && !_browseLoading && _public.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No offers are visible on this page.')),
        ..._public.map((offer) => _card(offer)),
        if (_cursor != null) OutlinedButton(onPressed: _browseLoading ? null : () => _browse(), child: const Text('Load more')),
      ]))),
    ]));
  @override void dispose() { unawaited(_account?.cancel()); super.dispose(); }
}

class _OfferReviewDialog extends StatefulWidget {
  const _OfferReviewDialog({required this.decision, required this.repository, required this.uid});
  final String decision;
  final BusinessOffersRepository repository;
  final String uid;
  @override State<_OfferReviewDialog> createState() => _OfferReviewDialogState();
}
class _OfferReviewDialogState extends State<_OfferReviewDialog> {
  final _note = TextEditingController();
  bool _invalid = false;
  bool _changed = false;
  StreamSubscription<String?>? _account;
  @override void initState() { super.initState(); _account = widget.repository.watchUid().listen((uid) {
    if (!mounted || uid == widget.uid) return; _note.clear(); setState(() => _changed = true);
  }); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(widget.decision == 'approve' ? 'Approve publication?' : 'Request changes'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_changed ? 'Your account changed. Close this review.' : 'Review the full offer for safety, accuracy and fair terms. Reject contact details, exact addresses, sensitive information and prohibited goods or services. Automated checks do not replace this review.'),
      if (!_changed) TextField(controller: _note, maxLength: 800, maxLines: 3, decoration: InputDecoration(labelText: widget.decision == 'reject' ? 'Reason (at least 5 characters)' : 'Optional review note', errorText: _invalid ? 'Enter at least 5 characters.' : null)),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _changed ? null : () {
      if (widget.decision == 'reject' && _note.text.trim().length < 5) { setState(() => _invalid = true); return; }
      Navigator.pop(context, _note.text.trim());
    }, child: Text(widget.decision == 'approve' ? 'Approve' : 'Send reason'))]);
  @override void dispose() { unawaited(_account?.cancel()); _note.dispose(); super.dispose(); }
}

class _BusinessOfferEditor extends StatefulWidget {
  const _BusinessOfferEditor({required this.repository, required this.uid, this.offer});
  final BusinessOffersRepository repository;
  final String uid;
  final BusinessOffer? offer;
  @override State<_BusinessOfferEditor> createState() => _BusinessOfferEditorState();
}
class _BusinessOfferEditorState extends State<_BusinessOfferEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(), _description = TextEditingController(), _terms = TextEditingController(), _area = TextEditingController(), _discount = TextEditingController();
  late final String _id;
  late DateTime _expiry;
  String _visibility = 'public';
  String? _fingerprint, _requestId, _error;
  bool _busy = false, _changed = false;
  StreamSubscription<String?>? _account;
  @override void initState() {
    super.initState(); final offer = widget.offer; _id = offer?.id ?? widget.repository.newId();
    _title.text = offer?.title ?? ''; _description.text = offer?.description ?? ''; _terms.text = offer?.terms ?? '';
    _area.text = offer?.locationLabel ?? ''; _discount.text = offer?.discountPercent?.toString() ?? '';
    _expiry = offer != null && !offer.expired ? offer.expiresAt : DateTime.now().add(const Duration(days: 7));
    _visibility = offer?.visibility ?? 'public';
    _account = widget.repository.watchUid().listen((uid) { if (!mounted || uid == widget.uid) return;
      _title.clear(); _description.clear(); _terms.clear(); _area.clear(); _discount.clear(); setState(() => _changed = true); });
    if (offer == null) unawaited(_defaults());
  }
  Future<void> _defaults() async {
    try { final details = await widget.repository.defaults(widget.uid);
      if (!mounted || _changed || widget.repository.currentUid != widget.uid) return;
      // Only bounded, owner-editable broad text is suggested; the owner reviews it before submitting.
      if (_area.text.isEmpty && details.serviceAreaText.length <= 100) _area.text = details.serviceAreaText;
      if (_terms.text.isEmpty && details.meetupTerms.length <= 800) _terms.text = details.meetupTerms;
    } catch (_) { /* Optional private defaults never block offer creation. */ }
  }
  Future<void> _save(bool submit) async {
    if (_busy || _changed || widget.repository.currentUid != widget.uid || !_form.currentState!.validate()) return;
    final draft = BusinessOfferDraft(title: _title.text, description: _description.text, terms: _terms.text, locationLabel: _area.text,
      discountPercent: _discount.text.trim().isEmpty ? null : int.tryParse(_discount.text.trim()), visibility: _visibility, expiresAt: _expiry);
    final fingerprint = '${draft.toMap()}:$submit';
    if (_fingerprint != fingerprint) { _fingerprint = fingerprint; _requestId = widget.repository.newId(); }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.repository.save(widget.uid, offerId: _id, requestId: _requestId!, revision: widget.offer?.revision ?? 0, draft: draft, submit: submit);
      if (!mounted || _changed || widget.repository.currentUid != widget.uid) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(submit ? 'Submitted for human review. Publication follows approval.' : 'Private draft saved.')));
      Navigator.pop(context);
    } catch (error) { if (mounted && !_changed) setState(() => _error = _offerError(error)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Widget _field(TextEditingController controller, String label, int max, {int min = 0, int lines = 1}) => TextFormField(controller: controller,
    enabled: !_busy, maxLength: max, maxLines: lines, decoration: InputDecoration(labelText: label), validator: (value) => (value?.trim().length ?? 0) < min ? 'Enter at least $min characters.' : null);
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.offer == null ? 'Create offer' : 'Edit offer')),
    body: _changed ? const Center(child: Text('Your account changed. Reopen offers.')) : Form(key: _form, child: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Describe a clear service and honest terms. Use a broad city or region. Exclude phone numbers, links, exact addresses and sensitive information. Every publication requires human review.'),
      const SizedBox(height: 16), _field(_title, 'Title', 100, min: 3), _field(_description, 'Description', 2000, min: 10, lines: 4),
      _field(_terms, 'Terms (optional)', 800, lines: 3), _field(_area, 'Broad service area (optional)', 100),
      TextFormField(controller: _discount, enabled: !_busy, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Discount % (optional)'),
        validator: (value) { if (value == null || value.trim().isEmpty) return null; final amount = int.tryParse(value.trim()); return amount == null || amount < 0 || amount > 100 ? 'Enter a whole percent from 0 to 100.' : null; }),
      DropdownButtonFormField<String>(initialValue: _visibility, decoration: const InputDecoration(labelText: 'Visibility after approval'),
        items: const [DropdownMenuItem(value: 'public', child: Text('Public')), DropdownMenuItem(value: 'party', child: Text('Confirmed Party'))],
        onChanged: _busy ? null : (value) => setState(() => _visibility = value!)),
      ListTile(contentPadding: EdgeInsets.zero, title: const Text('Expiry (within 30 days)'), subtitle: Text(MaterialLocalizations.of(context).formatMediumDate(_expiry.toLocal())), trailing: const Icon(Icons.calendar_today), onTap: _busy ? null : () async {
        final now = DateTime.now(); final first = DateTime(now.year, now.month, now.day).add(const Duration(days: 1)); final last = first.add(const Duration(days: 28));
        final initial = _expiry.isBefore(first) ? first : _expiry.isAfter(last) ? last : _expiry;
        final date = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
        if (date != null && mounted) setState(() => _expiry = date);
      }),
      if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (_busy) const LinearProgressIndicator(),
      const SizedBox(height: 16), FilledButton(onPressed: _busy ? null : () => _save(true), child: const Text('Submit for human review')),
      OutlinedButton(onPressed: _busy ? null : () => _save(false), child: const Text('Save private draft')),
    ])));
  @override void dispose() { unawaited(_account?.cancel()); for (final controller in [_title, _description, _terms, _area, _discount]) { controller.dispose(); } super.dispose(); }
}
