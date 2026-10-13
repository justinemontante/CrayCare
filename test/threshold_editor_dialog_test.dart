import 'package:craycare/widgets/settings/threshold_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackedController extends TextEditingController {
  _TrackedController() : super(text: '5');
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  for (final dismissal in ['Update', 'Cancel', 'Back']) {
    testWidgets('focused threshold fields survive $dismissal and reopening', (
      tester,
    ) async {
      late List<_TrackedController> controllers;
      final results = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  controllers = [_TrackedController(), _TrackedController()];
                  final result = await showThresholdEditorDialog<String>(
                    context: context,
                    controllers: controllers,
                    builder: (dialogContext) => AlertDialog(
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final controller in controllers)
                            TextField(controller: controller),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(
                            dialogContext,
                            controllers.first.text,
                          ),
                          child: const Text('Update'),
                        ),
                      ],
                    ),
                  );
                  results.add(result);
                },
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );

      // Repeated editing must release every route and its focused fields.
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '6.5');
        await tester.showKeyboard(find.byType(TextField).last);
        if (dismissal == 'Back') {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text(dismissal));
        }
        await tester.pump();
        expect(controllers.every((controller) => !controller.disposed), isTrue);
        expect(results.length, attempt);
        await tester.pumpAndSettle();
        expect(controllers.every((controller) => controller.disposed), isTrue);
        expect(results.length, attempt + 1);
        expect(results.last, dismissal == 'Update' ? '6.5' : null);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
