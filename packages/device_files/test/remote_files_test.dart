import 'package:flutter_test/flutter_test.dart';

import 'support/file_owner_checks.dart';

import 'support/migration_checks.dart';

void main() {
  for (final check in {...fileOwnerChecks, ...migrationChecks}.entries) {
    test(check.key, check.value);
  }
}
