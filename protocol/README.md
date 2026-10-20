# Shared command contract

`commands.json` is the source for the Dart and Rust command discriminators,
declared request/result fields, and state-verification policy. `owner: core`
crosses FRB; `owner: bridge` is resolved by the main device's local coordinator.
Platform MethodChannel methods and companion RPC methods are separate protocols.

Run `dart tool/protocol_codegen.dart` from the repository root after changing the contract.
`--check` formats expected outputs in memory and compares them without writing.
The main check script checks this contract and independently checks FRB output.

The wire envelope is version 1:

```json
{"protocolVersion":1,"command":"devices.list","params":{}}
{"protocolVersion":1,"ok":true,"data":{"devices":[]}}
{"protocolVersion":1,"ok":false,"error":{"code":"disconnected","message":"...","details":null}}
```

Rust accepts an omitted request version as legacy v1. New Dart requests include
the version and reject a missing or different response version. Bridge and native
library must ship together. The native request limit counts UTF-8 bytes, as does
the Dart encoder.

Declared fields reject missing required fields or incorrect primitive shapes.
Unknown fields remain available for additive extensions. Optional null fields
remain absent for compatibility. Domain modules still decide ranges, defaults,
alternative session selectors, permissions, generation validity and side effects.
This is a typed command/validated wire contract, not a claim that every dynamic
domain payload has been converted into a Dart or Rust struct.

To add a command, declare its owner and stable field shapes, regenerate outputs,
implement the dispatcher, and test its behavior through the owning module.
Declare `requiresVerifiedState` for operations that must wait for reconciliation;
the exact key/touch UP/CANCEL cleanup exception remains in state recovery.
