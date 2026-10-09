import 'package:flutter/material.dart';
import 'package:prox/models/matching_access.dart';
import 'package:prox/models/user_settings.dart';
import 'package:prox/widgets/match_filter_chip.dart';

class MatchingScopePicker extends StatelessWidget {
  const MatchingScopePicker({
    super.key,
    required this.scope,
    required this.publicUnlocked,
    required this.onChanged,
  });
  final MatchPartyScope scope;
  final bool publicUnlocked;
  final ValueChanged<MatchPartyScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final effective = MatchingAccessSnapshot(
      publicUnlocked: publicUnlocked,
    ).effectiveScope(scope);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Who you match with',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            MatchFilterChip(
              label: 'Party Only',
              selected: effective == MatchPartyScope.partyOnly,
              onTap: () => onChanged(MatchPartyScope.partyOnly),
            ),
            MatchFilterChip(
              label: 'Party + Tree',
              selected: effective == MatchPartyScope.tree,
              onTap: () => onChanged(MatchPartyScope.tree),
            ),
            MatchFilterChip(
              label: publicUnlocked ? 'Public' : 'Public · Locked',
              selected: effective == MatchPartyScope.public,
              onTap: publicUnlocked
                  ? () => onChanged(MatchPartyScope.public)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Party Only includes people you have met in person and connected '
          'with. Party + Tree also includes a friend of a friend, one level '
          'beyond your Party, and shows who you both know. '
          '${publicUnlocked ? 'Public is available; Party and Tree remain your choice.' : 'Public opens when enough users are in your area.'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
