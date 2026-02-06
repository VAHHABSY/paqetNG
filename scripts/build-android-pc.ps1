# Build paqet (from paqet submodule) for Android on Windows.
# Run from paqetNG repo root. Requires: Go (CGO), Android NDK, git.
# Optional: ANDROID_NDK_HOME. If you pass SDK path (e.g. E:\SDK), NDK is auto-detected under ndk\<version>.

param(
    [string]$NdkPath = $env:ANDROID_NDK_HOME
)
if (-not $NdkPath) { $NdkPath = $env:ANDROID_NDK_ROOT }

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$PaqetSrc = Join-Path $RepoRoot "paqet"
if (-not (Test-Path (Join-Path $PaqetSrc "go.mod"))) {
    Write-Error "paqet submodule not found at $PaqetSrc. Run: git submodule update --init paqet"
}

# If user passed SDK root (e.g. E:\SDK), find NDK under ndk\
if ($NdkPath -and (Test-Path (Join-Path $NdkPath "ndk"))) {
    $ndkDir = Get-ChildItem -Path (Join-Path $NdkPath "ndk") -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($ndkDir) {
        $NdkPath = $ndkDir.FullName
        Write-Host "Using NDK: $NdkPath" -ForegroundColor Cyan
    }
}

$ndk = $NdkPath
if (-not $ndk) {
    Write-Host "ANDROID_NDK_HOME (or ANDROID_NDK_ROOT) is not set." -ForegroundColor Yellow
    Write-Host "Example: .\scripts\build-android-pc.ps1 -NdkPath E:\SDK"
    exit 1
}

$ndkBin = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin"
if (-not (Test-Path $ndkBin)) {
    Write-Host "NDK bin not found at: $ndkBin" -ForegroundColor Yellow
    exit 1
}

$buildDir = Join-Path $RepoRoot "build\android"
$libpcapDir = Join-Path $RepoRoot "build\libpcap-android"
$abi = "arm64-v8a"
$libpcapInclude = Join-Path $libpcapDir "include"
$libpcapLib = Join-Path $libpcapDir "$abi\24"

if (-not (Test-Path (Join-Path $libpcapLib "libpcap.a"))) {
    Write-Host "Fetching prebuilt libpcap for Android..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    if (-not (Test-Path $libpcapDir)) {
        git clone --depth 1 https://github.com/seladb/libpcap-android.git $libpcapDir
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
    if (-not (Test-Path (Join-Path $libpcapLib "libpcap.a"))) {
        Write-Host "Prebuilt libpcap not found at $libpcapLib\libpcap.a" -ForegroundColor Yellow
        exit 1
    }
}

$androidApi = "24"
$clang = Join-Path $ndkBin "aarch64-linux-android$androidApi-clang"
if (-not (Test-Path $clang)) {
    if (Test-Path "$clang.cmd") { $clang = "$clang.cmd" } else { $clang = "$clang.exe" }
}
if (-not (Test-Path $clang)) {
    Write-Host "NDK clang not found: $ndkBin\aarch64-linux-android$androidApi-clang" -ForegroundColor Yellow
    exit 1
}

$ndkSysroot = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\sysroot"
$ndkLib = Join-Path $ndkSysroot "usr\lib\aarch64-linux-android\$androidApi"
$env:CGO_ENABLED = "1"
$env:GOOS = "android"
$env:GOARCH = "arm64"
$env:CC = $clang
$env:CGO_CFLAGS = "-I$libpcapInclude --sysroot=$ndkSysroot"
$env:CGO_LDFLAGS = "-L$libpcapLib -L$ndkLib -lpcap -lc -llog"

$outBinary = Join-Path $buildDir "paqet_android_arm64"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Write-Host "Building paqet for android/arm64..." -ForegroundColor Cyan
Push-Location $PaqetSrc
try {
    go build -trimpath -ldflags "-extldflags '-Wl,-z,max-page-size=16384'" -o $outBinary ./cmd/main.go
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "Done. Binary: $outBinary" -ForegroundColor Green
} finally {
    Pop-Location
}
