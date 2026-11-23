# SAMENI VPN - one-click setup + build + install (Windows 10/11)
$ErrorActionPreference = 'Continue'
trap {
    Write-Host "`nUNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    Read-Host 'Press Enter to exit'
    exit 1
}
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Set-Location -Path $PSScriptRoot
try { Start-Transcript -Path (Join-Path $PSScriptRoot 'setup_log.txt') -Force | Out-Null } catch {}

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Has($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function RefreshPath {
    $m = [Environment]::GetEnvironmentVariable('Path','Machine')
    $u = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = "$m;$u;C:\src\flutter\bin"
}
function Fail($m) { Write-Host "`nERROR: $m" -ForegroundColor Red; Read-Host 'Press Enter to exit'; exit 1 }

if (-not (Test-Path 'pubspec.yaml')) { Fail 'Run this file from inside the SAMENI_VPN project folder (pubspec.yaml not found).' }
RefreshPath

# ---------- 1) Git + JDK via winget ----------
Step '1/6 Git and JDK 17'
if (-not (Has 'winget')) { Fail 'winget not found. Update "App Installer" from Microsoft Store, or install Git and JDK 17 manually, then run again.' }
if (-not (Has 'git')) {
    winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements
    RefreshPath
}
if (-not (Has 'git')) { Fail 'Git installed but not visible yet. Close this window, open a new one and run again.' }
if (-not (Has 'java') -and -not $env:JAVA_HOME) {
    winget install -e --id EclipseAdoptium.Temurin.17.JDK --accept-source-agreements --accept-package-agreements
    RefreshPath
}
if (-not $env:JAVA_HOME) {
    $jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jdk) { $env:JAVA_HOME = $jdk.FullName }
}
if ($env:JAVA_HOME) { $env:Path = "$env:JAVA_HOME\bin;$env:Path" }

# ---------- 2) Flutter ----------
Step '2/6 Flutter SDK'
if (-not (Test-Path 'C:\src\flutter\bin\flutter.bat')) {
    New-Item -ItemType Directory -Force -Path 'C:\src' | Out-Null
    git clone -b stable --depth 1 https://github.com/flutter/flutter.git C:\src\flutter
}
RefreshPath
if (-not (Has 'flutter')) { Fail 'Flutter not found after clone.' }

