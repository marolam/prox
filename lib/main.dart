import "package:flutter/material.dart";

import "app.dart";
import "services/startup_watchdog.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Keeps "stuck on splash" bugs visible in logs if first frame never lands.
  StartupWatchdog.instance.arm();

  // Run immediately; ProxApp now owns Firebase init gating.
  runApp(const ProxApp());
}
