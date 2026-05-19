#!/bin/bash
# ============================================================
# 🍎 سكريبت بِناء iOS IPA
# ============================================================
# ⚠ يَتَطَلَّب جِهاز Mac + Xcode + حساب Apple Developer
#
# الاستِخدام:
#   chmod +x scripts/build_ios.sh
#   ./scripts/build_ios.sh
# ============================================================

set -e

# الألوان
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

step() { echo -e "\n${CYAN}🔧 $1${NC}"; }
ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠  $1${NC}"; }
err()  { echo -e "${RED}❌ $1${NC}"; }

cd "$(dirname "$0")/.."

echo -e "\n${MAGENTA}╔════════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║   🚀 M7 Nexus — iOS Build              ║${NC}"
echo -e "${MAGENTA}╚════════════════════════════════════════╝${NC}"

# ============================================================
# 1) فَحص النِظام
# ============================================================
if [[ "$OSTYPE" != "darwin"* ]]; then
  err "بِناء iOS يَحتاج macOS — أَنتَ على $OSTYPE"
  exit 1
fi
ok "macOS — جاهِز"

step "فَحص Flutter…"
if ! command -v flutter &> /dev/null; then
  err "Flutter غَير مُثَبَّت"
  echo "نَزِّله من: https://flutter.dev/docs/get-started/install/macos"
  exit 1
fi
flutter --version | head -1
ok "Flutter مُثَبَّت"

step "فَحص Xcode…"
if ! command -v xcodebuild &> /dev/null; then
  err "Xcode غَير مُثَبَّت"
  echo "ثَبِّته من Mac App Store"
  exit 1
fi
ok "Xcode: $(xcodebuild -version | head -1)"

step "فَحص CocoaPods…"
if ! command -v pod &> /dev/null; then
  warn "CocoaPods غَير مُثَبَّت — سأُثَبِّته"
  sudo gem install cocoapods
fi
ok "CocoaPods: $(pod --version)"

# ============================================================
# 2) فَحص ملفّات Firebase
# ============================================================
GSI="ios/Runner/GoogleService-Info.plist"
if [ ! -f "$GSI" ]; then
  warn "$GSI غَير مَوجود — Push Notifications لن تَعمَل"
  echo "  نَزِّله من: Firebase Console → اخْتَر iOS app"
  read -p "  هل تُريد المُتابَعة؟ (y/N): " cont
  [[ "$cont" != "y" ]] && exit 0
else
  ok "GoogleService-Info.plist مَوجود"
fi

# ============================================================
# 3) Clean + Pub Get
# ============================================================
step "تَنظيف build السابِق…"
flutter clean
ok "تَمّ التَنظيف"

step "تَحميل dependencies…"
flutter pub get
ok "تَمّ"

step "تَحديث CocoaPods…"
cd ios
pod install --repo-update
cd ..
ok "تَمّ"

# ============================================================
# 4) البِناء
# ============================================================
step "بِناء iOS Release…"

# ابنِ بدون codesign أَوَّلاً (لِلسُرعة + اختبار)
flutter build ios --release --no-codesign

if [ $? -ne 0 ]; then
  err "فَشِل البِناء"
  exit 1
fi

ok "build/ios/iphoneos/Runner.app جاهِز"

# ============================================================
# 5) إنشاء IPA (يَحتاج توقيع)
# ============================================================
step "إنشاء IPA (يَحتاج Provisioning Profile)…"
echo ""
echo -e "${YELLOW}للحصول على IPA يَجِب:${NC}"
echo -e "  1. اِفتَح ${CYAN}ios/Runner.xcworkspace${NC} في Xcode"
echo -e "  2. اخْتَر Runner target → Signing & Capabilities"
echo -e "  3. اخْتَر Team (Apple Developer)"
echo -e "  4. تَأكَّد من Bundle ID: ${CYAN}com.m7nexus.m7md_ops${NC}"
echo -e "  5. ${CYAN}Product → Archive${NC}"
echo -e "  6. ${CYAN}Distribute App → App Store Connect${NC} (للنَشر)"
echo -e "     أو ${CYAN}Ad Hoc${NC} (لِلتَوزيع المُحَدَّد)"
echo ""

read -p "هل تُريد فَتح Xcode الآن؟ (y/N): " openXcode
if [[ "$openXcode" == "y" ]]; then
  open ios/Runner.xcworkspace
fi

# ============================================================
# 6) IPA بِسطر أوامِر (إذا كان لَدَيكَ ExportOptions.plist)
# ============================================================
if [ -f "ios/ExportOptions.plist" ]; then
  step "تَوليد IPA تلقائيّاً…"
  flutter build ipa --release \
    --export-options-plist=ios/ExportOptions.plist
  if [ -f "build/ios/ipa/m7md_ops.ipa" ]; then
    SIZE=$(du -h build/ios/ipa/m7md_ops.ipa | cut -f1)
    ok "IPA جاهِز: build/ios/ipa/m7md_ops.ipa ($SIZE)"
  fi
else
  warn "ios/ExportOptions.plist غَير مَوجود — IPA يَدويّ من Xcode فَقَط"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🎉 تَمّ البِناء بِنَجاح!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
