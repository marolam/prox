import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/services/business_mode/business_entitlement_guard.dart';

class BusinessStorefrontDetails {
  const BusinessStorefrontDetails({
    this.hoursText = '',
    this.serviceAreaText = '',
    this.meetupTerms = '',
  });

  final String hoursText;
  final String serviceAreaText;
  final String meetupTerms;

  factory BusinessStorefrontDetails.fromMap(Map<String, dynamic> data) =>
      BusinessStorefrontDetails(
        hoursText: data['hoursText'] is String
            ? data['hoursText'] as String
            : '',
        serviceAreaText: data['serviceAreaText'] is String
            ? data['serviceAreaText'] as String
            : '',
        meetupTerms: data['meetupTerms'] is String
            ? data['meetupTerms'] as String
            : '',
      );

  Map<String, String> validatedFields() {
    final fields = <String, String>{
      'hoursText': hoursText.trim(),
      'serviceAreaText': serviceAreaText.trim(),
      'meetupTerms': meetupTerms.trim(),
    };
    if (fields['hoursText']!.length > 1000 ||
        fields['serviceAreaText']!.length > 500 ||
        fields['meetupTerms']!.length > 1000) {
      throw ArgumentError('Service details exceed their allowed length.');
    }
    return fields;
  }
}

abstract class BusinessStorefrontRepository {
  String? get currentUid;
  Stream<String?> watchUid();
  Future<BusinessStorefrontDetails> load(String uid);
  Future<void> save(String uid, BusinessStorefrontDetails details);
}

class BusinessStorefrontService implements BusinessStorefrontRepository {
  BusinessStorefrontService._();
  static final instance = BusinessStorefrontService._();

  @override
  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Stream<String?> watchUid() =>
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);

  void _checkUid(String uid) {
    if (uid.isEmpty || currentUid != uid) {
      throw StateError('Your account changed. Reopen Storefront to continue.');
    }
  }

  DocumentReference<Map<String, dynamic>> _document(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('business')
          .doc('settings')
          .collection('items')
          .doc('storefront');

  @override
  Future<BusinessStorefrontDetails> load(String uid) async {
    _checkUid(uid);
    await BusinessEntitlementGuard.instance.ensureCanOperateBusiness(uid: uid);
    _checkUid(uid);
    final snapshot = await _document(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    _checkUid(uid);
    return BusinessStorefrontDetails.fromMap(snapshot.data() ?? const {});
  }

  @override
  Future<void> save(String uid, BusinessStorefrontDetails details) async {
    final fields = details.validatedFields();
    _checkUid(uid);
    await BusinessEntitlementGuard.instance.ensureCanOperateBusiness(uid: uid);
    _checkUid(uid);
    await _document(uid)
        .set({
          ...fields,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 10));
    _checkUid(uid);
  }
}
