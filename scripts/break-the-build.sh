#!/usr/bin/env bash
# Toggles base-image.env between a deliberately outdated Python base
# image (Debian Buster, EOL — trips the Xray Critical/High gate) and a
# current, low-CVE-surface one. Run it, commit, push — that's the live
# "blocked gate" demo moment.
#
# PATCHED is Alpine, not a current Debian tag (e.g. 3.11-slim-bookworm).
# Found live: even an actively-patched Debian image realistically still
# carries some outstanding Critical/High CVEs in its large OS package
# set — Debian's patch cadence means there's rarely a moment where zero
# are outstanding. Alpine's much smaller package surface (musl/busybox)
# gives a genuinely achievable clean pass.
set -euo pipefail

ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/base-image.env"
VULNERABLE="3.9-slim-buster"
PATCHED="3.11-alpine"

current="$(grep -oP '(?<=PYTHON_VERSION=).*' "$ENV_FILE")"

if [[ "$current" == "$VULNERABLE" ]]; then
  echo "PYTHON_VERSION=$PATCHED" > "$ENV_FILE"
  echo "Switched to patched base image: $PATCHED"
  echo "Expect: Xray gate passes."
else
  echo "PYTHON_VERSION=$VULNERABLE" > "$ENV_FILE"
  echo "Switched to vulnerable base image: $VULNERABLE"
  echo "Expect: Xray gate blocks the build."
fi
