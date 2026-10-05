import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessOffer {
  const BusinessOffer({required this.id, required this.ownerUid, required this.title,
    required this.description, required this.expiresAt, required this.revision,
    this.ownerName = '', this.terms = '', this.locationLabel = '', this.discountPercent,
    this.visibility = 'public', this.status = 'draft', this.moderationReason = ''});
  final String id, ownerUid, ownerName, title, description, terms, locationLabel,
      visibility, status, moderationReason;
  final int revision;
  final int? discountPercent;
  final DateTime expiresAt;
  bool get expired => !expiresAt.isAfter(DateTime.now());
  String get statusLabel => expired && status == 'active' ? 'Expired' : switch (status) {
    'pending_review' => 'Awaiting human review', 'active' => 'Published',
    'rejected' => 'Needs changes', 'paused' => 'Paused', _ => 'Private draft',
  };
  factory BusinessOffer.fromMap(String id, Map<String, dynamic> data) {
    String text(String field, [String fallback = '']) => data[field] is String ? data[field] as String : fallback;
    final expiry = data['expiresAt'];
    final millis = data['expiresAtMs'];
    return BusinessOffer(id: id, ownerUid: text('ownerUid', text('uid')), ownerName: text('ownerName'),
      title: text('title'), description: text('description'), terms: text('terms'), locationLabel: text('locationLabel'),
      revision: data['revision'] is num ? (data['revision'] as num).toInt() : 0,
      expiresAt: expiry is Timestamp ? expiry.toDate() : DateTime.fromMillisecondsSinceEpoch(millis is num ? millis.toInt() : 0),
      discountPercent: data['discountPercent'] is num ? (data['discountPercent'] as num).toInt() : null,
      visibility: text('visibility', 'public'), status: text('status', 'active'), moderationReason: text('moderationReason'));
  }
}

class BusinessOfferDraft {
  const BusinessOfferDraft({required this.title, required this.description, required this.expiresAt,
    this.terms = '', this.locationLabel = '', this.discountPercent, this.visibility = 'public'});
  final String title, description, terms, locationLabel, visibility;
  final int? discountPercent;
  final DateTime expiresAt;
  Map<String, dynamic> toMap() => {'title': title.trim(), 'description': description.trim(), 'terms': terms.trim(),
    'locationLabel': locationLabel.trim(), 'discountPercent': discountPercent,
    'visibility': visibility, 'expiresAtMs': expiresAt.millisecondsSinceEpoch};
}

class BusinessOfferPage {
  const BusinessOfferPage(this.offers, this.nextCursor);
  final List<BusinessOffer> offers;
  final String? nextCursor;
}
