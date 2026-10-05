String formatDashboardMetricsUpdatedLabel({
  required DateTime updatedAt,
  DateTime? now,
}) {
  final localUpdated = updatedAt.toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();

  var diff = localNow.difference(localUpdated);
  if (diff.isNegative) diff = Duration.zero;

  if (diff < const Duration(minutes: 1)) {
    return 'Updated just now';
  }

  if (diff < const Duration(hours: 1)) {
    return 'Updated ${diff.inMinutes}m ago';
  }

  if (diff < const Duration(days: 1)) {
    return 'Updated ${diff.inHours}h ago';
  }

  if (diff < const Duration(days: 7)) {
    return 'Updated ${diff.inDays}d ago';
  }

  final year = localUpdated.year.toString().padLeft(4, '0');
  final month = localUpdated.month.toString().padLeft(2, '0');
  final day = localUpdated.day.toString().padLeft(2, '0');
  final hour = localUpdated.hour.toString().padLeft(2, '0');
  final minute = localUpdated.minute.toString().padLeft(2, '0');

  return 'Updated $year-$month-$day $hour:$minute';
}