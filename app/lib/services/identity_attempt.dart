import 'package:scrcpy_connect/models/identity_selection.dart';

abstract interface class IdentityAttempt {
  IdentitySelection get selection;
  Future<void> bindNew(String id);
  Future<void> dispose();
}
