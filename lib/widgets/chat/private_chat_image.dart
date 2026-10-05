import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:prox/services/chat_media_service.dart';

/// Storage paths are read with the current user's credentials, never a public URL.
class PrivateChatImage extends StatefulWidget {
  const PrivateChatImage({super.key, required this.path, required this.chatId});
  final String path;
  final String chatId;

  @override
  State<PrivateChatImage> createState() => _PrivateChatImageState();
}

class _PrivateChatImageState extends State<PrivateChatImage> {
  StreamSubscription<User?>? _account;
  Future<Uint8List?>? _image;
  String? _ownerUid;

  @override
  void initState() {
    super.initState();
    _bind(FirebaseAuth.instance.currentUser?.uid);
    _account = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted && user?.uid != _ownerUid) {
        setState(() => _bind(user?.uid));
      }
    });
  }

  void _bind(String? uid) {
    _ownerUid = uid;
    _image =
        uid != null &&
            ChatMediaService.isPrivateImagePath(widget.path, widget.chatId)
        ? ChatMediaService.instance.loadPrivateImage(widget.path, widget.chatId)
        : null;
  }

  @override
  void didUpdateWidget(covariant PrivateChatImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.chatId != widget.chatId) {
      _bind(FirebaseAuth.instance.currentUser?.uid);
    }
  }

  @override
  void dispose() {
    _account?.cancel();
    super.dispose();
  }

  Widget _unavailable() => const Padding(
    padding: EdgeInsets.all(16),
    child: Text('Photo unavailable'),
  );

  @override
  Widget build(BuildContext context) {
    if (_ownerUid == null) return _unavailable();
    if (_image == null) {
      // Preserve images already sent by older builds with HTTPS download URLs.
      final legacy = Uri.tryParse(widget.path);
      if (legacy?.scheme != 'https' ||
          legacy!.host.isEmpty ||
          legacy.userInfo.isNotEmpty) {
        return _unavailable();
      }
      return Image.network(
        widget.path,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _unavailable(),
      );
    }
    return FutureBuilder<Uint8List?>(
      key: ValueKey('$_ownerUid:${widget.path}'),
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _unavailable();
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null ||
            FirebaseAuth.instance.currentUser?.uid != _ownerUid) {
          return _unavailable();
        }
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: false,
          errorBuilder: (_, _, _) => _unavailable(),
        );
      },
    );
  }
}
