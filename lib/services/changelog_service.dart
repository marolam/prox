class ChangelogEntry {
  const ChangelogEntry({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;
}

class ChangelogService {
  ChangelogService._();

  static final ChangelogService instance = ChangelogService._();

  List<ChangelogEntry> entries() => const <ChangelogEntry>[
        ChangelogEntry(
          title: "Current tester build",
          bullets: <String>[
            "Release download links follow the latest shipped APK.",
            "Tester-facing settings and support surfaces are available.",
          ],
        ),
      ];
}