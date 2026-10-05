import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/utils/dialog_lifecycle.dart';

class _ObservedController extends TextEditingController {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  for (final save in [true, false]) {
    testWidgets(
      '${save ? 'saving' : 'canceling'} keeps controllers alive until dialog exit completes',
      (tester) async {
        final controller = _ObservedController();
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialogUntilRemoved<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Reply'),
                        content: TextField(controller: controller),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, save),
                            child: const Text('Close dialog'),
                          ),
                        ],
                      ),
                    );
                    controller.dispose();
                  },
                  child: const Text('Open dialog'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Fixed in this build');
        await tester.tap(find.text('Close dialog'));
        await tester.pump();
        expect(controller.disposed, isFalse);
        expect(find.byType(TextField), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(controller.disposed, isTrue);
        expect(result, save);
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
