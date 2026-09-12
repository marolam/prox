import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/services/action_receipt_service.dart';
import 'package:prox/screens/store/feature_example_screen.dart';

class BusinessActionReceiptsScreen extends StatefulWidget {
  const BusinessActionReceiptsScreen({super.key});
  @override
  State<BusinessActionReceiptsScreen> createState() =>
      _BusinessActionReceiptsScreenState();
}

class _BusinessActionReceiptsScreenState
    extends State<BusinessActionReceiptsScreen> {
  late Stream<List<ActionReceipt>> _receipts = ActionReceiptService.instance
      .watch();
  late final Stream<User?> _auth = FirebaseAuth.instance.authStateChanges();
  String? _uid = FirebaseAuth.instance.currentUser?.uid;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business receipts')),
    body: StreamBuilder<User?>(
      stream: _auth,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, user) {
        if (user.data?.uid != _uid) {
          _uid = user.data?.uid;
          _receipts = ActionReceiptService.instance.watch();
        }
        if (user.data == null)
          return const Center(child: Text('Sign in to view your receipts.'));
        return StreamBuilder<List<ActionReceipt>>(
          key: ValueKey(_uid),
          stream: _receipts,
          builder: (context, snapshot) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'The latest 100 action confirmations saved on this device for your account. These are activity records; consult your payment provider for financial receipts.',
              ),
              const SizedBox(height: 16),
              if (snapshot.hasError)
                ListTile(
                  title: const Text('Could not load saved receipts.'),
                  trailing: TextButton(
                    onPressed: () => setState(
                      () => _receipts = ActionReceiptService.instance.watch(),
                    ),
                    child: const Text('Retry'),
                  ),
                )
              else if (!snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else if (snapshot.data!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No action receipts saved yet. Confirmed business actions will be listed here.',
                  ),
                )
              else
                for (final receipt in snapshot.data!)
                  Card(
                    child: ExpansionTile(
                      title: Text(receipt.title),
                      subtitle: Text(
                        '${receipt.kind} · ${receipt.createdAt.toLocal()}',
                      ),
                      childrenPadding: const EdgeInsets.all(16),
                      children: [SelectableText(receipt.detail)],
                    ),
                  ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FeatureExampleScreen(
                      title: 'Business receipt example',
                    ),
                  ),
                ),
                child: const Text('Explore an example receipt'),
              ),
            ],
          ),
        );
      },
    ),
  );
}
