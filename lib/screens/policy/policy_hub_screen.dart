import "package:flutter/material.dart";
import "package:prox/screens/policy/business_rules_screen.dart";
import "package:prox/screens/policy/code_of_conduct_screen.dart";
import "package:prox/screens/policy/legal_agreement_screen.dart";

class PolicyHubScreen extends StatelessWidget {
  const PolicyHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rules & policy")),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text("Legal agreement & waiver"),
            subtitle: const Text(
                "Liability limits, prohibited use, enforcement, data sharing, and IP rules."),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const LegalAgreementScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text("Code of conduct"),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const CodeOfConductScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.business_center_outlined),
            title: const Text("Business rules"),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                  builder: (_) => const BusinessRulesScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
