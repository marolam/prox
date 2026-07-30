import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:prox/models/business_models.dart';

/// Business Mode Service
///
/// Manages:
/// - Business profile creation and management
/// - Subscription handling (free, pro, business tiers)
/// - Avatar management for business users
/// - Payment processing (points or card)
/// - Business mode access control

class BusinessModeService extends ChangeNotifier {
  static final BusinessModeService _instance = BusinessModeService._internal();
  static BusinessModeService get instance => _instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  factory BusinessModeService() {
    return _instance;
  }

  BusinessModeService._internal();

  // Current user's business data
  BusinessProfile? _profile;
  BusinessSubscription? _subscription;
  List<BusinessAvatar> _avatars = [];

  // Getters
  BusinessProfile? get profile => _profile;
  BusinessSubscription? get subscription => _subscription;
  List<BusinessAvatar> get avatars => _avatars;
  bool get isBusinessUser => _subscription != null && _subscription!.active;
  bool get isBusiness => subscription?.tier == BusinessSubscriptionTier.business;

  /// Load business data for current user
  Future<void> loadBusinessData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _profile = null;
      _subscription = null;
      _avatars = [];
      notifyListeners();
      return;
    }

    try {
      // Load profile
      final profileDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('business')
          .doc('profile')
          .get();

      if (profileDoc.exists) {
        _profile = BusinessProfile.fromJson(profileDoc.data()!);
      } else {
        _profile = null;
      }

      // Load subscription
      final subDoc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('business')
          .doc('subscription')
          .get();

      if (subDoc.exists) {
        _subscription = BusinessSubscription.fromJson(subDoc.data()!);
        // Check if subscription expired
        if (_subscription!.isExpired) {
          _subscription = null;
        }
      } else {
        _subscription = null;
      }

      // Load avatars
      final avatarDocs = await _firestore
          .collection('users')
          .doc(uid)
          .collection('business')
          .doc('avatars')
          .collection('items')
          .get();

      _avatars = avatarDocs.docs
          .map((doc) => BusinessAvatar.fromJson(doc.data()))
          .toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading business data: $e');
      rethrow;
    }
  }

  /// Create a new business profile
  Future<BusinessProfile> createBusinessProfile({
    required String businessName,
    String? businessDescription,
    String? businessCategory,
    String? businessWebsite,
    String? businessPhone,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final profile = BusinessProfile(
      uid: uid,
      businessName: businessName,
      businessDescription: businessDescription,
      businessCategory: businessCategory,
      businessWebsite: businessWebsite,
      businessPhone: businessPhone,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('business')
        .doc('profile')
        .set(profile.toJson());

    _profile = profile;
    notifyListeners();
    return profile;
  }

  /// Update business profile
  Future<BusinessProfile> updateBusinessProfile({
    String? businessName,
    String? businessDescription,
    String? businessCategory,
    String? businessWebsite,
    String? businessPhone,
  }) async {
    if (_profile == null) throw Exception('No business profile found');

    final updated = _profile!.copyWith(
      businessName: businessName,
      businessDescription: businessDescription,
      businessCategory: businessCategory,
      businessWebsite: businessWebsite,
      businessPhone: businessPhone,
      updatedAt: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(_profile!.uid)
        .collection('business')
        .doc('profile')
        .set(updated.toJson());

    _profile = updated;
    notifyListeners();
    return updated;
  }

  /// Subscribe to a business tier
  /// paymentMethod: 'points' or 'card'
  /// paymentMethodId: ID of card (if using card), or null if using points
  Future<BusinessSubscription> subscribe({
    required BusinessSubscriptionTier tier,
    required String paymentMethod,
    String? paymentMethodId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    final now = DateTime.now();
    final subscription = BusinessSubscription(
      uid: uid,
      tier: tier,
      startDate: now,
      renewalDate: now.add(Duration(days: 30)),
      paymentMethodId: paymentMethodId,
      autoRenew: true,
      createdAt: now,
    );

    // Save subscription
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('business')
        .doc('subscription')
        .set(subscription.toJson());

    // Log transaction
    await _logBusinessTransaction(
      uid: uid,
      type: 'subscription_purchase',
      amount: tier.pointsEquivalent,
      paymentMethod: paymentMethod,
      description: 'Subscribed to ${tier.displayName}',
    );

    _subscription = subscription;
    notifyListeners();
    return subscription;
  }

  /// Cancel business subscription
  Future<void> cancelSubscription() async {
    if (_subscription == null) return;

    final updated = _subscription!.copyWith(
      cancelledAt: DateTime.now(),
      autoRenew: false,
    );

    await _firestore
        .collection('users')
        .doc(_subscription!.uid)
        .collection('business')
        .doc('subscription')
        .set(updated.toJson());

    // Log transaction
    await _logBusinessTransaction(
      uid: _subscription!.uid,
      type: 'subscription_cancel',
      amount: 0,
      description: 'Cancelled ${_subscription!.tier.displayName} subscription',
    );

    _subscription = updated;
    notifyListeners();
  }

  /// Create a new avatar
  /// TODO: Implement with proper avatar model
  Future<BusinessAvatar> createAvatar({
    required String name,
    String? description,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');

    // Stub implementation - returns a basic auto-responder avatar
    final avatar = BusinessAvatar(
      uid: uid,
      enabled: true,
      autoResponseMessage: description ?? 'Thanks for reaching out!',
      isAvailable: true,
    );

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('business')
        .doc('avatars')
        .collection('items')
        .doc(_firestore.collection('dummy').doc().id)
        .set(avatar.toJson());

    _avatars.add(avatar);
    notifyListeners();
    return avatar;
  }

  /// Update avatar
  /// TODO: Implement with proper avatar model
  Future<BusinessAvatar> updateAvatar(
    String avatarId, {
    bool? enabled,
    String? autoResponseMessage,
    bool? isAvailable,
  }) async {
    final index = _avatars.indexWhere((a) => a.uid == avatarId);
    if (index == -1) throw Exception('Avatar not found');

    final updated = _avatars[index].copyWith(
      enabled: enabled,
      autoResponseMessage: autoResponseMessage,
      isAvailable: isAvailable,
      lastUpdated: DateTime.now(),
    );

    await _firestore
        .collection('users')
        .doc(_avatars[index].uid)
        .collection('business')
        .doc('avatars')
        .collection('items')
        .doc(_firestore.collection('dummy').doc().id)
        .set(updated.toJson());

    _avatars[index] = updated;
    notifyListeners();
    return updated;
  }

  /// Delete avatar
  /// TODO: Implement with proper avatar model
  Future<void> deleteAvatar(String avatarId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    // For now, just remove from list
    _avatars.removeWhere((a) => a.uid == avatarId);
    notifyListeners();
  }

  /// Set active avatar
  /// TODO: Implement with proper avatar model
  Future<void> setActiveAvatar(String avatarId) async {
    // Stub - avatars don't have active/inactive state in current BusinessAvatar model
  }

  /// Get active avatar
  BusinessAvatar? getActiveAvatar() {
    return _avatars.isNotEmpty ? _avatars.first : null;
  }

  /// Watch subscription status
  Stream<BusinessSubscription?> watchSubscription() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('business')
        .doc('subscription')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final sub = BusinessSubscription.fromJson(doc.data()!);
      // Filter out expired subscriptions
      return !sub.isExpired ? sub : null;
    });
  }

  /// Watch avatars
  Stream<List<BusinessAvatar>> watchAvatars() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('business')
        .doc('avatars')
        .collection('items')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => BusinessAvatar.fromJson(doc.data()))
          .toList();
    });
  }

  /// Check if user can unlock business mode
  /// Returns (canUnlock, reason)
  (bool, String) canUnlockBusinessMode(int currentLevel, int currentPoints) {
    // Define requirements
    const requiredLevel = 5;
    const requiredPoints = 200;

    if (currentLevel < requiredLevel) {
      return (false, 'Requires Level $requiredLevel');
    }

    if (currentPoints < requiredPoints) {
      return (false, 'Requires $requiredPoints points');
    }

    return (true, 'Ready to unlock');
  }

  /// Private helper: Log business transactions
  Future<void> _logBusinessTransaction({
    required String uid,
    required String type,
    required int amount,
    String? paymentMethod,
    String? description,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('business')
          .doc('transactions')
          .collection('history')
          .add({
        'type': type,
        'amount': amount,
        'paymentMethod': paymentMethod,
        'description': description,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error logging business transaction: $e');
    }
  }
}
