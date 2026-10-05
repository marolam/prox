import "package:flutter/material.dart";
import 'package:firebase_auth/firebase_auth.dart';
import "package:prox/screens/support/support_compose_screen.dart";
import 'package:prox/services/support_service.dart';
import 'package:prox/screens/support/support_ticket_screen.dart';

class UserSupportScreen extends StatefulWidget {
  const UserSupportScreen({super.key, this.tickets});
  final Stream<List<TrackedSupportTicket>>? tickets;

  @override
  State<UserSupportScreen> createState() => _UserSupportScreenState();
}

class _UserSupportScreenState extends State<UserSupportScreen> {
  Stream<User?>? _auth;
  String? _uid;
  Stream<List<TrackedSupportTicket>>? _tickets;
  @override
  void initState() {
    super.initState();
    if (widget.tickets != null) {
      _tickets = widget.tickets;
      return;
    }
    _auth = FirebaseAuth.instance.authStateChanges();
    _bind(FirebaseAuth.instance.currentUser?.uid);
  }

  void _bind(String? uid) {
    _uid = uid;
    _tickets = uid == null ? null : SupportService.instance.watchTickets(uid);
  }

  Widget _records() {
    if (widget.tickets == null && _uid == null) {
      return const Center(child: Text('Sign in to view your support tickets.'));
    }
    return StreamBuilder<List<TrackedSupportTicket>>(
      key: ValueKey(_uid),
      stream: _tickets,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Your tickets could not be loaded. Check your connection and retry.',
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      if (widget.tickets != null)
                        _tickets = widget.tickets;
                      else
                        _bind(_uid);
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final tickets = snapshot.data!;
        if (tickets.isEmpty)
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No support tickets yet. Submit a message to get help and follow its status here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: tickets.length + 1,
          itemBuilder: (context, index) {
            if (index == tickets.length)
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Showing up to 100 tickets. Replies and status update automatically.',
                ),
              );
            final ticket = tickets[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.confirmation_number_outlined),
                title: Text(ticket.subject),
                subtitle: Text(
                  '${ticket.statusLabel} · ${ticket.category}'
                  '${ticket.fixedLabel.isEmpty ? '' : '\n${ticket.fixedLabel}'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SupportTicketScreen(ticket: ticket),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My support tickets')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('New support ticket'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SupportComposeScreen(),
              ),
            ),
          ),
        ),
        Expanded(
          child: _auth == null
              ? _records()
              : StreamBuilder<User?>(
                  stream: _auth,
                  initialData: FirebaseAuth.instance.currentUser,
                  builder: (context, snapshot) {
                    final uid = snapshot.data?.uid;
                    if (uid != _uid) _bind(uid);
                    return _records();
                  },
                ),
        ),
      ],
    ),
  );
}
