import "package:flutter/material.dart";

class ProCalendarScreen extends StatelessWidget {
  const ProCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final plannedDays = <int>{14, 17, 22};

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pro Calendar"),
        actions: [
          Badge.count(
            count: 3,
            child: IconButton(
              tooltip: "Meetup inbox",
              onPressed: () {},
              icon: const Icon(Icons.mark_email_unread_outlined),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            "Scheduled meetups",
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 30,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final day = index + 1;
              final planned = plannedDays.contains(day);
              return Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: planned
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: planned
                      ? [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  "$day",
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: planned ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _MeetupCard(
            title: "Today, 4:30 PM",
            customer: "Customer contact ready after agreement",
            terms:
                "Terms, price, prep, address, reminders, messages, and navigation live here.",
          ),
          const SizedBox(height: 10),
          _MeetupCard(
            title: "June 17, 10:00 AM",
            customer: "Awaiting final terms",
            terms:
                "The requesting user can message the Pro, but this calendar remains Pro-only.",
          ),
        ],
      ),
    );
  }
}

class _MeetupCard extends StatelessWidget {
  const _MeetupCard(
      {required this.title, required this.customer, required this.terms});

  final String title;
  final String customer;
  final String terms;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(customer),
          const SizedBox(height: 6),
          Text(terms,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: const [
              ActionChip(
                  label: Text("Message"),
                  avatar: Icon(Icons.chat_outlined, size: 18)),
              ActionChip(
                  label: Text("Reminder"),
                  avatar: Icon(Icons.notifications_outlined, size: 18)),
              ActionChip(
                  label: Text("Navigate"),
                  avatar: Icon(Icons.navigation_outlined, size: 18)),
            ],
          ),
        ],
      ),
    );
  }
}
