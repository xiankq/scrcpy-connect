import 'package:flutter_test/flutter_test.dart';

import 'support/transfer_checks.dart';

import 'support/migration_checks.dart';

void main() {
  for (final check in {...transferChecks, ...migrationChecks}.entries) {
    test(check.key, check.value);
  }
}
