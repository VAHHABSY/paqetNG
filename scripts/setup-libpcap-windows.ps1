# Setup prebuilt libpcap for Android so Makefile.paqet can build tcpdump on Windows.
# Puts libpcap in build/android/libpcap/{arm64-v8a,armeabi-v7a} (same layout as build-libpcap-android.sh).
# Requires: git. Uses seladb/libpcap-android prebuilt libs.

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildAndroid = Join-Path $RepoRoot "build\android"
$LibpcapAndroid = Join-Path $RepoRoot "build\libpcap-android"

if (-not (Test-Path (Join-Path $LibpcapAndroid "include"))) {
    Write-Host "Fetching prebuilt libpcap for Android (seladb/libpcap-android)..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path (Split-Path $LibpcapAndroid) | Out-Null
    if (-not (Test-Path $LibpcapAndroid)) {
        git clone --depth 1 https://github.com/seladb/libpcap-android.git $LibpcapAndroid
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}

$abis = @("arm64-v8a", "armeabi-v7a")
foreach ($abi in $abis) {
    $srcLib = Join-Path $LibpcapAndroid "$abi\24\libpcap.a"
    if (-not (Test-Path $srcLib)) {
        Write-Error "Prebuilt libpcap not found at $srcLib. Clone build\libpcap-android and ensure $abi\24\libpcap.a exists."
    }
    $destDir = Join-Path $BuildAndroid "libpcap\$abi"
    $destLib = Join-Path $destDir "lib\libpcap.a"
    $destInclude = Join-Path $destDir "include"
    if (-not (Test-Path $destLib)) {
        New-Item -ItemType Directory -Force -Path (Join-Path $destDir "lib") | Out-Null
        Copy-Item -Force $srcLib $destLib
        Write-Host "Copied libpcap to $destLib" -ForegroundColor Green
    }
    if (-not (Test-Path $destInclude)) {
        $srcInclude = Join-Path $LibpcapAndroid "include"
        Copy-Item -Recurse -Force $srcInclude $destInclude
        Write-Host "Copied include to $destInclude" -ForegroundColor Green
    }
}
Write-Host "Prebuilt libpcap ready for tcpdump build." -ForegroundColor Green
