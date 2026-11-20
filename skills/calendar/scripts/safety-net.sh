#!/bin/bash
# Daily safety net on the controller for the worker's 30-minute calendar-mirror timer.
# Runs the same idempotent sync, so when the worker is down for a day, anything added to
# Apple Calendar by hand still reaches the team. A run with no changes is a no-op.
# Schedule it with your controller's automation runner (launchd), once a day.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
exec uv run --quiet --script mirror.py sync
