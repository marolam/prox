import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Shows only the signed-in user's records. Queries match ownership rules.
class AccountRecordsScreen extends StatefulWidget {
  const AccountRecordsScreen({
    super.key,
    required this.title,
    required this.collection,
    required this.ownerField,
    required this.emptyMessage,
    this.titleField = 'subject',
    this.detailField = 'message',
    this.compose,
    this.composeLabel = 'New report',
  });
  final String title;
  final String collection;
  final String ownerField;
  final String emptyMessage;
  final String titleField;
  final String detailField;
  final Widget? compose;
  final String composeLabel;

  @override
  State<AccountRecordsScreen> createState() => _AccountRecordsScreenState();
}

class _AccountRecordsScreenState extends State<AccountRecordsScreen> {
  late final Stream<User?> _auth = FirebaseAuth.instance.authStateChanges();
  String? _uid;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _records;

  void _subscribe(String? uid) {
    _uid = uid;
    _records = uid == null
        ? null
        : FirebaseFirestore.instance
              .collection(widget.collection)
              .where(widget.ownerField, isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .limit(100)
              .snapshots();
  }

  static String _date(Object? raw) {
    final date = raw is Timestamp ? raw.toDate().toLocal() : null;
    return date == null
        ? 'Sending date pending'
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: StreamBuilder<User?>(
      stream: _auth,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, auth) {
        final uid = auth.data?.uid;
        if (_uid != uid || (uid != null && _records == null)) _subscribe(uid);
        if (uid == null)
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Sign in to view your records.'),
            ),
          );
        return Column(
          children: [
            if (widget.compose != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(widget.composeLabel),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => widget.compose!),
                  ),
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey(uid),
                stream: _records,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Your records could not be loaded. Check your connection and try again.',
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => setState(() => _subscribe(uid)),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs.toList()
                    ..sort((a, b) {
                      final ad = a.data()['createdAt'];
                      final bd = b.data()['createdAt'];
                      return (bd is Timestamp ? bd.millisecondsSinceEpoch : 0)
                          .compareTo(
                            ad is Timestamp ? ad.millisecondsSinceEpoch : 0,
                          );
                    });
                  if (docs.isEmpty)
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.emptyMessage,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: docs.length + 1,
                    itemBuilder: (context, index) {
                      if (index == docs.length)
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            snapshot.data!.metadata.isFromCache
                                ? 'Showing saved records. Reconnect to receive updates.'
                                : 'Showing up to 100 records. Status updates appear automatically.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      final doc = docs[index];
                      final data = doc.data();
                      final status = '${data['status'] ?? 'submitted'}'
                          .replaceAll('_', ' ');
                      return Card(
                        child: ExpansionTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text('${data[widget.titleField] ?? 'Report'}'),
                          subtitle: Text(
                            '$status · ${_date(data['createdAt'])}',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16,
                          ),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              '${data[widget.detailField] ?? 'No additional details.'}',
                            ),
                            if (data['decision'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text('Decision: ${data['decision']}'),
                              ),
                            const SizedBox(height: 12),
                            SelectableText(
                              'Reference: ${doc.id}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    ),
  );
}
