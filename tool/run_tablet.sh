#!/usr/bin/env bash
set -euo pipefail
# Explicit serial prevents installing on a second connected Android device.
serial="${1:?Usage: tool/run_tablet.sh DEVICE_SERIAL [DART_TARGET]}"
target="${2:-lib/main.dart}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/example"
flutter build apk --debug --target-platform android-arm64 --target "$target"
adb -s "$serial" install --no-streaming -t -r build/app/outputs/flutter-apk/app-debug.apk
adb -s "$serial" shell am force-stop dev.qruhf.qruhf_example
adb -s "$serial" shell am start -n dev.qruhf.qruhf_example/.MainActivity
