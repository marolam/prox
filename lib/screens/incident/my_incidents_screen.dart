import "package:flutter/material.dart";
import "package:prox/widgets/account_records_screen.dart";
import "package:prox/screens/support/report_compose_screen.dart";

class MyIncidentsScreen extends StatelessWidget {
  const MyIncidentsScreen({super.key});

  @override
  Widget build(BuildContext context) => const AccountRecordsScreen(
    title: "My reports & appeals",
    collection: "incidents",
    ownerField: "reporterUid",
    titleField: "reason",
    detailField: "detail",
    emptyMessage:
        "You have no submitted incident reports or appeals. Use New report to describe an incident or reference a decision you wish to appeal.",
    compose: ReportComposeScreen(incident: true),
  );
}
