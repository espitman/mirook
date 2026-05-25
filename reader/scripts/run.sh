#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

exec "$READER_ROOT/run.sh"
