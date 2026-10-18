# DESIGN.md → Flutter tokens

`generate.mjs` uses the official `@google/design.md/linter` API at the locked
version 0.4.0. The official parsed model is the only token input; no YAML parser,
second token file, or hand-maintained token values are used. The upstream CLI
does not export Dart, and its DTCG exporter omits component tokens, so this tool
only supplies the Dart emitter.

From the repository root (Node 18+ and the workspace Dart SDK must be on PATH):

```sh
npm ci --ignore-scripts --prefix tool/design_tokens
node tool/design_tokens/generate.mjs
node tool/design_tokens/generate.mjs --check
npm test --prefix tool/design_tokens
npm run lint --prefix tool/design_tokens
```

Edit `designs/design.md`, then regenerate. Commit the generated Dart file and
the npm lockfile. `--check` regenerates and formats in memory, compares exact
bytes, and fails without writing source files when output is missing or stale.

The emitter supports colors including alpha, typography, spacing, rounding,
and the explicit component property set in `generate.mjs`. Unknown keys,
properties, unresolved tokens, unsupported units, missing typography fields,
and missing constants consumed by `design_system.dart` fail generation.
DESIGN.md `px` maps to Flutter logical pixels; other CSS units need an explicit
future mapping. Unitless line heights must be quoted strings because the
official 0.4.0 parser silently ignores YAML numeric line heights. Numeric
spacing is rejected for the same reason.

The generated font-family metadata remains available, while Flutter's theme
uses the platform Chinese system font as required by the specification's
Typography section. All rendered font sizes, weights, line heights, and
tracking come from generated constants.

Official lint warnings remain visible: project optical/layout extensions are
accepted by the explicit emitter contract, and official orphan-color checks
only inspect DESIGN.md components rather than Flutter theme references.
