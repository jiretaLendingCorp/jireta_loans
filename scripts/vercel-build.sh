#!/bin/bash

set -e

echo "Installing Flutter..."

git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"

export PATH="$HOME/flutter/bin:$PATH"

flutter --version

flutter config --enable-web

flutter pub get

# ── Generate assets/env/.env from Vercel environment variables ───────────────
# assets/env/.env is git-ignored, so it must be created at build time.
# REFACTORED Aug 2026 for jireta.vercel.app:
# - Derive EDGE_FUNCTIONS_URL from SUPABASE_URL if not explicitly set.
# - Loudly warn when placeholder values are used (the OLD script silently wrote
#   your-project.supabase.co → the app then always reported "No Internet"
#   because the connectivity probe's DNS lookup failed).
# - Echo masked values so Vercel deployment logs make debugging obvious.
mkdir -p assets/env

# Prefer explicit EDGE_FUNCTIONS_URL, otherwise derive from SUPABASE_URL.
if [ -z "${EDGE_FUNCTIONS_URL:-}" ] && [ -n "${SUPABASE_URL:-}" ]; then
  DERIVED_EDGE="${SUPABASE_URL%/}/functions/v1"
else
  DERIVED_EDGE="${EDGE_FUNCTIONS_URL:-}"
fi

SUPABASE_URL_EFFECTIVE="${SUPABASE_URL:-https://your-project.supabase.co}"
EDGE_FUNCTIONS_URL_EFFECTIVE="${DERIVED_EDGE:-https://your-project.supabase.co/functions/v1}"

# Masked log — shows whether real env vars were injected without leaking secrets.
mask() { local v="$1"; if [ ${#v} -gt 24 ]; then echo "${v:0:24}..."; else echo "$v"; fi; }
echo "Env check (masked):"
echo "  SUPABASE_URL: $(mask "$SUPABASE_URL_EFFECTIVE")"
echo "  EDGE_FUNCTIONS_URL: $(mask "$EDGE_FUNCTIONS_URL_EFFECTIVE")"
echo "  SUPABASE_ANON_KEY: $(mask "${SUPABASE_ANON_KEY:-your-anon-key}")"
echo "  APP_ENV: ${APP_ENV:-production}"
if [ -n "${CORS_ALLOWED_ORIGINS:-}" ]; then
  echo "  CORS_ALLOWED_ORIGINS: $CORS_ALLOWED_ORIGINS"
else
  echo "  CORS_ALLOWED_ORIGINS: (not set — will default to * in dev)"
fi

if [[ "$SUPABASE_URL_EFFECTIVE" == *"your-project.supabase.co"* ]]; then
  echo "🚨 CRITICAL: SUPABASE_URL is still the placeholder 'your-project.supabase.co'."
  echo "   Set SUPABASE_URL in Vercel → Project Settings → Environment Variables (Production),"
  echo "   then trigger a Redeploy (Vercel → Deployments → ••• → Redeploy)."
  echo "   Without this the production app will always fail with:"
  echo "     ERR_NAME_NOT_RESOLVED your-project.supabase.co/functions/v1/auth-login"
  echo "     → 'Cannot connect to server' on every login/register call."
  if [ "${APP_ENV:-production}" = "production" ]; then
    echo "   Failing build to prevent deploying a broken production build."
    echo "   Fix: Vercel Dashboard → jireta → Settings → Environment Variables → Add (copy from Supabase Dashboard → Settings → API):"
    echo "     SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co"
    echo "     SUPABASE_ANON_KEY=eyJ... (Publishable key)"
    echo "     EDGE_FUNCTIONS_URL=https://YOUR_PROJECT_REF.supabase.co/functions/v1"
    echo "   Then Redeploy."
    exit 1
  fi
fi

# Also warn if new origin jireta.vercel.app is not in CORS_ALLOWED_ORIGINS
if [ -n "${CORS_ALLOWED_ORIGINS:-}" ]; then
  if [[ "$CORS_ALLOWED_ORIGINS" != *"jireta.vercel.app"* ]]; then
    echo "⚠️  WARNING: CORS_ALLOWED_ORIGINS does not contain jireta.vercel.app"
    echo "   Edge Functions will return Access-Control-Allow-Origin: null for that origin,"
    echo "   causing Dio to throw and the app to show 'No Internet Connection' even when online."
    echo "   Fix: supabase secrets set CORS_ALLOWED_ORIGINS=https://jireta.vercel.app,https://lending-jet-five.vercel.app,https://app.jiretaloanscorp.com"
  fi
fi

cat > assets/env/.env <<EOF
SUPABASE_URL=${SUPABASE_URL_EFFECTIVE}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-your-anon-key}
EDGE_FUNCTIONS_URL=${EDGE_FUNCTIONS_URL_EFFECTIVE}
GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY:-your-google-maps-key}
XENDIT_PUBLIC_KEY=${XENDIT_PUBLIC_KEY:-xendit_public_xxx}
APP_ENV=${APP_ENV:-production}
EOF

echo "Generated assets/env/.env:"
cat assets/env/.env | sed -E 's/(SUPABASE_ANON_KEY=).*/\1***/; s/(XENDIT_PUBLIC_KEY=).*/\1***/'

# Inject the Google Maps key into web/index.html (google_maps_flutter_web
# requires the JS API script tag or the map throws a red error box).
# Keys are alphanumeric + - _, safe for sed replacement.
if [ -n "${GOOGLE_MAPS_API_KEY:-}" ]; then
  sed -i "s/YOUR_GOOGLE_MAPS_API_KEY/${GOOGLE_MAPS_API_KEY}/g" web/index.html || true
  echo "Injected GOOGLE_MAPS_API_KEY into web/index.html"
else
  echo "WARNING: GOOGLE_MAPS_API_KEY not set — web map will use placeholder key"
fi

# ── APK download ("Download APK" button sa web login page) ───────────────────
# Naka-host ang release APK (~141 MB) sa GitHub Releases ng repo, hindi sa
# `web/downloads/`:
#   https://github.com/jiretaLendingCorp/jireta_loans/releases/latest/download/jireta-loans.apk
# Hindi ito ma-commit dahil lampas sa 100 MB na file limit ng GitHub, at hindi
# rin ma-upload sa Supabase Storage free plan (50 MB na file limit).
#
# Ang default URL ay nasa lib/core/config/app_config.dart. Kapag may custom na
# host/CDN, i-set ang APK_DOWNLOAD_URL sa Vercel env vars — build-time constant
# ang String.fromEnvironment, kaya kailangang ipasa dito sa --dart-define.
if [ -n "${APK_DOWNLOAD_URL:-}" ]; then
  echo "APK_DOWNLOAD_URL (custom): $APK_DOWNLOAD_URL"
  flutter build web --release --dart-define=APK_DOWNLOAD_URL="$APK_DOWNLOAD_URL"
else
  echo "APK_DOWNLOAD_URL: (default) GitHub Releases — releases/latest/download/jireta-loans.apk"
  flutter build web --release
fi
