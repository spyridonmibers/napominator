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
flutter pub get
echo "Готово: android/ и ios/ настроены."
