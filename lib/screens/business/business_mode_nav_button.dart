import 'package:flutter/material.dart';
import '../../app_router.dart';

class BusinessModeNavButton extends StatelessWidget {
  const BusinessModeNavButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.business_center),
      tooltip: 'Business Mode',
      onPressed: () {
        Navigator.of(context).push(AppRouter.toBusinessMode());
      },
    );
  }
}
