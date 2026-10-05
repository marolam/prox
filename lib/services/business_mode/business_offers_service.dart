import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/models/business_offer.dart';
import 'package:prox/services/auth/authenticated_callable.dart';
import 'package:prox/services/business_mode/business_entitlement_guard.dart';
import 'package:prox/services/business_mode/business_storefront_service.dart';
import 'package:prox/utils/auth_bound_stream.dart';

abstract class BusinessOffersRepository {
  String? get currentUid;
  Stream<String?> watchUid();
  String newId();
  Future<bool> canCreate(String uid);
  Future<bool> isAdmin(String uid);
  Future<BusinessStorefrontDetails> defaults(String uid);
  Stream<List<BusinessOffer>> watchOwned(String uid);
  Stream<List<BusinessOffer>> watchReviewQueue(String uid);
  Future<void> save(String uid, {required String offerId, required String requestId, required int revision,
    required BusinessOfferDraft draft, required bool submit});
  Future<void> change(String uid, BusinessOffer offer, String action, String requestId);
  Future<void> review(String uid, BusinessOffer offer, String decision, String reason, String requestId);
  Future<BusinessOfferPage> browse(String uid, {String? cursor});
}

class BusinessOffersService implements BusinessOffersRepository {
  BusinessOffersService._();
  static final instance = BusinessOffersService._();
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  @override String? get currentUid => FirebaseAuth.instance.currentUser?.uid;
  @override Stream<String?> watchUid() => FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
  void _check(String uid) { if (currentUid != uid || uid.isEmpty) throw StateError('Your account changed. Reopen offers.'); }
  @override String newId() => _db.collection('businessOffers').doc().id;
  @override Future<bool> canCreate(String uid) async {
    _check(uid);
    try { await BusinessEntitlementGuard.instance.ensureCanOperateBusiness(uid: uid); _check(uid); return true; }
    on StateError { _check(uid); return false; }
  }
  @override Future<bool> isAdmin(String uid) async {
    _check(uid); final token = await FirebaseAuth.instance.currentUser!.getIdTokenResult(true); _check(uid);
    return token.claims?['admin'] == true;
  }
  @override Future<BusinessStorefrontDetails> defaults(String uid) => BusinessStorefrontService.instance.load(uid);
  Stream<List<BusinessOffer>> _watch(String uid, Query<Map<String, dynamic>> query) {
    _check(uid);
    return authBoundStream<List<BusinessOffer>>(accountChanges: watchUid(), currentUid: () => currentUid,
      watch: (boundUid) => boundUid != uid ? Stream.value(const <BusinessOffer>[]) : query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => BusinessOffer.fromMap(doc.id, doc.data())).toList()), empty: const <BusinessOffer>[]);
  }
  @override Stream<List<BusinessOffer>> watchOwned(String uid) => _watch(uid, _db.collection('businessOffers').where('uid', isEqualTo: uid).limit(20));
  @override Stream<List<BusinessOffer>> watchReviewQueue(String uid) => _watch(uid, _db.collection('businessOffers').where('status', isEqualTo: 'pending_review').limit(50));
  Future<void> _call(String uid, String name, Map<String, dynamic> data) async {
    _check(uid); await callAuthenticatedFunction<dynamic>(name, {...data, 'expectedUid': uid}); _check(uid);
  }
  @override Future<void> save(String uid, {required String offerId, required String requestId, required int revision,
    required BusinessOfferDraft draft, required bool submit}) => _call(uid, 'upsertBusinessOffer',
      {'offerId': offerId, 'requestId': requestId, 'expectedRevision': revision, 'draft': draft.toMap(), 'submitForReview': submit});
  @override Future<void> change(String uid, BusinessOffer offer, String action, String requestId) =>
    _call(uid, 'changeBusinessOfferState', {'offerId': offer.id, 'requestId': requestId, 'expectedRevision': offer.revision, 'action': action});
  @override Future<void> review(String uid, BusinessOffer offer, String decision, String reason, String requestId) =>
    _call(uid, 'reviewBusinessOffer', {'offerId': offer.id, 'requestId': requestId, 'expectedRevision': offer.revision, 'decision': decision, 'reason': reason});
  @override Future<BusinessOfferPage> browse(String uid, {String? cursor}) async {
    _check(uid);
    final result = await callAuthenticatedFunction<dynamic>('listPublicBusinessOffers', {'expectedUid': uid, 'limit': 20, if (cursor != null) 'cursor': cursor});
    _check(uid); final data = Map<String, dynamic>.from(result.data as Map);
    final rows = (data['offers'] as List).map((row) { final value = Map<String, dynamic>.from(row as Map); return BusinessOffer.fromMap(value['offerId'] as String, value); }).toList();
    return BusinessOfferPage(rows, data['nextCursor'] as String?);
  }
}
