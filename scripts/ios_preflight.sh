#!/usr/bin/env bash
# scripts/ios_preflight.sh
# ─────────────────────────────────────────────────────────────────────────────
# One-command iOS preflight — patakbuhin sa macOS bago mag-test sa iPhone.
#
#   bash scripts/ios_preflight.sh
#
# Ginagawa (at hihinto sa unang fail):
#   1. flutter pub get
#   2. pod install (naka-pin sa iOS 15.5)
#   3. flutter test test/ios_platform_config_test.dart
#   4. flutter build ios --debug --no-codesign  (compile gate, walang signing)
#
# Kapag pumasa ito, compile-level na ok ang iOS. Ang device tests (push, maps,
# face verification, TestFlight) ay nasa docs/IOS_TEST_CHECKLIST.md.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: macOS + Xcode 15.3+ ang kailangan para mag-build ng iOS." >&2
  echo "       Kasalukuyang OS: $(uname -s). Sa Windows, ang static check lang ang kaya:" >&2
  echo "       flutter test test/ios_platform_config_test.dart" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

echo "==> Toolchain"
flutter --version
xcodebuild -version
pod --version

if [[ ! -f assets/env/.env ]]; then
  echo "error: wala ang assets/env/.env (git-ignored). Gumawa muna nito mula sa" >&2
  echo "       assets/env/.env.example, o kopyahin ang dev env file." >&2
  exit 1
fi

echo "==> flutter pub get"
flutter pub get

echo "==> pod install"
( cd ios && pod install )

echo "==> iOS config guard tests"
flutter test test/ios_platform_config_test.dart

echo "==> Compile gate (no codesign)"
flutter build ios --debug --no-codesign

echo
echo "OK — nagko-compile ang iOS app."
echo "Susunod: docs/IOS_TEST_CHECKLIST.md (device tests, push, TestFlight)."
