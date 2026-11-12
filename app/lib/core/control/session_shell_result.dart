final class SessionShellResult {
  const SessionShellResult(this.stdout, this.stderr, this.exitCode);
  final String stdout, stderr;
  final int? exitCode;
}
