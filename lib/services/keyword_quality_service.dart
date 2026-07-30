class KeywordValidationResult {
  const KeywordValidationResult({
    required this.normalized,
    required this.isValid,
  });

  final String normalized;
  final bool isValid;
}

class KeywordQualityService {
  static final RegExp _allowed = RegExp(r"^[a-z0-9][a-z0-9 '\-]{0,48}$");

  static KeywordValidationResult validate(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(RegExp(r"\s+"), " ");
    return KeywordValidationResult(
      normalized: normalized,
      isValid: normalized.isNotEmpty && _allowed.hasMatch(normalized),
    );
  }

  static List<String> sanitizeList(List<String> input) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in input) {
      final v = raw.trim().toLowerCase();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }
    return out;
  }
}

extension KeywordQualityListX on List<String> {
  List<String> get cleaned => KeywordQualityService.sanitizeList(this);
}
