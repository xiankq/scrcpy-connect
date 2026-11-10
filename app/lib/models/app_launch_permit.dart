abstract interface class AppLaunchPermit {
  bool get cancelled;
  bool claim();
  void cancel();
}
