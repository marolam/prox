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
          title: "0.19.0 — Reliability and account controls",
          bullets: <String>[
            "Persistent location controls and more reliable nearby discovery.",
            "Secure saved login, account-summary export, and account deletion.",
            "Saved support drafts, reports, an expanded guide, and interactive Pro examples.",
            "Verified purchases and clearer prepaid access information.",
            "Improved update prompts, text sizing, and Android/iOS release consistency.",
          ],
        ),
      ];
}
