enum ProCircleStatus {
  off,
  active,
}

enum ProEntityStatus {
  draft,
  gated,
  active,
  paused,
}

class ProEntity {
  const ProEntity({
    required this.id,
    required this.custodianUid,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.offerKeywords = const <String>[],
    this.audienceKeywords = const <String>[],
    this.locationLabel,
    this.latitude,
    this.longitude,
    this.serviceRadiusMiles = 5,
    this.priorityNotifyOptIn = false,
    this.freeTrialEligible = true,
    this.qualifiedLeadCount = 0,
  });

  final String id;
  final String custodianUid;
  final String displayName;
  final ProEntityStatus status;
  final List<String> offerKeywords;
  final List<String> audienceKeywords;
  final String? locationLabel;
  final double? latitude;
  final double? longitude;
  final double serviceRadiusMiles;
  final bool priorityNotifyOptIn;
  final bool freeTrialEligible;
  final int qualifiedLeadCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isVisiblePreview => status != ProEntityStatus.paused;

  factory ProEntity.fromJson(String id, Map<String, dynamic> json) {
    return ProEntity(
      id: id,
      custodianUid: _readString(json, "custodianUid"),
      displayName: _readString(json, "displayName", fallback: "Pro profile"),
      status: _readStatus(json["status"]),
      offerKeywords: _readKeywords(json["offerKeywords"]),
      audienceKeywords: _readKeywords(json["audienceKeywords"]),
      locationLabel: _readOptionalString(json, "locationLabel"),
      latitude: _readDouble(json["latitude"]),
      longitude: _readDouble(json["longitude"]),
      serviceRadiusMiles: _readDouble(json["serviceRadiusMiles"]) ?? 5,
      priorityNotifyOptIn: json["priorityNotifyOptIn"] == true,
      freeTrialEligible: json["freeTrialEligible"] != false,
      qualifiedLeadCount: (json["qualifiedLeadCount"] as num?)?.toInt() ?? 0,
      createdAt: _readDateTime(json["createdAt"]) ?? DateTime.now(),
      updatedAt: _readDateTime(json["updatedAt"]) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "custodianUid": custodianUid,
      "createdBy": custodianUid,
      "displayName": displayName,
      "status": status.name,
      "offerKeywords": _cleanKeywords(offerKeywords),
      "audienceKeywords": _cleanKeywords(audienceKeywords),
      "locationLabel": locationLabel,
      "latitude": latitude,
      "longitude": longitude,
      "serviceRadiusMiles": serviceRadiusMiles.clamp(1, 50).toDouble(),
      "priorityNotifyOptIn": priorityNotifyOptIn,
      "freeTrialEligible": freeTrialEligible,
      "qualifiedLeadCount": qualifiedLeadCount < 0 ? 0 : qualifiedLeadCount,
      "createdAt": createdAt.toIso8601String(),
      "updatedAt": updatedAt.toIso8601String(),
      "schemaVersion": 1,
    };
  }

  ProEntity copyWith({
    String? displayName,
    ProEntityStatus? status,
    List<String>? offerKeywords,
    List<String>? audienceKeywords,
    String? locationLabel,
    double? latitude,
    double? longitude,
    double? serviceRadiusMiles,
    bool? priorityNotifyOptIn,
    bool? freeTrialEligible,
    int? qualifiedLeadCount,
    DateTime? updatedAt,
  }) {
    return ProEntity(
      id: id,
      custodianUid: custodianUid,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      offerKeywords: offerKeywords ?? this.offerKeywords,
      audienceKeywords: audienceKeywords ?? this.audienceKeywords,
      locationLabel: locationLabel ?? this.locationLabel,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      serviceRadiusMiles: serviceRadiusMiles ?? this.serviceRadiusMiles,
      priorityNotifyOptIn: priorityNotifyOptIn ?? this.priorityNotifyOptIn,
      freeTrialEligible: freeTrialEligible ?? this.freeTrialEligible,
      qualifiedLeadCount: qualifiedLeadCount ?? this.qualifiedLeadCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

class ProKeywordSimulationInput {
  const ProKeywordSimulationInput({
    required this.offerKeywords,
    required this.audienceKeywords,
    required this.locationLabel,
    required this.radiusMiles,
  });

  final List<String> offerKeywords;
  final List<String> audienceKeywords;
  final String locationLabel;
  final double radiusMiles;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "offerKeywords": _cleanKeywords(offerKeywords),
      "audienceKeywords": _cleanKeywords(audienceKeywords),
      "locationLabel": locationLabel.trim(),
      "radiusMiles": radiusMiles.clamp(1, 50).toDouble(),
    };
  }
}

class ProKeywordSimulationResult {
  const ProKeywordSimulationResult({
    required this.demandScore,
    this.keywordSuggestions = const <String>[],
    this.potentialMatchCategories = const <String>[],
    this.setupChecklist = const <String>[],
  });

