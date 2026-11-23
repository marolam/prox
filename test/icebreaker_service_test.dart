import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/icebreaker_service.dart';

void main() {
  final now = DateTime(2026, 10, 11);
  Map<String, dynamic> observation({Object? encounter, bool nearby = true}) => {
    'nearby': nearby,
    'band': nearby ? 'close' : 'none',
    'code': '0123456789',
    'validUntilMs': now.add(const Duration(seconds: 15)).millisecondsSinceEpoch,
    'signals': nearby
        ? [
            {
              'key': 'pair',
              'colorIndex': 1,
              'symbolIndex': 2,
              'mark': 'ABCD',
              'band': 'close',
            },
          ]
        : [],
    'encounter': encounter,
  };
  final hidden = <String, dynamic>{
    'myReveal': true,
    'revealed': false,
    'myAdd': false,
    'connected': false,
  };

  test('signals expire even without another server response', () async {
    var clock = now;
    final service = IcebreakerService(
      now: () => clock,
      refreshLocation: () async {},
      call: (_, data) async => observation(),
    );
    await service.start('alice');
    expect(service.live, true);
    expect(service.signals.single.mark, 'ABCD');
    clock = now.add(const Duration(seconds: 15));
    service.expire();
    expect(service.live, false);
    expect(service.signals, isEmpty);
    expect(service.code, isNull);
    service.dispose();
  });

  test(
    'hidden encounter parser never exposes unsolicited keywords or peer names',
    () {
      final encounter = IcebreakerEncounter.fromMap({
        ...hidden,
        'keywords': ['private'],
        'peerName': 'private name',
      });
      expect(encounter.keywords, isEmpty);
      expect(encounter.peerName, isNull);
    },
  );

  test('mutual reveal and Party actions are separate and include only this session', () async {
    final actions = <String>[];
    final service = IcebreakerService(
      now: () => now,
      refreshLocation: () async {},
      call: (uid, data) async {
        expect(uid, 'alice');
        expect(data['token'], matches(RegExp(r'^[a-f0-9]{32}$')));
        actions.add(data['action']! as String);
        return data['action'] == 'observe'
            ? observation(encounter: hidden)
            : {
                'encounter': {
                  ...hidden,
                  'revealed': true,
                  'keywords': ['guitar'],
                  'peerName': 'Bob',
                  'myAdd': data['action'] == 'add',
                  'connected': data['action'] == 'add',
                },
              };
      },
    );
    await service.start('alice');
    expect(service.encounter!.keywords, isEmpty);
    await service.reveal();
    expect(service.encounter!.keywords, ['guitar']);
    expect(service.encounter!.connected, false);
    await service.addToParty();
    expect(service.encounter!.connected, true);
    expect(actions, ['observe', 'reveal', 'add']);
    service.dispose();
  });

  test('network errors clear glow and revealed data instead of keeping a stale success', () async {
    var fail = false;
    final service = IcebreakerService(
      now: () => now,
      refreshLocation: () async {},
      call: (_, data) async {
        if (fail)
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Offline',
          );
        return observation(
          encounter: {
            ...hidden,
            'revealed': true,
            'keywords': ['guitar'],
            'peerName': 'Bob',
          },
        );
      },
    );
    await service.start('alice');
    fail = true;
    await service.refresh();
    expect(service.error, 'Offline');
    expect(service.signals, isEmpty);
    expect(service.encounter, isNull);
    expect(service.hasEncounter, false);
    service.dispose();
  });

  test(
    'late response after stop cannot restore participation or private data',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final service = IcebreakerService(
        now: () => now,
        refreshLocation: () async {},
        call: (_, data) async =>
            data['action'] == 'stop' ? {'stopped': true} : pending.future,
      );
      final opening = service.start('alice');
      await Future<void>.delayed(Duration.zero);
      await service.stop();
      pending.complete(observation());
      await opening;
      expect(service.live, false);
      expect(service.signals, isEmpty);
      expect(service.active, false);
      service.dispose();
    },
  );

  test('malformed responses fail visibly and never invent a signal', () async {
    final service = IcebreakerService(
      now: () => now,
      refreshLocation: () async {},
      call: (_, data) async => {'nearby': true, 'signals': []},
    );
    await service.start('alice');
    expect(service.error, isNotNull);
    expect(service.live, false);
    expect(service.nearby, false);
    service.dispose();
  });

  test(
    'a pause during startup prevents a late start from reopening the session',
    () async {
      final stopping = Completer<Map<String, dynamic>>();
      var delayStop = false;
      final service = IcebreakerService(
        now: () => now,
        refreshLocation: () async {},
        call: (_, data) async {
          if (delayStop && data['action'] == 'stop') return stopping.future;
          return observation();
        },
      );
      await service.start('alice');
      delayStop = true;
      final reopening = service.start('bob');
      await Future<void>.delayed(Duration.zero);
      await service.stop();
      stopping.complete({'stopped': true});
      await reopening;
      expect(service.active, false);
      expect(service.signals, isEmpty);
      service.dispose();
    },
  );
}
