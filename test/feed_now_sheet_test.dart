import 'package:craycare/widgets/controls/feed_now_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Feed Now validates amount and closes without lifecycle errors', (
    tester,
  ) async {
    double? submitted;
    var showingFeedStatus = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setParentState) => Stack(
              children: [
                ElevatedButton(
                  onPressed: () async {
                    submitted = await showModalBottomSheet<double>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const FeedNowSheet(),
                    );
                    setParentState(() => showingFeedStatus = true);
                  },
                  child: const Text('Open Feed Now'),
                ),
                if (showingFeedStatus)
                  const Center(
                    child: Material(child: Text('Waiting for feeder')),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Feed Now'));
    await tester.pumpAndSettle();
    expect(find.text('Feed Now'), findsOneWidget);
    expect(find.textContaining('1 swing'), findsNothing);
    expect(find.textContaining('Requested dose'), findsNothing);
    expect(find.textContaining('Out-of-range readings'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.enabledBorder, isA<OutlineInputBorder>());
    expect(
      (field.decoration!.enabledBorder! as OutlineInputBorder).borderSide.color,
      isNot(Colors.grey),
    );
    final dispenseButton = find.ancestor(
      of: find.text('Dispense Feed'),
      matching: find.byType(ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(dispenseButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '2');
    await tester.pump();
    await tester.tap(find.text('Dispense Feed'));
    await tester.pumpAndSettle();
    expect(submitted, 2);
    expect(find.text('Waiting for feeder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
