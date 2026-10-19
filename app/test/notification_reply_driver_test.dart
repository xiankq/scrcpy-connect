import 'package:flutter_test/flutter_test.dart';

import '../../tool/driver/notification_reply.dart'
    show validateNotificationReplyReport;

const _runId = 'independent-run';
const _text = '真实 RemoteInput\n中文 👋';
const _receipt = <String, dynamic>{
  'runId': _runId,
  'messageId': '$_runId:0',
  'notificationId': 0,
  'text': _text,
  'count': 1,
};
const _report = <String, dynamic>{
  'notificationReplyComplete': true,
  'fixtureRunId': _runId,
  'fixtureTag': 'notification-fixture-$_runId',
  'replyText': _text,
  'notificationId': 'opaque-original-notification-id',
  'systemAcceptanceVisible': true,
  'deliveryUnconfirmedVisible': true,
  'reopenedReplyGuarded': true,
  'notificationDismissed': true,
  'dismissedReplyCopyMatches': true,
  'fixtureCleanupAcknowledged': true,
  'clipboardBaselinePresent': true,
  'clipboardRestored': true,
};

void _validate({
  Map<String, dynamic> report = _report,
  Map<String, dynamic>? receipt = _receipt,
  bool cleanupConfirmed = true,
}) => validateNotificationReplyReport(
  report,
  runId: _runId,
  expectedText: _text,
  receiverReceipt: receipt,
  cleanupConfirmed: cleanupConfirmed,
);

void main() {
  test(
    'scoped notification reply needs both UI and independent receiver evidence',
    () {
      expect(() => _validate(), returnsNormally);
      expect(() => _validate(report: const {}), throwsStateError);
      expect(
        () =>
            _validate(report: {..._report, 'notificationReplyComplete': false}),
        throwsStateError,
      );
      expect(
        () =>
            _validate(report: {..._report, 'productAcceptanceComplete': true}),
        throwsStateError,
      );
    },
  );

  test(
    'system acceptance alone never substitutes for target receiver delivery',
    () {
      expect(() => _validate(receipt: null), throwsStateError);
      expect(
        () => _validate(receipt: {..._receipt, 'count': 0}),
        throwsStateError,
      );
      expect(
        () => _validate(receipt: {..._receipt, 'count': 2}),
        throwsStateError,
      );
      expect(
        () => _validate(
          receipt: {..._receipt, 'text': 'different received content'},
        ),
        throwsStateError,
      );
      expect(
        () => _validate(receipt: {..._receipt, 'messageId': 'another-run:0'}),
        throwsStateError,
      );
    },
  );

  test('an unfinished UI guard or owned cleanup fails despite a valid receiver receipt', () {
    expect(
      () => _validate(report: {..._report, 'reopenedReplyGuarded': false}),
      throwsStateError,
    );
    expect(
      () => _validate(report: {..._report, 'dismissedReplyCopyMatches': false}),
      throwsStateError,
    );
    expect(() => _validate(cleanupConfirmed: false), throwsStateError);
    expect(
      () => _validate(report: {..._report, 'clipboardRestored': false}),
      throwsStateError,
    );
  });
}
