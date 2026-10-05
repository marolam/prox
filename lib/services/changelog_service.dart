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
      title: "0.20.0 — Founding testers and fast support",
      bullets: <String>[
        "Admin-approved tester missions with verified 48-hour progress.",
        "Referral links, welcome rewards, activation rewards, and review safeguards.",
        "Categorized feedback with private screenshots and device/build details.",
        "Tracked support replies and notices showing the version and build that fixed a report.",
        "Administrator rollout controls, support triage, and daily activation/retention metrics.",
      ],
    ),
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
