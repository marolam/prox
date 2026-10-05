import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/chat_media_service.dart';

void main() {
  test(
    'image bytes determine upload MIME and reject mislabeled executable data',
    () {
      expect(
        ChatMediaService.contentTypeForBytes([0xff, 0xd8, 0xff, 0]),
        'image/jpeg',
      );
      expect(
        ChatMediaService.contentTypeForBytes([137, 80, 78, 71, 13, 10, 26, 10]),
        'image/png',
      );
      expect(
        ChatMediaService.contentTypeForBytes([
          82,
          73,
          70,
          70,
          0,
          0,
          0,
          0,
          87,
          69,
          66,
          80,
        ]),
        'image/webp',
      );
      expect(
        ChatMediaService.contentTypeForBytes([71, 73, 70, 56, 57, 97]),
        'image/gif',
      );
      expect(
        () => ChatMediaService.contentTypeForBytes([60, 115, 118, 103]),
        throwsArgumentError,
      );
      expect(
        () => ChatMediaService.contentTypeForBytes([]),
        throwsArgumentError,
      );
      expect(
        () => ChatMediaService.contentTypeForBytes(
          List.filled(ChatMediaService.maximumBytes, 0),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'private image references cannot escape the active chat storage folder',
    () {
      expect(
        ChatMediaService.isPrivateImagePath(
          'chatMedia/pair/alice-abc.jpg',
          'pair',
        ),
        isTrue,
      );
      for (final path in [
        'chatMedia/other/alice-abc.jpg',
        'chatMedia/pair/../secret.jpg',
        'https://example.test/photo.jpg',
        'chatMedia/pair/alice\\secret.jpg',
      ]) {
        expect(ChatMediaService.isPrivateImagePath(path, 'pair'), isFalse);
      }
    },
  );
}
