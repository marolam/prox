import "package:flutter/material.dart";
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BugReportService {
  BugReportService._();

  static final BugReportService instance = BugReportService._();

  final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();
  Future<String> submit({
    required String title,
    required String description,
    String route = 'manual_report',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to submit a report.');
    if (title.trim().isEmpty || description.trim().isEmpty) {
      throw ArgumentError('A title and description are required.');
    }
    final report = await FirebaseFirestore.instance
        .collection('bugReports')
        .add({
          'ownerUid': uid,
          'actor': uid,
          'title': title.trim(),
          'description': description.trim(),
          'route': route,
          'status': 'open',
          'createdAt': FieldValue.serverTimestamp(),
        });
    return report.id;
  }
}
