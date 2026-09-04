import 'dart:async';

import 'package:craycare/models/control_types.dart';
import 'package:craycare/widgets/controls/feeder_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpFeeder(
    WidgetTester tester, {
    List<ScheduleItem> schedules = const [],
    Future<bool> Function(double?, String)? onAdd,
    Future<bool> Function(int, ScheduleItem)? onEdit,
  }) async {
    final errorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint(details.toString());
      errorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = errorHandler);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: '6:00:AM');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeederTab(
            schedules: schedules,
            timeCtl: controller,
            onFeedNow: () {},
            onAddSchedule: onAdd ?? (_, _) async => true,
            onDeleteSchedule: (_) {},
            onEditSchedule: onEdit ?? (_, _) async => true,
            onToggleSchedule: (_, _) {},
            feederLogs: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('skipped device outcome is not rendered as completed', (
    tester,
  ) async {
    final now = manilaWallClock();
    final at = DateTime.utc(
      now.year,
      now.month,
      now.day,
      8,
    ).subtract(manilaUtcOffset);
    await pumpFeeder(
      tester,
      schedules: [
        ScheduleItem(
          '8:00',
          'AM',
          id: 'one',
          isDone: true,
          lastOutcome: 'skipped_insufficient',
          lastOccurrenceAt: at,
        ),
      ],
    );
    expect(find.text('SKIPPED'), findsOneWidget);
    expect(find.text('COMPLETED'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add schedule rejects unsupported dose and waits for save', (
    tester,
  ) async {
    final saved = Completer<bool>();
    var calls = 0;
    await pumpFeeder(
      tester,
      onAdd: (_, _) {
        calls++;
        return saved.future;
      },
    );
    await tester.ensureVisible(find.text('Add Schedule'));
    await tester.tap(find.text('Add Schedule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '35');
    await tester.pump();
    expect(find.textContaining('Use 20–200 g'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Add'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '40');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(TextField), findsOneWidget);
    saved.complete(false);
    await tester.pumpAndSettle();
    expect(
      find.byType(TextField),
      findsOneWidget,
    ); // Failed save keeps user input.
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit schedule preserves the sheet when save fails', (
    tester,
  ) async {
    final saved = Completer<bool>();
    var calls = 0;
    await pumpFeeder(
      tester,
      schedules: [ScheduleItem('8:00', 'AM', grams: 20)],
      onEdit: (_, _) {
        calls++;
        return saved.future;
      },
    );
    await tester.ensureVisible(find.byTooltip('Schedule actions'));
    await tester.tap(find.byTooltip('Schedule actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Edit Schedule'), findsOneWidget);
    saved.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Edit Schedule'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
