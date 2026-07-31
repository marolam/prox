import "package:flutter/material.dart";

class BugReportService {
  BugReportService._();

  static final BugReportService instance = BugReportService._();

  final RouteObserver<PageRoute<dynamic>> routeObserver = RouteObserver<PageRoute<dynamic>>();
  bool get isEnabledForThisBuild => false;

  void ensureReady() {}
}