#!/usr/bin/env bash
# Builds the Flutter Web frontend on Vercel (static output in build/web).
# The backend stays on Render; the app calls it directly.
#   install: download the pinned Flutter SDK and fetch Dart packages
#   build:   flutter build web
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.6}"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter-sdk}"
API_BASE_URL="https://ro-mobileapp.onrender.com/api/"
export PATH="$FLUTTER_HOME/bin:$PATH"

install() {
  if ! command -v unzip >/dev/null 2>&1; then
    dnf install -y unzip >/dev/null 2>&1 || yum install -y unzip >/dev/null 2>&1 || true
  fi
  if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  fi
  flutter config --no-analytics --enable-web >/dev/null
  flutter --version
  flutter pub get
}

build() {
  flutter build web --release --base-href / \
    --dart-define=API_BASE_URL="$API_BASE_URL"
}

case "${1:-}" in
  install) install ;;
  build) build ;;
  *) install; build ;;
esac
