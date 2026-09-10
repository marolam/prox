import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/utils/async_pulse_scheduler.dart';

void main() {
  testWidgets(
    'completed bursts wait a full interval instead of looping immediately',
    (tester) async {
      var runs = 0;
      late AsyncPulseScheduler scheduler;
      scheduler = AsyncPulseScheduler(
        interval: () => const Duration(seconds: 10),
        canRun: () => true,
        action: () async {
          runs++;
          scheduler.start();
        },
        onError: (e, s) => fail('$e'),
      );
      addTearDown(scheduler.stop);
      scheduler.start(immediate: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(runs, 1);
      await tester.pump(const Duration(seconds: 9));
      expect(runs, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(runs, 2);
      scheduler.stop();
    },
  );

  testWidgets('stop and restart cannot overlap a previous in-flight burst', (
    tester,
  ) async {
    final pending = Completer<void>();
    var runs = 0;
    var active = 0;
    var peak = 0;
    final scheduler = AsyncPulseScheduler(
      interval: () => const Duration(seconds: 2),
      canRun: () => true,
      action: () async {
        runs++;
        active++;
        if (active > peak) peak = active;
        if (runs == 1) await pending.future;
        active--;
      },
      onError: (e, s) => fail('$e'),
    );
    addTearDown(scheduler.stop);
    scheduler.start(immediate: true);
    await tester.pump(const Duration(milliseconds: 1));
    scheduler.stop();
    scheduler.start(immediate: true);
    await tester.pump(const Duration(seconds: 8));
    expect(runs, 1);
    pending.complete();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(runs, 2);
    expect(peak, 1);
    scheduler.stop();
    await tester.pump(const Duration(minutes: 1));
    expect(runs, 2);
  });

  testWidgets(
    'errors retry at the interval and foreground suspension stops work',
    (tester) async {
      var allowed = true;
      var runs = 0;
      var errors = 0;
      final scheduler = AsyncPulseScheduler(
        interval: () => const Duration(seconds: 5),
        canRun: () => allowed,
        action: () async {
          runs++;
          throw StateError('offline');
        },
        onError: (e, s) {
          errors++;
        },
      );
      addTearDown(scheduler.stop);
      scheduler.start(immediate: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(errors, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(runs, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(errors, 2);
      allowed = false;
      await tester.pump(const Duration(minutes: 1));
      expect(runs, 2);
      allowed = true;
      scheduler.start(immediate: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(runs, 3);
      scheduler.stop();
    },
  );
}
