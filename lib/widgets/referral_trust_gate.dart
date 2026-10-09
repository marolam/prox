import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ReferralTrustGate extends StatelessWidget {
  const ReferralTrustGate({
    super.key,
    required this.uid,
    required this.child,
    this.accountStream,
  });
  final String uid;
  final Widget child;
  final Stream<Map<String, dynamic>?>? accountStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream:
          accountStream ??
          FirebaseFirestore.instance
              .doc('users/$uid')
              .snapshots()
              .map((doc) => doc.data()),
      builder: (context, snapshot) {
        final restricted =
            snapshot.data?['disabled'] == true ||
            snapshot.data?['banned'] == true;
        if (!snapshot.hasError &&
            !restricted &&
            snapshot.hasData &&
            (snapshot.data!['referralTrustRequired'] != true ||
                snapshot.data!['referralInPersonVerified'] == true)) {
          return child;
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              restricted ? 'Account restricted' : 'Join Prox face to face',
            ),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.qr_code_scanner, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    snapshot.hasError
                        ? 'Could not verify account access. Check your connection or contact support if your account is restricted.'
                        : restricted
                        ? 'This account is restricted. Contact support to appeal or ask for help.'
                        : 'Meet your referrer in person and open their fresh QR link while you are together. '
                              'Both locations must verify proximity before matching, chats and recruiting unlock. '
                              'A forwarded link or ordinary invite code is not enough.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/referrals'),
                    child: const Text('My referral / mentor'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/support'),
                    child: const Text('Contact support'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
