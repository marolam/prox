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
  static final RegExp _repeatedCharacters = RegExp(r"(.)\1{4,}");
  static const Set<String> _fillerWords = <String>{
    "a",
    "an",
    "and",
    "her",
    "his",
    "its",
    "my",
    "our",
    "the",
    "their",
    "your",
  };

  static KeywordValidationResult validate(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll(RegExp(r"\s+"), " ");
    final words =
        normalized.split(" ").where((word) => word.isNotEmpty).toList();
    final fillerCount = words.where(_fillerWords.contains).length;
    return KeywordValidationResult(
      normalized: normalized,
      isValid: normalized.isNotEmpty &&
          _allowed.hasMatch(normalized) &&
          !_repeatedCharacters.hasMatch(normalized) &&
          !(words.length >= 4 && fillerCount >= 2),
    );
  }

  static List<String> sanitizeList(List<String> input) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in input) {
      final result = validate(raw);
      if (!result.isValid) continue;
      if (seen.add(result.normalized)) out.add(result.normalized);
    }
    return out;
  }
}

extension KeywordQualityListX on List<String> {
  List<String> get cleaned => KeywordQualityService.sanitizeList(this);
}
