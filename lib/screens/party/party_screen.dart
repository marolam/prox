import "package:flutter/material.dart";

import "package:prox/screens/party/party_list_screen.dart";

class PartyScreen extends StatelessWidget {
  const PartyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Party")),
      body: const SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: PartyListScreen(),
        ),
      ),
    );
  }
}
