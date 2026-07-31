import "package:flutter/material.dart";

class CostHudService {
  CostHudService._();

  static final CostHudService instance = CostHudService._();

  final RouteObserver<PageRoute<dynamic>> routeObserver = RouteObserver<PageRoute<dynamic>>();
  bool get isEnabledForThisBuild => false;

  void ensureReady() {}
}