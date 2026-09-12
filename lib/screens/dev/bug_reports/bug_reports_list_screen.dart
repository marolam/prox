import "package:flutter/material.dart";
import "package:prox/widgets/account_records_screen.dart";
import "package:prox/screens/support/report_compose_screen.dart";

class BugReportsListScreen extends StatelessWidget {
  const BugReportsListScreen({super.key});

  @override
  Widget build(BuildContext context) => const AccountRecordsScreen(
    title: "My bug reports",
    collection: "bugReports",
    ownerField: "ownerUid",
    titleField: "title",
    detailField: "description",
    emptyMessage:
        "No bug reports yet. Found a problem? Include the steps to reproduce it and track the report here.",
    compose: ReportComposeScreen(incident: false),
  );
}
