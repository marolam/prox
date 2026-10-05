import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:prox/services/image_picker_guard.dart';

class ChatMediaService {
  ChatMediaService._();
  static final ChatMediaService instance = ChatMediaService._();

  final ImagePicker _picker = ImagePicker();

  Future<XFile?> takePhoto() {
    return _pick(ImageSource.camera);
  }

  Future<XFile?> pickFromGallery() {
    return _pick(ImageSource.gallery);
  }

  Future<XFile?> _pick(ImageSource source) async {
    if (!ImagePickerGuard.tryAcquire()) return null;
    try {
      return await _picker.pickImage(source: source, imageQuality: 85);
    } finally {
      ImagePickerGuard.release();
    }
  }

  static const maximumBytes = 10 * 1024 * 1024;

  /// Identify supported images by bytes, rather than trusting a file extension.
  static String contentTypeForBytes(List<int> bytes) {
    if (bytes.isEmpty || bytes.length >= maximumBytes) {
      throw ArgumentError('Choose an image smaller than 10 MB.');
    }
    bool begins(List<int> signature, [int offset = 0]) =>
        bytes.length >= offset + signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[offset + i],
        ).asMap().entries.every((entry) => entry.value == signature[entry.key]);
    if (begins([0xff, 0xd8, 0xff])) return 'image/jpeg';
    if (begins([137, 80, 78, 71, 13, 10, 26, 10])) return 'image/png';
    if (begins([82, 73, 70, 70]) && begins([87, 69, 66, 80], 8)) {
      return 'image/webp';
    }
    if (begins([71, 73, 70, 56, 55, 97]) || begins([71, 73, 70, 56, 57, 97])) {
      return 'image/gif';
    }
    throw ArgumentError('Choose a JPEG, PNG, WebP or GIF image.');
  }

  static bool isPrivateImagePath(String value, String chatId) =>
      value.startsWith('chatMedia/$chatId/') &&
      value.split('/').length == 3 &&
      !value.contains('..') &&
      !value.contains('\\');

  void _requireOwner(String uid) {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Your account changed. Open this chat again.');
    }
  }

  Future<String> uploadChatImage({
    required String chatId,
    required XFile file,
    String? expectedUid,
  }) async {
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    if (ownerUid == null) throw StateError('Sign in to send a photo.');
    if (expectedUid != null && ownerUid != expectedUid) {
      throw StateError('Your account changed. Open this chat again.');
    }
    if (await file.length() >= maximumBytes) {
      throw ArgumentError('Choose an image smaller than 10 MB.');
    }
    final bytes = await file.readAsBytes();
    _requireOwner(ownerUid);
    return uploadChatImageBytes(
      chatId: chatId,
      bytes: bytes,
      expectedUid: ownerUid,
    );
  }

  Future<String> uploadChatImageBytes({
    required String chatId,
    required List<int> bytes,
    String fileName = "chat-image.jpg",
    String? expectedUid,
  }) async {
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    if (ownerUid == null) throw StateError('Sign in to send a photo.');
    if (expectedUid != null && expectedUid != ownerUid) {
      throw StateError('Your account changed. Open this chat again.');
    }
    if (chatId.isEmpty || chatId.contains('/') || chatId.contains('..')) {
      throw ArgumentError('Invalid chat.');
    }
    final contentType = contentTypeForBytes(bytes);
    final chat = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .get();
    _requireOwner(ownerUid);
    final data = chat.data();
    if (data == null ||
        !(data['participants'] as List? ?? []).contains(ownerUid) ||
        data['closedAt'] != null) {
      throw StateError('This chat is unavailable.');
    }
    final suffix = List.generate(
      20,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final extension = switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'gif',
    };
    final path = 'chatMedia/$chatId/$ownerUid-$suffix.$extension';
    await FirebaseStorage.instance
        .ref(path)
        .putData(
          Uint8List.fromList(bytes),
          SettableMetadata(
            contentType: contentType,
            customMetadata: {'ownerUid': ownerUid, 'chatId': chatId},
          ),
        )
        .timeout(const Duration(seconds: 45));
    _requireOwner(ownerUid);
    return path;
  }

  Future<Uint8List?> loadPrivateImage(String path, String chatId) async {
    if (!isPrivateImagePath(path, chatId))
      throw ArgumentError('Invalid image.');
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    if (ownerUid == null) throw StateError('Sign in to view this photo.');
    final bytes = await FirebaseStorage.instance
        .ref(path)
        .getData(maximumBytes)
        .timeout(const Duration(seconds: 20));
    _requireOwner(ownerUid);
    return bytes;
  }

  /// Remove an orphan when message creation failed; rules permit only its owner.
  Future<void> discardImage(
    String path,
    String chatId,
    String expectedUid,
  ) async {
    _requireOwner(expectedUid);
    if (!isPrivateImagePath(path, chatId) ||
        !path.split('/').last.startsWith('$expectedUid-'))
      return;
    await FirebaseStorage.instance.ref(path).delete();
  }
}
