import 'package:flutter/material.dart';

Future<bool?> showPartyReferralConsent(
  BuildContext context,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog(
    title: const Text('Join your inviter’s Party?'),
    content: const Text(
      'Party is for people you have met in person. '
      'Accept only if you are together with the person who showed you this QR code. '
      'Prox will check your locations and add you to each other’s Party. '
      'Their Party connections can become your Tree matches through that mutual person.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Continue without joining'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('We’ve met — join Party'),
      ),
    ],
  ),
);
