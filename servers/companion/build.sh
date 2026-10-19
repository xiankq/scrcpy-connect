#!/usr/bin/env bash
set -euo pipefail
exec dart "$(dirname "$0")/build.dart" "$@"
