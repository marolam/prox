/// Business Mode Models
///
/// Defines data structures for business mode, avatar auto-responder, and store items.

// ============================================================================
// BUSINESS SUBSCRIPTION MODELS
// ============================================================================

/// Business subscription tier - Single tier at $50/month (50 points)
enum BusinessSubscriptionTier {
  business;

  String get displayName => 'Business';
  double get monthlyPrice => 50.0; // $50/month = 50 points
  String get description =>
      'Full business mode access with auto-responder, priority matching, and more';

  double get monthlyPriceUsd {
    return switch (this) {
      BusinessSubscriptionTier.business => 50.0,
    };
  }

  /// Points equivalent for payment (assuming 1 point = $0.01)
  int get pointsEquivalent {
    return (monthlyPriceUsd * 100).toInt();
  }
}

/// Business profile information
class BusinessProfile {
  final String uid;
  final String businessName;
  final String? businessDescription;
  final String? businessCategory; // e.g., "consulting", "real estate", etc.
  final String? businessWebsite;
  final String? businessPhone;
  final List<String> avatarIds; // Associated avatars for this business
  final DateTime createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> metadata; // Custom fields

  BusinessProfile({
    required this.uid,
    required this.businessName,
    this.businessDescription,
    this.businessCategory,
    this.businessWebsite,
    this.businessPhone,
    this.avatarIds = const [],
    required this.createdAt,
    this.updatedAt,
    this.metadata = const {},
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      uid: json['uid'] as String,
      businessName: json['businessName'] as String,
      businessDescription: json['businessDescription'] as String?,
      businessCategory: json['businessCategory'] as String?,
      businessWebsite: json['businessWebsite'] as String?,
      businessPhone: json['businessPhone'] as String?,
      avatarIds: List<String>.from(json['avatarIds'] as List? ?? []),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'businessName': businessName,
      'businessDescription': businessDescription,
      'businessCategory': businessCategory,
      'businessWebsite': businessWebsite,
      'businessPhone': businessPhone,
      'avatarIds': avatarIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  BusinessProfile copyWith({
    String? businessName,
    String? businessDescription,
    String? businessCategory,
    String? businessWebsite,
    String? businessPhone,
    List<String>? avatarIds,
    DateTime? updatedAt,
    Map<String, dynamic>? metadata,
  }) {
    return BusinessProfile(
      uid: uid,
      businessName: businessName ?? this.businessName,
      businessDescription: businessDescription ?? this.businessDescription,
      businessCategory: businessCategory ?? this.businessCategory,
      businessWebsite: businessWebsite ?? this.businessWebsite,
      businessPhone: businessPhone ?? this.businessPhone,
      avatarIds: avatarIds ?? this.avatarIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      metadata: metadata ?? this.metadata,
    );
  }
}

/// Business subscription record
class BusinessSubscription {
  final String uid;
  final BusinessSubscriptionTier tier;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? renewalDate; // Next renewal
  final bool active;
  final String? paymentMethodId; // ID of stored payment method
  final bool autoRenew;
  final DateTime createdAt;
  final DateTime? cancelledAt;

  BusinessSubscription({
    required this.uid,
    required this.tier,
    required this.startDate,
    this.endDate,
    this.renewalDate,
    this.active = true,
    this.paymentMethodId,
    this.autoRenew = true,
    required this.createdAt,
    this.cancelledAt,
  });

  factory BusinessSubscription.fromJson(Map<String, dynamic> json) {
    return BusinessSubscription(
      uid: json['uid'] as String,
      tier: BusinessSubscriptionTier.values.byName(json['tier'] as String),
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'] as String)
          : null,
      renewalDate: json['renewalDate'] != null
          ? DateTime.parse(json['renewalDate'] as String)
          : null,
      active: json['active'] as bool? ?? true,
      paymentMethodId: json['paymentMethodId'] as String?,
      autoRenew: json['autoRenew'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      cancelledAt: json['cancelledAt'] != null
          ? DateTime.parse(json['cancelledAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'tier': tier.name,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'renewalDate': renewalDate?.toIso8601String(),
      'active': active,
      'paymentMethodId': paymentMethodId,
      'autoRenew': autoRenew,
      'createdAt': createdAt.toIso8601String(),
      'cancelledAt': cancelledAt?.toIso8601String(),
    };
  }

  bool get isExpired {
    if (endDate == null) return false;
    return DateTime.now().isAfter(endDate!);
  }

  int get daysUntilRenewal {
    if (renewalDate == null) return 0;
    return renewalDate!.difference(DateTime.now()).inDays;
  }

  BusinessSubscription copyWith({
    String? uid,
    BusinessSubscriptionTier? tier,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? renewalDate,
    bool? active,
    String? paymentMethodId,
    bool? autoRenew,
    DateTime? createdAt,
    DateTime? cancelledAt,
  }) {
    return BusinessSubscription(
      uid: uid ?? this.uid,
      tier: tier ?? this.tier,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      renewalDate: renewalDate ?? this.renewalDate,
      active: active ?? this.active,
      paymentMethodId: paymentMethodId ?? this.paymentMethodId,
      autoRenew: autoRenew ?? this.autoRenew,
      createdAt: createdAt ?? this.createdAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
    );
  }
}

// ============================================================================
// AUTO-RESPONDER AVATAR SYSTEM
// ============================================================================

/// Business mode auto-responder avatar
/// Simple placeholder that responds to incoming messages and can set away status
class BusinessAvatar {
  final String uid;
  final bool enabled; // Whether auto-responder is active
  final String autoResponseMessage; // Message sent to incoming chats
  final String? awayMessage; // Optional away message
  final bool isAvailable; // Whether business owner is available
  final DateTime? lastUpdated;
  final Map<String, dynamic> metadata;

  BusinessAvatar({
    required this.uid,
    this.enabled = true,
    this.autoResponseMessage = 'Thanks for reaching out! I\'ll get back to you soon.',
    this.awayMessage,
    this.isAvailable = true,
    this.lastUpdated,
    this.metadata = const {},
  });

  factory BusinessAvatar.fromJson(Map<String, dynamic> json) {
    return BusinessAvatar(
      uid: json['uid'] as String,
      enabled: json['enabled'] as bool? ?? true,
      autoResponseMessage: json['autoResponseMessage'] as String? ??
          'Thanks for reaching out! I\'ll get back to you soon.',
      awayMessage: json['awayMessage'] as String?,
      isAvailable: json['isAvailable'] as bool? ?? true,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'enabled': enabled,
      'autoResponseMessage': autoResponseMessage,
      'awayMessage': awayMessage,
      'isAvailable': isAvailable,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'metadata': metadata,
    };
  }

  BusinessAvatar copyWith({
    bool? enabled,
    String? autoResponseMessage,
    String? awayMessage,
    bool? isAvailable,
    DateTime? lastUpdated,
    Map<String, dynamic>? metadata,
  }) {
    return BusinessAvatar(
      uid: uid,
      enabled: enabled ?? this.enabled,
      autoResponseMessage:
          autoResponseMessage ?? this.autoResponseMessage,
      awayMessage: awayMessage ?? this.awayMessage,
      isAvailable: isAvailable ?? this.isAvailable,
      lastUpdated: lastUpdated ?? DateTime.now(),
      metadata: metadata ?? this.metadata,
    );
  }
}

// ============================================================================
// STORE MODELS
// ============================================================================

/// Store item category
enum StoreItemCategory {
  avatar,      // Avatar customization
  accessory,   // Accessories
  cosmetic,    // Personal: fonts, themes, profile customization
  feature,     // Business: priority matching, super messages, giveaway boxes
  boost;       // Boosts & upgrades

  String get displayName {
    return switch (this) {
      StoreItemCategory.avatar => 'Avatars',
      StoreItemCategory.accessory => 'Accessories',
      StoreItemCategory.cosmetic => 'Cosmetics',
      StoreItemCategory.feature => 'Features',
      StoreItemCategory.boost => 'Boosts',
    };
  }
}

/// Store item tier (affects pricing and rarity)
enum StoreItemTier {
  common,   // 50-200 points
  rare,     // 200-500 points
  epic,     // 500+ points
  legendary; // 1000+ points

  String get displayName {
    return switch (this) {
      StoreItemTier.common => 'Common',
      StoreItemTier.rare => 'Rare',
      StoreItemTier.epic => 'Epic',
      StoreItemTier.legendary => 'Legendary',
    };
  }

  int get minPoints {
    return switch (this) {
      StoreItemTier.common => 50,
      StoreItemTier.rare => 200,
      StoreItemTier.epic => 500,
      StoreItemTier.legendary => 1000,
    };
  }
}

/// Item available in the Prox Store
class StoreItem {
  final String id;
  final String name;
  final String description;
  final StoreItemCategory category;
  final StoreItemTier tier;
  final int costPoints;
  final double? costUsd; // For items also available for purchase with card
  final String? iconUrl;
  final String? previewUrl;
  final bool isLimited; // Limited time or quantity
  final int? maxQuantity;
  final int? currentQuantityRemaining;
  final bool requiresBusinessMode; // Only for business mode users
  final bool isPermanent; // Permanent purchase vs temporary
  final int? durationDays; // If temporary, how long it lasts
  final DateTime createdAt;
  final DateTime? expiresAt; // When this item is no longer available
  final Map<String, dynamic> metadata;

  StoreItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.tier,
    required this.costPoints,
    this.costUsd,
    this.iconUrl,
    this.previewUrl,
    this.isLimited = false,
    this.maxQuantity,
    this.currentQuantityRemaining,
    this.requiresBusinessMode = false,
    this.isPermanent = true,
    this.durationDays,
    required this.createdAt,
    this.expiresAt,
    this.metadata = const {},
  });

  factory StoreItem.fromJson(Map<String, dynamic> json) {
    return StoreItem(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      category: StoreItemCategory.values.byName(json['category'] as String),
      tier: StoreItemTier.values.byName(json['tier'] as String),
      costPoints: json['costPoints'] as int,
      costUsd: json['costUsd'] as double?,
      iconUrl: json['iconUrl'] as String?,
      previewUrl: json['previewUrl'] as String?,
      isLimited: json['isLimited'] as bool? ?? false,
      maxQuantity: json['maxQuantity'] as int?,
      currentQuantityRemaining: json['currentQuantityRemaining'] as int?,
      requiresBusinessMode: json['requiresBusinessMode'] as bool? ?? false,
      isPermanent: json['isPermanent'] as bool? ?? true,
      durationDays: json['durationDays'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category.name,
      'tier': tier.name,
      'costPoints': costPoints,
      'costUsd': costUsd,
      'iconUrl': iconUrl,
      'previewUrl': previewUrl,
      'isLimited': isLimited,
      'maxQuantity': maxQuantity,
      'currentQuantityRemaining': currentQuantityRemaining,
      'requiresBusinessMode': requiresBusinessMode,
      'isPermanent': isPermanent,
      'durationDays': durationDays,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  bool get isAvailable {
    // Check if expired
    if (expiresAt != null && DateTime.now().isAfter(expiresAt!)) {
      return false;
    }
    // Check if sold out
    if (isLimited && currentQuantityRemaining != null) {
      return currentQuantityRemaining! > 0;
    }
    return true;
  }
}

/// User's purchase of a store item
class StorePurchase {
  final String id;
  final String uid;
  final String itemId;
  final DateTime purchaseDate;
  final int pointsCost;
  final double? usdCost;
  final String paymentMethod; // 'points' or 'card'
  final DateTime? expiresAt; // If temporary item
  final bool active;

  StorePurchase({
    required this.id,
    required this.uid,
    required this.itemId,
    required this.purchaseDate,
    required this.pointsCost,
    this.usdCost,
    required this.paymentMethod,
    this.expiresAt,
    this.active = true,
  });

  factory StorePurchase.fromJson(Map<String, dynamic> json) {
    return StorePurchase(
      id: json['id'] as String,
      uid: json['uid'] as String,
      itemId: json['itemId'] as String,
      purchaseDate: DateTime.parse(json['purchaseDate'] as String),
      pointsCost: json['pointsCost'] as int,
      usdCost: json['usdCost'] as double?,
      paymentMethod: json['paymentMethod'] as String,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uid': uid,
      'itemId': itemId,
      'purchaseDate': purchaseDate.toIso8601String(),
      'pointsCost': pointsCost,
      'usdCost': usdCost,
      'paymentMethod': paymentMethod,
      'expiresAt': expiresAt?.toIso8601String(),
      'active': active,
    };
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }
}