# ---------- 3) Android SDK ----------
Step '3/6 Android SDK'
function IsSdk($d) { return $d -and (Test-Path $d) -and ((Test-Path "$d\platforms") -or (Test-Path "$d\platform-tools") -or (Test-Path "$d\cmdline-tools") -or (Test-Path "$d\build-tools")) }
$sdk = $null
$cands = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk", "$env:USERPROFILE\AppData\Local\Android\Sdk")
foreach ($d in 'C','D','E','F') { $cands += "${d}:\Android\Sdk"; $cands += "${d}:\Android\sdk"; $cands += "${d}:\Sdk"; $cands += "${d}:\android-sdk"; $cands += "${d}:\AndroidSDK" }
foreach ($c in $cands) { if (IsSdk $c) { $sdk = $c; break } }
if (-not $sdk) {
    # No valid SDK found (the old "Android SDK Tools 26.1.1" is ignored on purpose): install a fresh one.
    if (Test-Path 'D:\') { $sdk = 'D:\AndroidSDK' } else { $sdk = "$env:LOCALAPPDATA\Android\Sdk" }
    Write-Host "No valid Android SDK found. A fresh SDK will be installed in: $sdk" -ForegroundColor Yellow
}
Write-Host "Using Android SDK: $sdk"
$sdkmgr = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $sdkmgr)) {
    $alt = Get-ChildItem "$sdk\cmdline-tools" -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path "$($_.FullName)\bin\sdkmanager.bat" } | Select-Object -First 1
    if ($alt) { $sdkmgr = "$($alt.FullName)\bin\sdkmanager.bat" }
}
if (-not (Test-Path $sdkmgr)) {
    New-Item -ItemType Directory -Force -Path $sdk | Out-Null
    $zip = "$env:TEMP\cmdline-tools.zip"
    Write-Host 'Downloading Android command-line tools (about 150 MB)...'
    $urls = @(
        'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip',
        'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip',
        'https://dl.google.com/android/repository/commandlinetools-win-9477386_latest.zip'
    )
    $ok = $false
    foreach ($url in $urls) {
        if ($ok) { break }
        for ($i = 1; $i -le 2 -and -not $ok; $i++) {
            try {
                if (Test-Path $zip) { Remove-Item $zip -Force }
                Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
                $ok = (Test-Path $zip) -and ((Get-Item $zip).Length -gt 50MB)
                if ($ok) { Write-Host "Downloaded: $url" -ForegroundColor Green }
            } catch {
                Write-Host "Failed ($url): $($_.Exception.Message)" -ForegroundColor Yellow
                if ($_.Exception.Message -match '404') { break }
            }
        }
    }
    if (-not $ok) {
        Fail "Could not download Android command-line tools.`nOption 1: turn ON VPN and run again.`nOption 2 (no download): open Android Studio > Settings > Languages & Frameworks > Android SDK > SDK Tools tab > tick 'Android SDK Command-line Tools (latest)' > Apply. Then run this script again."
    }
    $tmp = "$env:TEMP\cmdline-extract"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Force -Path "$sdk\cmdline-tools" | Out-Null
    if (Test-Path "$sdk\cmdline-tools\latest") { Remove-Item "$sdk\cmdline-tools\latest" -Recurse -Force }
    Move-Item "$tmp\cmdline-tools" "$sdk\cmdline-tools\latest"
}
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
Write-Host 'Accepting licenses and installing SDK packages (this can take several minutes)...'
(1..60 | ForEach-Object { 'y' }) | & $sdkmgr --licenses --sdk_root=$sdk | Out-Null
& $sdkmgr --sdk_root=$sdk 'platform-tools' 'platforms;android-35' 'platforms;android-36' 'build-tools;35.0.0' 'build-tools;36.0.0'
if ($LASTEXITCODE -ne 0) { Fail 'Android SDK install failed. Check your internet / VPN and run again.' }

# ---------- 4) Flutter config ----------
Step '4/6 Flutter configuration'
flutter config --android-sdk $sdk
(1..60 | ForEach-Object { 'y' }) | flutter doctor --android-licenses | Out-Null

# ---------- 5) Prepare Android host + Build ----------
Step '5/6 Preparing Android Gradle wrapper and Achaemenid launcher'
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'prepare_android.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'Android host setup failed.' }

Step 'Building APK'
flutter pub get
if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get failed.' }
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { Fail 'Build failed. Copy the error text above and send it to Claude.' }

$outDir = Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk'
$apk = Join-Path $outDir 'app-arm64-v8a-release.apk'
$dest = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SAMENI_VPN.apk'
Copy-Item $apk $dest -Force
Write-Host "`nAPK saved to Desktop: $dest" -ForegroundColor Green

# ---------- 6) Install on phone (optional) ----------
Step '6/6 Install on phone'
$adb = "$sdk\platform-tools\adb.exe"
& $adb start-server | Out-Null
$devs = (& $adb devices) | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' }
if ($devs) {
    & $adb install -r $apk
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'arm64 install failed, trying armv7...' -ForegroundColor Yellow
        & $adb install -r (Join-Path $outDir 'app-armeabi-v7a-release.apk')
    }
} else {
    Write-Host 'No phone detected over USB.' -ForegroundColor Yellow
    Write-Host 'Option A: copy SAMENI_VPN.apk from Desktop to the phone and tap it to install.'
    Write-Host 'Option B: enable Developer options > USB debugging, connect the phone, run this script again.'
}
Read-Host "`nDone. Press Enter to exit"
