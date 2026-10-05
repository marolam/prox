import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:prox/services/support_service.dart';

/// Loads a private Storage object through the signed-in SDK, with no public URL.
class SupportAttachmentPreview extends StatefulWidget {
  const SupportAttachmentPreview({
    super.key,
    required this.path,
    this.loadAttachment,
  });
  final String path;
  final Future<Uint8List?> Function(String path)? loadAttachment;

  @override
  State<SupportAttachmentPreview> createState() =>
      _SupportAttachmentPreviewState();
}

class _SupportAttachmentPreviewState extends State<SupportAttachmentPreview> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final bytes =
          await (widget.loadAttachment ??
              SupportService.instance.loadAttachment)(widget.path);
      if (!mounted) return;
      if (bytes == null) throw StateError('Screenshot unavailable');
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  child: Image.memory(
                    bytes,
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('This image cannot be displayed.'),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Screenshot could not be loaded. Check your connection and try again.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _loading ? null : _open,
    icon: const Icon(Icons.image_outlined),
    label: Text(_loading ? 'Loading screenshot...' : 'View private screenshot'),
  );
}
