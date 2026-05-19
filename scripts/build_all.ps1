# ============================================================
# 🚀 بِناء كلّ النِسَخ دَفعةً واحِدة (Android APK + Web)
# ============================================================
# iOS لا يُمكِن بِناؤه على Windows — يَحتاج Mac.
#
# الاستِخدام:
#   .\scripts\build_all.ps1
#   .\scripts\build_all.ps1 -SkipWeb       ← Android فَقَط
#   .\scripts\build_all.ps1 -SkipAndroid   ← Web فَقَط
#   .\scripts\build_all.ps1 -Bundle        ← AAB بَدَلاً من APK
# ============================================================

param(
    [switch]$SkipAndroid = $false,
    [switch]$SkipWeb = $false,
    [switch]$Bundle = $false,
    [switch]$Clean = $false
)

$ErrorActionPreference = "Continue"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$startTime = Get-Date

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║   🚀 M7 Nexus — Build All             ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Magenta

$results = @()

# ============================================================
# Android
# ============================================================
if (-not $SkipAndroid) {
    Write-Host "`n📱 بِناء Android…" -ForegroundColor Yellow
    $androidArgs = @{}
    if ($Clean) { $androidArgs.Clean = $true }
    if ($Bundle) { $androidArgs.Bundle = $true }

    $androidScript = "$PSScriptRoot\build_android.ps1"
    & $androidScript @androidArgs
    if ($LASTEXITCODE -eq 0) {
        $results += @{ Platform = "Android"; Status = "✅" }
    } else {
        $results += @{ Platform = "Android"; Status = "❌" }
    }
}

# ============================================================
# Web
# ============================================================
if (-not $SkipWeb) {
    Write-Host "`n🌐 بِناء Web…" -ForegroundColor Yellow
    $webArgs = @{}
    if ($Clean) { $webArgs.Clean = $true }

    $webScript = "$PSScriptRoot\build_web.ps1"
    & $webScript @webArgs
    if ($LASTEXITCODE -eq 0) {
        $results += @{ Platform = "Web"; Status = "✅" }
    } else {
        $results += @{ Platform = "Web"; Status = "❌" }
    }
}

# ============================================================
# الملخَّص
# ============================================================
$elapsed = (Get-Date) - $startTime
$elapsedStr = "{0:mm}:{0:ss}" -f $elapsed

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   📊 ملخَّص البِناء                      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

foreach ($r in $results) {
    Write-Host "  $($r.Status) $($r.Platform)"
}

Write-Host "`n  ⏱  الوَقت الكُلّيّ: $elapsedStr" -ForegroundColor Gray

# للـiOS
Write-Host "`n💡 لِبِناء iOS تَحتاج Mac:" -ForegroundColor Cyan
Write-Host "   chmod +x scripts/build_ios.sh"
Write-Host "   ./scripts/build_ios.sh"

# عَرض المَخرجات
Write-Host "`n📦 المَخرجات:" -ForegroundColor Yellow

if (-not $SkipAndroid) {
    if ($Bundle) {
        $aab = "build\app\outputs\bundle\release\app-release.aab"
        if (Test-Path $aab) {
            $size = [math]::Round((Get-Item $aab).Length / 1MB, 2)
            Write-Host "   📦 Android AAB: $aab ($size MB)"
        }
    } else {
        $apkDir = "build\app\outputs\flutter-apk"
        if (Test-Path $apkDir) {
            Get-ChildItem -Path $apkDir -Filter "*.apk" | ForEach-Object {
                $size = [math]::Round($_.Length / 1MB, 2)
                Write-Host "   📱 Android APK: $($_.FullName) ($size MB)"
            }
        }
    }
}

if (-not $SkipWeb) {
    $webDir = "build\web"
    if (Test-Path $webDir) {
        Write-Host "   🌐 Web: $((Resolve-Path $webDir).Path)"
        $zips = Get-ChildItem -Path "build" -Filter "m7nexus_web_*.zip" -ErrorAction SilentlyContinue
        if ($zips) {
            $latestZip = $zips | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $zipSize = [math]::Round($latestZip.Length / 1MB, 2)
            Write-Host "   📦 Web ZIP:  $($latestZip.FullName) ($zipSize MB)"
        }
    }
}

Write-Host ""
