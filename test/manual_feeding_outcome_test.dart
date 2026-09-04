import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/models/control_types.dart';

void main() {
  test('each terminal device response resolves its own manual request', () {
    for (final status in [
      'completed',
      'skipped_insufficient',
      'blocked',
      'failed',
    ]) {
      expect(
        manualFeedingOutcome(
          commandId: 'new',
          statusCommandId: 'new',
          status: status,
          logs: [],
        ),
        status,
      );
    }
  });
  test('old or scheduled responses never complete the current request', () {
    expect(
      manualFeedingOutcome(
        commandId: 'new',
        statusCommandId: 'old',
        status: 'completed',
        logs: [
          LogEntry(
            'old feed',
            'manual',
            '',
            '',
            commandId: 'old',
            status: 'completed',
          ),
          LogEntry('scheduled feed', 'auto', '', '', status: 'completed'),
        ],
      ),
      isNull,
    );
    expect(
      manualFeedingOutcome(
        commandId: null,
        statusCommandId: null,
        status: 'completed',
        logs: [],
      ),
      isNull,
    );
  });
  test('queued/checking/dispensing are not terminal outcomes', () {
    for (final status in ['idle', 'checking_feed_level', 'dispensing']) {
      expect(
        manualFeedingOutcome(
          commandId: 'new',
          statusCommandId: 'new',
          status: status,
          logs: [],
        ),
        isNull,
      );
    }
  });
  test(
    'durable log resolves a request even if the live status has moved on',
    () {
      expect(
        manualFeedingOutcome(
          commandId: 'new',
          statusCommandId: 'another',
          status: 'dispensing',
          logs: [
            LogEntry(
              'Skipped',
              'manual',
              '',
              '',
              commandId: 'new',
              status: 'skipped_insufficient',
            ),
          ],
        ),
        'skipped_insufficient',
      );
    },
  );
}
