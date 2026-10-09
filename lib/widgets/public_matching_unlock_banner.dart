import 'package:flutter/material.dart';
import 'package:prox/services/matching_access_service.dart';

/// Remains visible until the server durably records this account's dismissal.
class PublicMatchingUnlockBanner extends StatefulWidget {
  const PublicMatchingUnlockBanner({super.key, this.service});
  final MatchingAccessService? service;

  @override
  State<PublicMatchingUnlockBanner> createState() =>
      _PublicMatchingUnlockBannerState();
}

class _PublicMatchingUnlockBannerState
    extends State<PublicMatchingUnlockBanner> {
  bool _acknowledging = false;

  @override
  Widget build(BuildContext context) {
    final service = widget.service ?? MatchingAccessService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!service.current.publicUnlockNotificationPending) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Public matching is now available',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'There are enough Prox users in your area to open '
                  'public matching. '
                  '${service.current.partyScope == 'public' ? 'Your Party + Tree search has automatically expanded to Public. ' : 'Public is now available alongside Party Only and Party + Tree. '}'
                  'You can still choose Party Only or Party + Tree '
                  'in Discovery settings whenever you prefer.',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _acknowledging
                        ? null
                        : () async {
                            setState(() => _acknowledging = true);
                            try {
                              await service.acknowledgePublicUnlock();
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not save this notice. Please try again.',
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted)
                                setState(() => _acknowledging = false);
                            }
                          },
                    child: Text(_acknowledging ? 'Saving…' : 'Got it'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
