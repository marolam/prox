import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:prox/services/points_service.dart";
import "package:prox/utils/auth_bound_stream.dart";

abstract class TrustBarSource {
  String? get currentUid;
  Stream<String?> watchUid();
  Stream<PointsMeta> watchMeta(String uid);
}

class _FirebaseTrustBarSource implements TrustBarSource {
  const _FirebaseTrustBarSource();

  @override
  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Stream<String?> watchUid() =>
      FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);

  @override
  Stream<PointsMeta> watchMeta(String uid) =>
      PointsService.instance.watchMeta(uid);
}

/// The signed-in account's canonical trust score, without a cached placeholder.
class CurrentUserTrustBar extends StatefulWidget {
  const CurrentUserTrustBar({super.key, this.source});

  final TrustBarSource? source;

  @override
  State<CurrentUserTrustBar> createState() => _CurrentUserTrustBarState();
}

class _CurrentUserTrustBarState extends State<CurrentUserTrustBar> {
  late TrustBarSource _source;
  late Stream<_AccountTrust?> _trust;
  int _binding = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(CurrentUserTrustBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _bind();
  }

  void _bind() {
    final source = widget.source ?? const _FirebaseTrustBarSource();
    _source = source;
    _binding++;
    // Each State/retry gets a fresh SDK auth stream. A previously cancelled SDK
    // broadcast wrapper must not be retained across widget removal/reopening.
    _trust = authBoundStream<_AccountTrust?>(
      accountChanges: source.watchUid(),
      currentUid: () => source.currentUid,
      watch: (uid) =>
          source.watchMeta(uid).map((meta) => _AccountTrust(uid, meta)),
      empty: null,
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<_AccountTrust?>(
    key: ValueKey(_binding),
    stream: _trust,
    builder: (context, snapshot) {
      final uid = _source.currentUid;
      if (uid == null || uid.isEmpty) {
        return const _TrustStatus(message: "Sign in to view trust.");
      }
      if (snapshot.hasError) {
        return _TrustStatus(
          message: "Trust unavailable",
          onRetry: () => setState(_bind),
        );
      }
      final value = snapshot.data;
      // Guard a parent rebuild before the queued account-reset event arrives.
      if (value == null || value.uid != uid) {
        return const _TrustStatus(message: "Loading trust…", loading: true);
      }
      final percent = value.meta.trustPercent;
      if (!percent.isFinite) {
        return _TrustStatus(
          message: "Trust unavailable",
          onRetry: () => setState(_bind),
        );
      }
      return ProxTrustBar(value: percent / 100);
    },
  );
}

class _AccountTrust {
  const _AccountTrust(this.uid, this.meta);

  final String uid;
  final PointsMeta meta;
}

class _TrustStatus extends StatelessWidget {
  const _TrustStatus({
    required this.message,
    this.loading = false,
    this.onRetry,
  });

  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading) ...[
          const LinearProgressIndicator(minHeight: 10),
          const SizedBox(height: 6),
        ],
        Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text("Retry")),
      ],
    );
  }
}

class ProxTrustBar extends StatelessWidget {
  const ProxTrustBar({super.key, required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = value.clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 10,
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Trust ${(v * 100).round()}%",
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
