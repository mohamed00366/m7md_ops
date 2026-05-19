# ============================================================
# 🌐 سكريبت بِناء Web Production
# ============================================================
# يُنشِئ مُجَلَّد build/web جاهِز للنَشر على:
#   - Netlify / Vercel / Cloudflare Pages (مَجّانيّ)
#   - Firebase Hosting (مَجّانيّ)
#   - Apache / Nginx على VPS
#   - أيّ static hosting
#
# الاستِخدام:
#   .\scripts\build_web.ps1 [-Renderer html|canvaskit] [-BaseHref /path/]
#
# مَثلاً:
#   .\scripts\build_web.ps1                     ← canvaskit (افتراضيّ)
#   .\scripts\build_web.ps1 -Renderer html      ← html (أَخَفّ، أَبسَط)
#   .\scripts\build_web.ps1 -BaseHref /m7/      ← لو في sub-path
# ============================================================

param(
    [ValidateSet("html", "canvaskit", "auto")]
    [string]$Renderer = "auto",
    [string]$BaseHref = "/",
    [switch]$Clean = $false,
    [switch]$Optimize = $true
)

$ErrorActionPreference = "Stop"
function Write-Step { Write-Host "`n🔧 $args" -ForegroundColor Cyan }
function Write-OK   { Write-Host "✅ $args" -ForegroundColor Green }
function Write-Warn { Write-Host "⚠  $args" -ForegroundColor Yellow }
function Write-Err  { Write-Host "❌ $args" -ForegroundColor Red }

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   🚀 M7 Nexus — Web Build             ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Magenta

# ============================================================
# 1) Flutter check
# ============================================================
Write-Step "فَحص Flutter Web…"
flutter config --enable-web 2>&1 | Out-Null
$webEnabled = flutter config 2>&1 | Select-String -Pattern "enable-web: true"
if (-not $webEnabled) {
    Write-Err "Web غَير مُفَعَّل في Flutter"
    Write-Host "  flutter config --enable-web"
    exit 1
}
Write-OK "Flutter Web جاهِز"

# ============================================================
# 2) Clean
# ============================================================
if ($Clean) {
    Write-Step "تَنظيف…"
    flutter clean
    Write-OK "تَمّ"
}

# ============================================================
# 3) Pub get
# ============================================================
Write-Step "تَحميل dependencies…"
flutter pub get
if ($LASTEXITCODE -ne 0) { Write-Err "فَشِل pub get"; exit 1 }
Write-OK "تَمّ"

# ============================================================
# 4) البِناء
# ============================================================
Write-Step "بِناء Web (renderer=$Renderer, base-href=$BaseHref)…"

$buildArgs = @("build", "web", "--release")
$buildArgs += "--web-renderer=$Renderer"
$buildArgs += "--base-href=$BaseHref"

# تَفعيل tree-shaking للأَيقونات + minify
if ($Optimize) {
    $buildArgs += "--tree-shake-icons"
    $buildArgs += "--source-maps"  # يُساعِد لو فيه أخطاء بَعد النَشر
}

flutter @buildArgs

if ($LASTEXITCODE -ne 0) {
    Write-Err "فَشِل البِناء"
    exit 1
}

# ============================================================
# 5) عَرض النَتائج
# ============================================================
$webDir = "build\web"
$totalSize = (Get-ChildItem -Path $webDir -Recurse | Measure-Object -Property Length -Sum).Sum
$totalMB = [math]::Round($totalSize / 1MB, 2)
$fileCount = (Get-ChildItem -Path $webDir -Recurse -File).Count

Write-Step "نَتائج البِناء:"
Write-OK "📁 المُجَلَّد: $((Resolve-Path $webDir).Path)"
Write-OK "💾 الحَجم الكامِل: $totalMB MB"
Write-OK "📄 عَدد الملفّات: $fileCount"

# الملفّات الأَكبَر
Write-Host "`n  أَكبَر 5 ملفّات:" -ForegroundColor Gray
Get-ChildItem -Path $webDir -Recurse -File |
    Sort-Object Length -Descending |
    Select-Object -First 5 |
    ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1MB, 2)
        Write-Host "    $sizeMB MB  $($_.Name)" -ForegroundColor Gray
    }

# ============================================================
# 6) خُطوات النَشر
# ============================================================
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   🎉 تَمّ البِناء بِنَجاح!              ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════╝`n" -ForegroundColor Green

Write-Host "💡 خَيارات النَشر:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  📌 1. اختبار محلّيّ (سَريع):" -ForegroundColor Yellow
Write-Host "     cd $webDir"
Write-Host "     python -m http.server 8000"
Write-Host "     ثمّ افتح http://localhost:8000"
Write-Host ""
Write-Host "  📌 2. Firebase Hosting (مَجّانيّ):" -ForegroundColor Yellow
Write-Host "     firebase init hosting"
Write-Host "     firebase deploy --only hosting"
Write-Host ""
Write-Host "  📌 3. Netlify (drag & drop):" -ForegroundColor Yellow
Write-Host "     اِفتَح netlify.com → اِسحَب مُجَلَّد build/web"
Write-Host ""
Write-Host "  📌 4. Vercel (CLI):" -ForegroundColor Yellow
Write-Host "     npx vercel build/web --prod"
Write-Host ""
Write-Host "  📌 5. Cloudflare Pages:" -ForegroundColor Yellow
Write-Host "     wrangler pages deploy build/web"
Write-Host ""
Write-Host "  📌 6. VPS (Apache/Nginx):" -ForegroundColor Yellow
Write-Host "     scp -r build/web/* user@server:/var/www/html/"
Write-Host ""

# ============================================================
# 7) إنشاء zip للسُهولة
# ============================================================
$zipPath = "build\m7nexus_web_$(Get-Date -Format 'yyyy-MM-dd_HHmm').zip"
Write-Step "إنشاء ملفّ ZIP لِلْتَوزيع…"
Compress-Archive -Path "$webDir\*" -DestinationPath $zipPath -Force
$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-OK "📦 $zipPath  ($zipSize MB)"
Write-Host ""
