import 'dart:io';

import '../test/support/file_owner_checks.dart';

import '../test/support/migration_checks.dart';

Future<void> main() async {
  for (final check in {...fileOwnerChecks, ...migrationChecks}.entries) {
    await check.value();
    stdout.writeln('PASS ${check.key}');
  }
}
