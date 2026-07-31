import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../screens/auth/sign_in_screen.dart';

/// Shows SignInScreen if not authenticated; otherwise builds with non-null User.
class AuthGate extends StatelessWidget {
  final Widget Function(BuildContext context, User user) builder;
  const AuthGate({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const SignInScreen();
        return builder(context, user);
      },
    );
  }
}


