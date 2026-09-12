import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/services/login_update_check_service.dart';
import 'package:prox/widgets/update_enforcement_gate.dart';

void main() {
  testWidgets(
      'live policy blocks both pointer and accessibility, preserves child state',
      (tester) async {
    var policy = const UpdateConfigSnapshot({'update_latest_version': '1.0.0'});
    final service = LoginUpdateCheckService.forTesting(
      versionLoader: () async => '1.0.0',
      configLoader: (_) async => policy,
    );
    await tester.pumpWidget(MaterialApp(
        home: UpdateEnforcementGate(
      service: service,
      child: const _Counter(),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Count 0'));
    await tester.pump();
    expect(find.text('Count 1'), findsOneWidget);

    policy = const UpdateConfigSnapshot({'update_latest_version': '1.1.0'});
    await service.check(forceRefresh: true);
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsOneWidget);
    expect(
        tester
            .widget<IgnorePointer>(find
                .descendant(
                    of: find.byType(UpdateEnforcementGate),
                    matching: find.byType(IgnorePointer))
                .first)
            .ignoring,
        isTrue);
    expect(
        tester
            .widget<ExcludeSemantics>(find
                .descendant(
                    of: find.byType(UpdateEnforcementGate),
                    matching: find.byType(ExcludeSemantics))
                .first)
            .excluding,
        isTrue);
    expect(find.text('Count 1'), findsOneWidget);

    policy = const UpdateConfigSnapshot({'update_check_enabled': false});
    await service.check(forceRefresh: true);
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsNothing);
    await tester.tap(find.text('Count 1'));
    await tester.pump();
    expect(find.text('Count 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    service.latestResult.dispose();
  });

  testWidgets(
      'mandatory gate survives refresh failure and scrolls on a small display',
      (tester) async {
    tester.view.physicalSize = const Size(320, 350);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var fail = false;
    final service = LoginUpdateCheckService.forTesting(
      versionLoader: () async => '1.0.0',
      configLoader: (_) async {
        if (fail) throw StateError('offline');
        return const UpdateConfigSnapshot({'update_latest_version': '1.1.0'});
      },
    );
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: UpdateEnforcementGate(service: service, child: child!),
      ),
      home: const Scaffold(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    fail = true;
    await tester.ensureVisible(find.text("I've updated, re-check"));
    await tester.tap(find.text("I've updated, re-check"));
    await tester.pumpAndSettle();
    expect(find.text('Update required'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    service.latestResult.dispose();
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: TextButton(
        onPressed: () => setState(() => count++),
        child: Text('Count $count'),
      ));
}
