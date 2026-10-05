import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:prox/services/auth/authenticated_callable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prox/models/support_ticket.dart';
import 'package:prox/services/app_build_info_service.dart';
import 'package:prox/services/image_picker_guard.dart';

enum SupportCategory {
  bug('Bug Report'),
  ux('Usability'),
  billing('Billing'),
  feature('Feature idea'),
  question('Question');

  const SupportCategory(this.label);
  final String label;
}

/// Keep uncertain deliveries retryable without treating every rejection as
/// a connection failure or exposing server exception payloads.
String supportSubmissionErrorMessage(
  Object error, {
  bool deliveryUncertain = false,
}) {
  if (deliveryUncertain && supportSubmissionWasRejected(error)) {
    return 'The latest attempt was rejected, but an earlier attempt may have arrived. Check My support tickets or retry this saved report with the same details.';
  }
  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'unauthenticated' =>
        'Your sign-in could not be verified. Sign in again, then retry. Your draft is kept.',
      'permission-denied' =>
        'This account could not submit the report. Check your account and screenshot, then retry. Your draft is kept.',
      'invalid-argument' =>
        'Check the subject, message, category, and screenshot, then try again. Your draft is kept.',
      'resource-exhausted' =>
        'The support submission limit has been reached. Your draft is kept; try again later.',
      'failed-precondition' =>
        'Reopen your saved draft and check your account and screenshot before retrying.',
      'already-exists' =>
        'This draft differs from an earlier submission. Check My support tickets before sending a new report.',
      _ =>
        'Submission could not be confirmed. Retry with this saved draft; it will keep the same report reference.',
    };
  }
  if (error is FirebaseAuthException ||
      (error is StateError &&
          const {
            'Sign in to the account that created this report.',
            'Your account changed. Return to the original account to retry.',
            'Sign in to the account that opened this screen.',
            'Your account changed. Reopen this screen.',
          }.contains(error.message))) {
    return 'Return to the account that created this draft, then retry. Your draft is kept.';
  }
  return 'Submission could not be confirmed. Retry with this saved draft; it will keep the same report reference.';
}

bool supportSubmissionWasRejected(Object error) =>
    error is FirebaseFunctionsException &&
    const {
      'unauthenticated',
      'permission-denied',
      'invalid-argument',
      'resource-exhausted',
      'failed-precondition',
    }.contains(error.code);

/// An image stays private: the callable receives a Storage path, never a URL.
class SupportAttachment {
  const SupportAttachment({required this.bytes, required this.contentType});
  final Uint8List bytes;
  final String contentType;
  static const maximumBytes = 5 * 1024 * 1024;

  String get extension => switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => throw ArgumentError('Choose a JPEG, PNG, or WebP screenshot.'),
  };

  factory SupportAttachment.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumBytes) {
      throw ArgumentError('Choose a screenshot smaller than 5 MB.');
    }
    bool startsWith(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((matches) => matches);
    final contentType = startsWith([0xff, 0xd8, 0xff])
        ? 'image/jpeg'
        : startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        ? 'image/png'
        : bytes.length >= 12 &&
              startsWith([0x52, 0x49, 0x46, 0x46]) &&
              String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
        ? 'image/webp'
        : null;
    if (contentType == null) {
      throw ArgumentError('Choose a JPEG, PNG, or WebP screenshot.');
    }
    return SupportAttachment(bytes: bytes, contentType: contentType);
  }
}

class SupportReportRequest {
  const SupportReportRequest({
    required this.requestId,
    required this.category,
    required this.subject,
    required this.message,
    this.source = 'in_app',
    this.firstHuhMoment = '',
    this.metadata = const {},
    this.attachment,
    this.expectedUid,
  });
  final String requestId;
  final SupportCategory category;
  final String subject;
  final String message;
  final String source;
  final String firstHuhMoment;
  final Map<String, String> metadata;
  final SupportAttachment? attachment;
  final String? expectedUid;
}

class SupportReply {
  const SupportReply({
    required this.id,
    required this.message,
    required this.fromSupport,
    this.createdAt,
  });
  final String id;
  final String message;
  final bool fromSupport;
  final DateTime? createdAt;
}

class TrackedSupportTicket {
  const TrackedSupportTicket({
    required this.id,
    required this.subject,
    required this.message,
    this.status = 'open',
    this.category = 'question',
    this.severity = 'P2',
    this.acknowledgement = '',
    this.fixedVersion = '',
    this.fixedBuild = '',
    this.attachmentPaths = const [],
    this.createdAt,
  });
  final String id;
  final String subject;
  final String message;
  final String status;
  final String category;
  final String severity;
  final String acknowledgement;
  final String fixedVersion;
  final String fixedBuild;
  final List<String> attachmentPaths;
  final DateTime? createdAt;

  String get statusLabel => switch (status) {
    'acknowledged' => 'Acknowledged',
    'in_progress' => 'In progress',
    'resolved' => 'Resolved',
    'closed' => 'Closed',
    _ => 'Received',
  };

  String get fixedLabel => fixedVersion.isEmpty && fixedBuild.isEmpty
      ? ''
      : 'Fixed in ${fixedVersion.isEmpty ? 'app' : 'version $fixedVersion'}'
            '${fixedBuild.isEmpty ? '' : ', build $fixedBuild'}';

  factory TrackedSupportTicket.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    final rawDate = data['createdAt'];
    return TrackedSupportTicket(
      id: snapshot.id,
      subject: '${data['subject'] ?? 'Support report'}',
      message: '${data['message'] ?? ''}',
      status: '${data['status'] ?? 'open'}',
      category: '${data['category'] ?? 'question'}',
      severity: '${data['severity'] ?? 'P2'}',
      acknowledgement: '${data['acknowledgement'] ?? ''}',
      fixedVersion: '${data['fixedVersion'] ?? ''}',
      fixedBuild: '${data['fixedBuild'] ?? ''}',
      attachmentPaths: (data['attachmentPaths'] is List)
          ? (data['attachmentPaths'] as List).whereType<String>().toList()
          : [],
      createdAt: rawDate is Timestamp ? rawDate.toDate() : null,
    );
  }
}

