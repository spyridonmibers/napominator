#!/usr/bin/env bash
# Генерирует папки android/ и ios/ стандартным `flutter create`
# и вносит нужные для уведомлений правки.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create . \
  --project-name napominator \
  --org ru.napominator \
  --platforms android,ios \
  --no-pub

python3 tool/patch_platforms.py

# Live Activity (Dynamic Island) — только на macOS, где есть Xcode и CocoaPods.
if [ "$(uname)" = "Darwin" ]; then
  ruby tool/ios_extra/add_live_activity.rb
fi
flutter pub get
echo "Готово: android/ и ios/ настроены."
