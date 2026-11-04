import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/first_use_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a rejected platform write cannot acknowledge welcome or pollute reload',
    () async {
      const channel = MethodChannel('plugins.flutter.io/shared_preferences');
      final persisted = <String, Object>{};
      var allowWrites = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getAll':
            return Map<String, Object>.from(persisted);
          case 'setString':
            if (!allowWrites) return false;
            final arguments = Map<String, dynamic>.from(call.arguments as Map);
            persisted[arguments['key'] as String] =
                arguments['value'] as String;
            return true;
          default:
            throw PlatformException(
              code: 'Unexpected test call',
              message: call.method,
            );
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      SharedPreferences.resetStatic();
      final service = FirstUseService('write-failure');
      await service.load(autoWelcome: true);
      allowWrites = false;
      await expectLater(service.welcome(startTour: true), throwsStateError);
      expect(service.welcomeSeen, isFalse);
      expect(service.touring, isFalse);
      final restored = FirstUseService('write-failure');
      await restored.load();
      expect(restored.welcomeSeen, isFalse);
      allowWrites = true;
      await service.welcome(startTour: true);
      expect(service.welcomeSeen, isTrue);
      expect(service.touring, isTrue);
    },
  );
}
