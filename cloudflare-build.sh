#!/usr/bin/env bash
# =============================================================================
# 🌐 Cloudflare Pages Build Script for Flutter Web
# =============================================================================
# هذا السكريبت يَعمَل عَلى Cloudflare Pages قَبل البِناء.
# يَقوم بِـ:
#   1. تَنزيل Flutter SDK
#   2. إضافَتها لِلـ PATH
#   3. تَنفيذ flutter pub get
#   4. بِناء النُسخة الإنتاجيّة لِلويب
#
# في إعدادات Cloudflare Pages → Build command:
#   bash cloudflare-build.sh
#
# Build output directory:
#   build/web
# =============================================================================

set -e

# الإصدار المُثَبَّت — يُطابِق المَحَلِّيّ + pubspec.lock (Flutter 3.29.x)
# ملاحظة: pubspec.lock مُولَّد على 3.29؛ استخدام 3.24.5 يُفشِل flutter pub get.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.29.2}"
FLUTTER_HOME="$HOME/flutter"

echo "🚀 Cloudflare Pages — Flutter Web Build"
echo "Flutter version: $FLUTTER_VERSION"

# تَنزيل Flutter إن لَم يَكُن مَوجوداً (Cloudflare يَستَخدِم cache)
if [ ! -d "$FLUTTER_HOME" ]; then
  echo "📥 Downloading Flutter $FLUTTER_VERSION..."
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi

# إضافَة Flutter لِلـ PATH
export PATH="$FLUTTER_HOME/bin:$PATH"

# تَحَقُّق
echo "✅ Flutter info:"
flutter --version

# التَجَنُّب: لا تُنَفِّذ analyze (نَحنُ نَبني فَقَط)
echo "📦 flutter pub get..."
flutter pub get

# بِناء الإصدار النِهائيّ
# ملاحظة: --base-href="/" لأَنّ الدومين الجَذر هو ذو القيمة
echo "🏗️ Building web release..."
flutter build web \
  --release \
  --pwa-strategy=offline-first

echo "✅ Build complete!"
echo "Output: build/web"
ls -lh build/web/ | head -10
