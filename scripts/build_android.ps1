# ============================================================
# 🤖 سكريبت بِناء Android APK + AAB
# ============================================================
# يُنَفِّذ كلّ الخَطوات اللازِمة لإنتاج ملفّ تَثبيت جاهِز.
#
# الاستِخدام:
#   .\scripts\build_android.ps1 [-Release|-Debug|-Bundle]
#
# مَثلاً:
#   .\scripts\build_android.ps1 -Release   ← APK للـsharing/testing
#   .\scripts\build_android.ps1 -Bundle    ← AAB للـPlay Store
#   .\scripts\build_android.ps1 -Debug     ← Debug APK سَريع
# ============================================================

param(
    [switch]$Release = $true,
    [switch]$Debug = $false,
    [switch]$Bundle = $false,
    [switch]$Clean = $false,
    [switch]$SkipChecks = $false
)

# الألوان
$ErrorActionPreference = "Stop"
function Write-Step { Write-Host "`n🔧 $args" -ForegroundColor Cyan }
function Write-OK   { Write-Host "✅ $args" -ForegroundColor Green }
function Write-Warn { Write-Host "⚠  $args" -ForegroundColor Yellow }
function Write-Err  { Write-Host "❌ $args" -ForegroundColor Red }

# الانتِقال إلى جَذر المَشروع
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   🚀 M7 Nexus — Android Build         ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Magenta

# ============================================================
# 1) فَحص الـenvironment
# ============================================================
if (-not $SkipChecks) {
    Write-Step "فَحص Flutter…"
    try {
        $flutterVer = flutter --version 2>&1 | Select-String -Pattern "Flutter \d+\.\d+"
        Write-OK "Flutter مُثَبَّت: $flutterVer"
    } catch {
        Write-Err "Flutter غَير مُثَبَّت أو غَير مَضاف للـPATH"
        Write-Host "نَزِّله من: https://flutter.dev/docs/get-started/install"
        exit 1
    }

    Write-Step "فَحص Android SDK…"
    flutter doctor --android-licenses 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Android SDK جاهِز"
    } else {
        Write-Warn "قَد تَحتاج لِقَبول تَراخيص Android"
    }
}

# ============================================================
# 2) Clean (اختياريّ)
# ============================================================
if ($Clean) {
    Write-Step "تَنظيف build السابِق…"
    flutter clean
    Write-OK "تَمّ التَنظيف"
}

# ============================================================
# 3) جَلب الـdependencies
# ============================================================
Write-Step "تَحميل dependencies…"
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Err "فَشِل pub get"; exit 1 }
Write-OK "تَمّ تَحميل الـdependencies"

# ============================================================
# 4) فَحص ملفّات Firebase
# ============================================================
$gsj = "android\app\google-services.json"
if (-not (Test-Path $gsj)) {
    Write-Warn "$gsj غَير مَوجود — Push Notifications لن تَعمَل"
    Write-Host "  نَزِّله من: Firebase Console → Project Settings → اخْتَر Android app"
    Write-Host "  يُمكِنكَ المُتابَعة بدونه — لكنّ FCM لن يَعمَل"
    $continue = Read-Host "  هل تُريد المُتابَعة؟ (y/N)"
    if ($continue -ne "y") { exit 0 }
} else {
    Write-OK "google-services.json مَوجود"
}

# ============================================================
# 5) البِناء
# ============================================================
$mode = if ($Debug) { "debug" } elseif ($Bundle) { "appbundle" } else { "apk" }

Write-Step "بِناء Android $mode…"
$buildArgs = @()
if ($mode -eq "apk") {
    $buildArgs = @("apk", "--release", "--split-per-abi")
} elseif ($mode -eq "appbundle") {
    $buildArgs = @("appbundle", "--release")
} else {
    $buildArgs = @("apk", "--debug")
}

flutter build @buildArgs

if ($LASTEXITCODE -ne 0) {
    Write-Err "فَشِل البِناء — اِفحَص الأَخطاء أعلاه"
    exit 1
}

# ============================================================
# 6) اعرِض المَخرجات
# ============================================================
Write-Step "نَتائج البِناء:"

if ($mode -eq "apk") {
    $apkDir = "build\app\outputs\flutter-apk"
    Get-ChildItem -Path $apkDir -Filter "*.apk" | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-OK "📱 $($_.Name)  ($sizeMB MB)"
        Write-Host "   $($_.FullName)" -ForegroundColor Gray
    }
} elseif ($mode -eq "appbundle") {
    $aabDir = "build\app\outputs\bundle\release"
    Get-ChildItem -Path $aabDir -Filter "*.aab" | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-OK "📦 $($_.Name)  ($sizeMB MB)"
        Write-Host "   $($_.FullName)" -ForegroundColor Gray
    }
} else {
    Get-ChildItem -Path "build\app\outputs\flutter-apk" -Filter "*.apk" |
        ForEach-Object { Write-OK "$($_.Name)" }
}

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   🎉 تَمّ البِناء بِنَجاح!              ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════╝`n" -ForegroundColor Green

if ($mode -eq "apk") {
    Write-Host "💡 خُطوات تالية:" -ForegroundColor Cyan
    Write-Host "  • انسَخ الـAPK لهاتفك واضغطه لتَثبيته"
    Write-Host "  • اِفتَح Settings → Security → فَعِّل 'Install from unknown sources'"
    Write-Host "  • للنَشر للـPlay Store، اِبنِ AAB:"
    Write-Host "      .\scripts\build_android.ps1 -Bundle" -ForegroundColor Gray
} elseif ($mode -eq "appbundle") {
    Write-Host "💡 لِلنَشر للـPlay Store:" -ForegroundColor Cyan
    Write-Host "  1. اِفتَح play.google.com/console"
    Write-Host "  2. Production → Create new release"
    Write-Host "  3. اِرفَع ملفّ .aab"
}
