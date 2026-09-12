import "package:flutter/material.dart";

import "package:prox/screens/services/party_profile_service.dart";
import "package:prox/screens/services/party_service.dart";
import "package:prox/screens/services/user_profile_service.dart";

class PartyMemberProfileScreen extends StatelessWidget {
  final String memberUid;

  const PartyMemberProfileScreen({
    super.key,
    required this.memberUid,
  });

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _chips(Iterable<String> values) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: values.map((value) => Chip(label: Text(value))).toList(),
    );
  }

  Widget _profileBody(
    BuildContext context,
    UserProfile? profile,
    PartyProfileSharing sharing,
  ) {
    final name = profile?.displayName?.trim();
    final photo = profile?.photoUrl?.trim() ?? "";
    final sections = <Widget>[];

    if (sharing.shareHeadline &&
        (profile?.headline?.trim().isNotEmpty ?? false)) {
      sections.add(_section(
        context,
        icon: Icons.short_text,
        title: "Headline",
        child: Text(profile!.headline!.trim()),
      ));
    }
    if (sharing.shareAbout && sharing.about.isNotEmpty) {
      sections.add(_section(context,
          icon: Icons.person_outline,
          title: "About",
          child: Text(sharing.about)));
    }
    if (sharing.shareGeneralArea && sharing.generalArea.isNotEmpty) {
      sections.add(_section(context,
          icon: Icons.location_city_outlined,
          title: "General area",
          child: Text(sharing.generalArea)));
    }
    if (sharing.shareKeywords &&
        ((profile?.searchingFor.isNotEmpty ?? false) ||
            (profile?.canProvide.isNotEmpty ?? false))) {
      if (profile!.searchingFor.isNotEmpty) {
        sections.add(_section(context,
            icon: Icons.search,
            title: "Wants",
            child: _chips(profile.searchingFor)));
      }
      if (profile.canProvide.isNotEmpty) {
        sections.add(_section(context,
            icon: Icons.handshake_outlined,
            title: "Has",
            child: _chips(profile.canProvide)));
      }
    }
    if (sharing.shareContactEmail && sharing.contactEmail.isNotEmpty) {
      sections.add(_section(context,
          icon: Icons.email_outlined,
          title: "Contact email",
          child: SelectableText(sharing.contactEmail)));
    }
    if (sharing.sharePhone && sharing.phone.isNotEmpty) {
      sections.add(_section(context,
          icon: Icons.phone_outlined,
          title: "Phone",
          child: SelectableText(sharing.phone)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Center(
          child: CircleAvatar(
            radius: 48,
            backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
            child: photo.isEmpty ? const Icon(Icons.person, size: 48) : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name?.isNotEmpty == true ? name! : "Party member",
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 28),
        if (sections.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "This member has not shared additional Party information.",
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...sections,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = memberUid.trim();
    return Scaffold(
      appBar: AppBar(title: const Text("Party profile")),
      body: StreamBuilder<bool>(
        stream: PartyService.instance.watchIsInMyParty(uid),
        builder: (context, membershipSnap) {
          if (membershipSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (membershipSnap.data != true) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Party profile access is available only to Party members.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return StreamBuilder<UserProfile?>(
            stream: UserProfileService.instance.watchProfile(uid),
            builder: (context, profileSnap) {
              return StreamBuilder<PartyProfileSharing>(
                stream: PartyProfileService.instance.watchMember(uid),
                builder: (context, sharingSnap) {
                  if (!sharingSnap.hasData &&
                      sharingSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (sharingSnap.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          "This profile is private or Party membership is not mutual yet.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return _profileBody(
                    context,
                    profileSnap.data,
                    sharingSnap.data ?? const PartyProfileSharing(),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
