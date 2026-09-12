import "package:flutter/material.dart";
import "package:prox/services/geoquery_service.dart";

class LocationIssueBanner extends StatelessWidget {
  const LocationIssueBanner({super.key, this.message, this.hint, this.onRetry});

  final String? message;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text(message ?? hint ?? "Location is unavailable."),
      leading: const Icon(Icons.location_off_outlined),
      actions: [TextButton(onPressed: onRetry, child: const Text("Retry"))],
    );
  }
}

/// Shows results only after both location resolution and the query succeed.
/// Raw backend errors and account identifiers do not belong in this surface.
class NearbyResultsGate extends StatelessWidget {
  const NearbyResultsGate({
    super.key,
    required this.status,
    required this.locationEnabled,
    required this.matchingEnabled,
    required this.queryLoading,
    required this.queryFailed,
    required this.child,
    required this.onRetry,
    required this.onSettings,
    this.retrying = false,
  });
  final GeoQueryStatus status;
  final bool locationEnabled;
  final bool matchingEnabled;
  final bool queryLoading;
  final bool queryFailed;
  final bool retrying;
  final Widget child;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    String? title;
    String detail = '';
    var loading = false;
    var retry = false;
    var settings = false;
    if (!locationEnabled || status == GeoQueryStatus.locationOff) {
      title = 'Location is off';
      detail =
          'Nearby is paused while location sharing is off. You can change this in Settings.';
      settings = true;
    } else if (!matchingEnabled) {
      title = 'Matching is off';
      detail =
          'Turn matching on with the Prox Circle when you want to look nearby.';
    } else if (retrying) {
      title = 'Checking nearby again…';
      detail = 'Checking your location and connection.';
      loading = true;
    } else if (status == GeoQueryStatus.locationUnavailable) {
      title = "We couldn't get your location";
      detail = "Check your device's location settings, then try again.";
      retry = true;
      settings = true;
    } else if (queryFailed || status == GeoQueryStatus.queryError) {
      title = 'Nearby is unavailable';
      detail = 'Check your connection and try again.';
      retry = true;
    } else if (queryLoading ||
        status == GeoQueryStatus.idle ||
        status == GeoQueryStatus.loading) {
      title = 'Finding nearby matches…';
      detail = 'Checking your location and connection.';
      loading = true;
    }
    if (title == null) return child;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  settings
                      ? Icons.location_off_outlined
                      : Icons.explore_outlined,
                  size: 30,
                  color: Theme.of(context).colorScheme.primary,
                ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
              if (retry || settings) ...[
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (retry)
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    if (settings)
                      OutlinedButton(
                        onPressed: onSettings,
                        child: const Text('Location settings'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
