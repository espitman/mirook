#!/bin/bash

set -euo pipefail

READER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$READER_ROOT"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to run Mirook Reader."
  exit 1
fi

if [ ! -d node_modules ]; then
  echo "Installing Mirook Reader dependencies..."
  npm install --no-audit --no-fund
fi

if [ ! -f node_modules/electron/path.txt ]; then
  echo "Installing Electron runtime..."
  node node_modules/electron/install.js
fi

echo "Starting Mirook Reader..."
npm run run
