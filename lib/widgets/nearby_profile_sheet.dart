import 'package:flutter/material.dart';

/// Uses the sanitized Nearby profile; viewing it neither opens nor renews chat.
class NearbyProfileSheet extends StatelessWidget {
  const NearbyProfileSheet({
    super.key,
    required this.profile,
    required this.displayName,
    this.photoUrl = '',
  });
  final Map<String, dynamic> profile;
  final String displayName;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final groups = profile['keywords'] is Map
        ? profile['keywords'] as Map
        : const {};
    final bio = profile['bio'] is String
        ? (profile['bio'] as String).trim()
        : '';
    List<String> words(String group, String fallback) {
      final values = groups[group] ?? profile[fallback];
      return values is List ? values.whereType<String>().take(10).toList() : [];
    }

    final wants = words('Searching For', 'SearchingFor');
    final offers = words('Can Provide', 'CanProvide');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: photoUrl.isEmpty
                      ? null
                      : NetworkImage(photoUrl),
                  child: photoUrl.isEmpty ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (bio.isNotEmpty) Text(bio),
            if (wants.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Searching for',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(wants.join(', ')),
            ],
            if (offers.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Can provide',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(offers.join(', ')),
            ],
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close profile'),
            ),
          ],
        ),
      ),
    );
  }
}
