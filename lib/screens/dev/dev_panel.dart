import 'package:flutter/material.dart';
import 'package:prox/screens/dev/dev_tools_hub_screen.dart';

class DevPanel extends StatelessWidget {
  const DevPanel({super.key});
  @override
  Widget build(BuildContext context) =>
      const DevToolsHubScreen(title: 'Developer panel');
}
