import 'package:flutter_test/flutter_test.dart';

import '../driver/system_notifications.dart'
    show validateSystemNotificationsReport;

const _runId = '0123456789abcdef0123456789abcdef';
const _report = <String, dynamic>{
  'systemNotificationsComplete': true,
  'fixtureRunId': _runId,
  'sourceNotificationIds': ['source-a', 'source-b'],
  'permissionGranted': true,
  'automaticObservationLive': true,
  'realNotificationEventObserved': true,
  'exactSourceWithdrawalVerified': true,
  'notificationsPageOpened': true,
  'clickedSourceStillLive': true,
  'remoteSessionUnchanged': true,
  'fixtureCleanupAcknowledged': true,
};
const _receipt = <String, dynamic>{
  'runId': _runId,
  'channel': 'remote_notifications',
  'genericRecordCount': 2,
  'sourceRecordCount': 2,
  'localNotificationIds': [100000, 100001],
  'actualHome': true,
  'baselineEmpty': true,
  'genericContentOnly': true,
  'exactWithdrawal': true,
  'otherMirrorRetained': true,
  'foregroundServiceRetained': true,
  'actualSystemUiTap': true,
  'targetForegroundUnchanged': true,
  'ownedSourcesAbsent': true,
  'ownedMirrorsAbsent': true,
};

void _validate({
  Map<String, dynamic> report = _report,
  Map<String, dynamic>? receipt = _receipt,
  bool cleanup = true,
}) => validateSystemNotificationsReport(
  report,
  runId: _runId,
  osReceipt: receipt,
  cleanupConfirmed: cleanup,
);

void main() {
  test(
    'scoped completion requires real app and independent Android evidence',
    () {
      expect(() => _validate(), returnsNormally);
      expect(() => _validate(report: {}), throwsStateError);
      expect(
        () =>
            _validate(report: {..._report, 'productAcceptanceComplete': true}),
        throwsStateError,
      );
      expect(
        () => _validate(
          report: {..._report, 'systemNotificationsComplete': false},
        ),
        throwsStateError,
      );
      expect(() => _validate(receipt: null), throwsStateError);
      expect(() => _validate(receipt: {}), throwsStateError);
    },
  );

  test('missing or wrong-run app receipts cannot claim OS acceptance', () {
    for (final key in _report.keys) {
      final incomplete = {..._report}..remove(key);
      expect(
        () => _validate(report: incomplete),
        throwsStateError,
        reason: 'Required app receipt: $key',
      );
    }
    expect(
      () => _validate(report: {..._report, 'fixtureRunId': 'different-run'}),
      throwsStateError,
    );
    for (final ids in <List<Object?>>[
      <Object?>[],
      ['a'],
      ['a', 'a'],
      ['a', ''],
      ['a', 1],
    ]) {
      expect(
        () => _validate(report: {..._report, 'sourceNotificationIds': ids}),
        throwsStateError,
      );
    }
  });

  test('HOME, privacy, exact cancellation, SystemUI tap and FGS proof are mandatory', () {
    for (final key in _receipt.keys) {
      final incomplete = {..._receipt}..remove(key);
      expect(
        () => _validate(receipt: incomplete),
        throwsStateError,
        reason: 'Required independent Android receipt: $key',
      );
    }
    for (final key in _receipt.keys.where((key) => _receipt[key] == true)) {
      expect(
        () => _validate(receipt: {..._receipt, key: false}),
        throwsStateError,
        reason: 'Failed independent Android receipt: $key',
      );
    }
    expect(
      () => _validate(receipt: {..._receipt, 'runId': 'different-run'}),
      throwsStateError,
    );
    expect(
      () => _validate(receipt: {..._receipt, 'channel': 'incoming_calls'}),
      throwsStateError,
    );
    expect(
      () => _validate(receipt: {..._receipt, 'genericRecordCount': 1}),
      throwsStateError,
    );
  });

  test(
    'OS identities must be distinct and cannot own the connection service',
    () {
      for (final ids in <List<Object?>>[
        <Object?>[],
        [100000],
        [100000, 100000],
        [2101, 100001],
        [99999, 100001],
        [100000, 200000],
        ['100000', 100001],
      ]) {
        expect(
          () => _validate(receipt: {..._receipt, 'localNotificationIds': ids}),
          throwsStateError,
        );
      }
    },
  );

  test(
    'cleanup is awaited and required even after otherwise valid evidence',
    () {
      expect(() => _validate(cleanup: false), throwsStateError);
      expect(
        () => _validate(
          report: {..._report, 'fixtureCleanupAcknowledged': false},
        ),
        throwsStateError,
      );
      expect(
        () => _validate(receipt: {..._receipt, 'ownedSourcesAbsent': false}),
        throwsStateError,
      );
      expect(
        () => _validate(receipt: {..._receipt, 'ownedMirrorsAbsent': false}),
        throwsStateError,
      );
    },
  );
}
