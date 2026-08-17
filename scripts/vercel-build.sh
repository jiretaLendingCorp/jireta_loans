#!/bin/bash

set -e

echo "Installing Flutter..."

git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"

export PATH="$HOME/flutter/bin:$PATH"

flutter --version

flutter config --enable-web

flutter pub get

# Generate assets/env/.env from Vercel environment variables.
# assets/env/.env is git-ignored, so it must be created at build time.
mkdir -p assets/env
cat > assets/env/.env <<EOF
SUPABASE_URL=${SUPABASE_URL:-https://your-project.supabase.co}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-your-anon-key}
EDGE_FUNCTIONS_URL=${EDGE_FUNCTIONS_URL:-https://your-project.supabase.co/functions/v1}
GOOGLE_MAPS_API_KEY=${GOOGLE_MAPS_API_KEY:-your-google-maps-key}
XENDIT_PUBLIC_KEY=${XENDIT_PUBLIC_KEY:-xendit_public_xxx}
APP_ENV=${APP_ENV:-production}
EOF

flutter build web --release
