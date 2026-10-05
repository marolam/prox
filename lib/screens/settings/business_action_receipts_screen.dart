import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prox/services/action_receipt_service.dart';

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
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const <ActionReceipt>[];
            final latest = rows.isEmpty ? null : rows.first;

            return ListView(
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
                else if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No action receipts saved yet. Confirmed business actions will be listed here.',
                    ),
                  )
                else
                  for (final receipt in rows)
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(
                          () => _receipts = ActionReceiptService.instance.watch(),
                        ),
                        icon: const Icon(Icons.refresh_outlined),
                        label: const Text('Refresh receipts'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: latest == null
                            ? null
                            : () async {
                                final summary =
                                    '${latest.kind}\n${latest.title}\n${latest.createdAt.toLocal()}\n\n${latest.detail}';
                                await Clipboard.setData(
                                  ClipboardData(text: summary),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Latest receipt copied.'),
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy latest'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ),
  );
}
