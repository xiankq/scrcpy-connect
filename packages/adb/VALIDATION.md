# ADB validation

Linux x86_64, Flutter 3.47.7/Dart 3.13.5 and platform-tools 37.0.1 were tested on 2026-10-23 with an authorized API 36 AVD. Private directories/loopback servers isolated the tests from SDK port 5037 and other transports.

Coverage includes Dart service ownership/backpressure/cancellation, official-server startup/exit and binary transfers, Rust smart-socket transport pinning, reverse/JDWP and SYNC compression/bounds. [Test commands and device setup](test/README.md) describe reproducible entry points.

This establishes Linux/AVD protocol behavior. Windows/macOS execution, physical USB handoff, mobile FRB calls and real wireless pairing/TLS require separate validation; secure-routing fixtures alone do not prove pairing.
