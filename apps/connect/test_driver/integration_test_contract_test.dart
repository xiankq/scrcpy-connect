import 'dart:io';

import 'integration_test.dart' show validateAcceptanceReport;

// Run directly with Dart; no driver connection, device or Flutter test engine.
void main(List<String> arguments) {
  if (arguments.contains('--missing-product')) {
    validateAcceptanceReport(const {}, environment: const {});
    throw StateError('A missing product receipt was incorrectly accepted.');
  }

  void rejects(
    Map<String, dynamic> metadata, {
    Map<String, String> environment = const {},
    required String reason,
  }) {
    try {
      validateAcceptanceReport(metadata, environment: environment);
    } on StateError catch (error) {
      if (error.message.toString().contains(reason)) return;
      rethrow;
    }
    throw StateError('Acceptance incorrectly passed: $reason');
  }

  for (final metadata in <Map<String, dynamic>>[
    {},
    {'productAcceptanceComplete': false},
    {'productAcceptanceComplete': 'true'},
    {'mediaAcceptanceComplete': true},
    {'audioAcceptanceComplete': true},
  ]) {
    rejects(metadata, reason: 'real product acceptance');
  }
  validateAcceptanceReport({
    'productAcceptanceComplete': true,
  }, environment: const {});
  const media = {'CONNECT_E2E_ACCEPTANCE': 'media'};
  for (final metadata in <Map<String, dynamic>>[
    {},
    {'mediaAcceptanceComplete': false},
    {'mediaAcceptanceComplete': 'true'},
    {'productAcceptanceComplete': true},
  ]) {
    rejects(metadata, environment: media, reason: 'scoped media acceptance');
  }
  validateAcceptanceReport({
    'mediaAcceptanceComplete': true,
  }, environment: media);
  rejects(
    {'mediaAcceptanceComplete': true, 'productAcceptanceComplete': false},
    environment: media,
    reason: 'real product acceptance',
  );
  rejects(
    const {},
    environment: {'CONNECT_E2E_ACCEPTANCE': 'unknown'},
    reason: 'Unknown acceptance scope',
  );
  const background = {'CONNECT_E2E_BACKGROUND': '1'};
  const audio = {'CONNECT_E2E_AUDIO_LIFECYCLE': '1'};
  rejects(
    {'productAcceptanceComplete': true},
    environment: background,
    reason: 'background media acceptance',
  );
  rejects(
    {'productAcceptanceComplete': true},
    environment: audio,
    reason: 'shared audio acceptance',
  );
  validateAcceptanceReport({
    'mediaAcceptanceComplete': true,
  }, environment: background);
  validateAcceptanceReport({
    'audioAcceptanceComplete': true,
  }, environment: audio);
  rejects(
    {'mediaAcceptanceComplete': true},
    environment: {...background, ...audio},
    reason: 'shared audio acceptance',
  );
  validateAcceptanceReport(
    {'mediaAcceptanceComplete': true, 'audioAcceptanceComplete': true},
    environment: {...background, ...audio},
  );
  rejects(
    {'productAcceptanceComplete': false, 'mediaAcceptanceComplete': true},
    environment: background,
    reason: 'real product acceptance',
  );
  // Existing system-picker and clipboard fixtures do not use the product target.
  for (final fixture in ['CONNECT_E2E_CLIPBOARD', 'CONNECT_E2E_DOCUMENTS']) {
    validateAcceptanceReport(const {}, environment: {fixture: '1'});
  }
  stdout.writeln('Driver acceptance contracts passed.');
}
