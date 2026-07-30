import "package:prox/services/points_service.dart";

enum ProxFeatureUnlock {
  supportMode,
  supportTechnician,
  businessMode,
}

class ProgressionSnapshot {
  const ProgressionSnapshot({
    required this.level,
    required this.accountAgeDays,
    required this.unlocked,
  });

  final int level;
  final int accountAgeDays;
  final Set<ProxFeatureUnlock> unlocked;

  bool has(ProxFeatureUnlock feature) => unlocked.contains(feature);
}

class ProgressionService {
  ProgressionService._();
  static final ProgressionService instance = ProgressionService._();

  Future<ProgressionSnapshot?> loadForUser(String uid) async {
    final meta = await PointsService.instance.getMeta(uid);
    final level = levelFromTotalPoints(meta.totalPoints);
    final unlocked = <ProxFeatureUnlock>{};

    if (meta.totalPoints >= 25) unlocked.add(ProxFeatureUnlock.supportMode);
    if (meta.totalPoints >= 75) unlocked.add(ProxFeatureUnlock.supportTechnician);
    if (meta.completedMeetups >= 10 && meta.trustPercent >= 80) {
      unlocked.add(ProxFeatureUnlock.businessMode);
    }

    return ProgressionSnapshot(
      level: level,
      accountAgeDays: 0,
      unlocked: unlocked,
    );
  }

  int levelFromTotalPoints(int totalPoints) {
    if (totalPoints <= 0) return 1;
    return (totalPoints ~/ 100) + 1;
  }

  int pointsToNextLevel(int totalPoints) {
    final level = levelFromTotalPoints(totalPoints);
    final nextThreshold = level * 100;
    final needed = nextThreshold - totalPoints;
    return needed < 0 ? 0 : needed;
  }

  String requirementLabel(ProxFeatureUnlock? feature) {
    switch (feature) {
      case ProxFeatureUnlock.supportMode:
        return "Support Mode (25 points)";
      case ProxFeatureUnlock.supportTechnician:
        return "Support Technician (75 points)";
      case ProxFeatureUnlock.businessMode:
        return "Business Mode (10 meetups + 80% trust)";
      case null:
        return "All unlocked";
    }
  }

  String lockedReason({
    required ProxFeatureUnlock feature,
    required ProgressionSnapshot snapshot,
  }) {
    if (snapshot.has(feature)) return "Unlocked";
    return "Keep earning points and completing meetups to unlock this feature.";
  }
}