  final int demandScore;
  final List<String> keywordSuggestions;
  final List<String> potentialMatchCategories;
  final List<String> setupChecklist;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "demandScore": demandScore.clamp(0, 100),
      "keywordSuggestions": _cleanKeywords(keywordSuggestions),
      "potentialMatchCategories": _cleanKeywords(potentialMatchCategories),
      "setupChecklist": setupChecklist
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(12)
          .toList(growable: false),
    };
  }
}

String _readString(
  Map<String, dynamic> json,
  String key, {
  String fallback = "",
}) {
  final value = json[key];
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _readOptionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

ProEntityStatus _readStatus(Object? value) {
  final text = value?.toString().trim();
  return ProEntityStatus.values.firstWhere(
    (status) => status.name == text,
    orElse: () => ProEntityStatus.draft,
  );
}

List<String> _readKeywords(Object? value) {
  if (value is! List) return const <String>[];
  return _cleanKeywords(value.map((item) => item.toString()));
}

List<String> _cleanKeywords(Iterable<String> keywords) {
  return keywords
      .map((keyword) => keyword.trim().toLowerCase())
      .where((keyword) => keyword.isNotEmpty)
      .toSet()
      .take(12)
      .toList(growable: false);
}

class ProCircleConfig {
  const ProCircleConfig({
    required this.id,
    required this.label,
    required this.matchType,
    required this.keywords,
    this.status = ProCircleStatus.off,
  });

  final String id;
  final String label;
  final String matchType;
  final List<String> keywords;
  final ProCircleStatus status;

  bool get isActive => status == ProCircleStatus.active;

  ProCircleConfig copyWith({
    String? label,
    String? matchType,
    List<String>? keywords,
    ProCircleStatus? status,
  }) {
    return ProCircleConfig(
      id: id,
      label: label ?? this.label,
      matchType: matchType ?? this.matchType,
      keywords: keywords ?? this.keywords,
      status: status ?? this.status,
    );
  }
}

class ProApexPolicy {
  ProApexPolicy._();

  static List<ProCircleConfig> toggleCircle({
    required List<ProCircleConfig> circles,
    required String circleId,
    bool hasActiveLead = false,
  }) {
    if (hasActiveLead) {
      return circles
          .map((circle) => circle.copyWith(status: ProCircleStatus.off))
          .toList(growable: false);
    }

    return circles.map((circle) {
      if (circle.id != circleId) return circle;
      final nextStatus =
          circle.isActive ? ProCircleStatus.off : ProCircleStatus.active;
      return circle.copyWith(status: nextStatus);
    }).toList(growable: false);
  }

  static List<ProCircleConfig> setKeywords({
    required List<ProCircleConfig> circles,
    required String circleId,
    required List<String> keywords,
  }) {
    final cleanKeywords = keywords
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toSet()
        .take(8)
        .toList(growable: false);

    return circles.map((circle) {
      if (circle.id != circleId) return circle;
      return circle.copyWith(keywords: cleanKeywords);
    }).toList(growable: false);
  }

  static bool canReceiveMatches({
    required List<ProCircleConfig> circles,
    bool hasActiveLead = false,
    DateTime? pausedUntil,
    DateTime? now,
  }) {
    if (hasActiveLead) return false;
    final clock = now ?? DateTime.now();
    if (pausedUntil != null && pausedUntil.isAfter(clock)) return false;
    return circles
        .any((circle) => circle.isActive && circle.keywords.isNotEmpty);
  }
}