class SupportService {
  SupportService._();
  static final SupportService instance = SupportService._();
  static const _deviceChannel = MethodChannel('prox/device_metadata');

  static String newRequestId() {
    final random = Random.secure();
    return 'support_${List.generate(20, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  static Future<Map<String, String>> collectMetadata() async {
    final metadata = <String, String>{
      'version': 'unknown',
      'build': 'unknown',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'device': kIsWeb ? 'web browser' : 'unknown',
      'os': 'unknown',
    };
    try {
      final package = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 3),
      );
      metadata['version'] = package.version;
      metadata['build'] = package.buildNumber;
    } catch (_) {
      final full = await AppBuildInfoService.instance.fullVersion();
      metadata['version'] = full.split('+').first;
      if (full.contains('+')) metadata['build'] = full.split('+').last;
    }
    if (!kIsWeb) {
      try {
        final device = await _deviceChannel
            .invokeMapMethod<String, dynamic>('getMetadata')
            .timeout(const Duration(seconds: 2));
        for (final key in ['device', 'os']) {
          if (device?[key] is String && (device![key] as String).isNotEmpty) {
            metadata[key] = (device[key] as String).substring(
              0,
              min(120, (device[key] as String).length),
            );
          }
        }
      } catch (_) {
        /* Desktop/web or an older host may have no channel. */
      }
    }
    return metadata;
  }

  static Future<SupportAttachment?> pickScreenshot() async {
    if (!ImagePickerGuard.tryAcquire()) return null;
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2200,
        maxHeight: 2200,
        imageQuality: 85,
      );
      if (image == null) return null;
      if (await image.length() > SupportAttachment.maximumBytes) {
        throw ArgumentError('Choose a screenshot smaller than 5 MB.');
      }
      return SupportAttachment.fromBytes(await image.readAsBytes());
    } finally {
      ImagePickerGuard.release();
    }
  }

  Future<String> submitReport(SupportReportRequest request) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null ||
        (request.expectedUid != null && uid != request.expectedUid)) {
      throw StateError('Sign in to the account that created this report.');
    }
    final paths = <String>[];
    final attachment = request.attachment;
    if (attachment != null) {
      final path =
          'supportAttachments/$uid/${request.requestId}/screenshot.${attachment.extension}';
      await FirebaseStorage.instance
          .ref(path)
          .putData(
            attachment.bytes,
            SettableMetadata(contentType: attachment.contentType),
          )
          .timeout(const Duration(seconds: 30));
      paths.add(path);
    }
    final metadata = request.metadata.isEmpty
        ? await collectMetadata()
        : request.metadata;
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError(
        'Your account changed. Return to the original account to retry.',
      );
    }
    final result = await callAuthenticatedFunction<Map<String, dynamic>>(
      'submitGrowthSupport',
      {
        'requestId': request.requestId,
        'expectedUid': uid,
        'category': request.category.name,
        'subject': request.subject,
        'message': request.message,
        'source': request.source,
        'firstHuhMoment': request.firstHuhMoment,
        'metadata': metadata,
        'attachmentPaths': paths,
      },
    );
    return '${result.data['ticketId'] ?? request.requestId}';
  }

  Future<void> createTicket(SupportTicket ticket) async {
    await submitReport(
      SupportReportRequest(
        requestId: ticket.id.trim().isEmpty ? newRequestId() : ticket.id.trim(),
        category: SupportCategory.question,
        subject: ticket.subject,
        message: ticket.message,
        source: 'support_compose',
        expectedUid: ticket.uid,
      ),
    );
  }

  Stream<List<TrackedSupportTicket>> watchTickets(String uid) =>
      FirebaseFirestore.instance
          .collection('supportTickets')
          .where('uid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(TrackedSupportTicket.fromDocument).toList(),
          );

  Stream<TrackedSupportTicket> watchTicket(String ticketId) => FirebaseFirestore
      .instance
      .collection('supportTickets')
      .doc(ticketId)
      .snapshots()
      .map(TrackedSupportTicket.fromDocument);

  Stream<List<SupportReply>> watchReplies(String ticketId) => FirebaseFirestore
      .instance
      .collection('supportTickets')
      .doc(ticketId)
      .collection('replies')
      .orderBy('createdAt')
      .limitToLast(100)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          final date = data['createdAt'];
          return SupportReply(
            id: doc.id,
            message: '${data['message'] ?? ''}',
            fromSupport: data['author'] == 'support',
            createdAt: date is Timestamp ? date.toDate() : null,
          );
        }).toList(),
      );

  Future<void> sendReply({
    required String ticketId,
    required String requestId,
    required String message,
  }) async {
    final ownerUid = FirebaseAuth.instance.currentUser?.uid;
    if (ownerUid == null) {
      throw StateError('Sign in to reply to support.');
    }
    await callAuthenticatedFunction<Map<String, dynamic>>(
      'replyToSupportTicket',
      {
        'ticketId': ticketId,
        'requestId': requestId,
        'message': message,
        'expectedUid': ownerUid,
      },
    );
    if (FirebaseAuth.instance.currentUser?.uid != ownerUid) {
      throw StateError('Your account changed while sending the reply.');
    }
  }

  Future<Uint8List?> loadAttachment(String path) => FirebaseStorage.instance
      .ref(path)
      .getData(SupportAttachment.maximumBytes)
      .timeout(const Duration(seconds: 15));
}
