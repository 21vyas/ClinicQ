#!/usr/bin/env bash
set -euo pipefail

echo "[vercel-build] Starting Flutter web build"

# Validate required environment variables early with clear messages.
: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is required}"
: "${BASE_URL:?BASE_URL is required}"

echo "[vercel-build] Writing temporary .env for Flutter assets"
cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
BASE_URL=${BASE_URL}
EOF

if [ ! -d "flutter" ]; then
  echo "[vercel-build] Installing Flutter SDK"
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable flutter
fi

export PATH="$PWD/flutter/bin:$PATH"

flutter config --no-analytics
flutter --version

echo "[vercel-build] Resolving Dart/Flutter dependencies"
flutter pub get

echo "[vercel-build] Building web release"
flutter build web \
  --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=BASE_URL="$BASE_URL"

echo "[vercel-build] Build completed: build/web"