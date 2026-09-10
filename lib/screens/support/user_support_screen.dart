import "package:flutter/material.dart";
import "package:prox/widgets/account_records_screen.dart";
import "package:prox/screens/support/support_compose_screen.dart";

class UserSupportScreen extends StatelessWidget {
  const UserSupportScreen({super.key});

  @override
  Widget build(BuildContext context) => const AccountRecordsScreen(
    title: "My support tickets",
    collection: "supportTickets",
    ownerField: "uid",
    emptyMessage:
        "No support tickets yet. Submit a message to get help and follow its status here.",
    compose: SupportComposeScreen(),
    composeLabel: "New support ticket",
  );
}
