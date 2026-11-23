$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter پیدا نشد. ابتدا Flutter SDK را نصب و به PATH اضافه کنید.'
}
$temp = Join-Path $env:TEMP ('sameni-android-' + [guid]::NewGuid().ToString('N'))
try {
    Write-Host 'ساخت پوشه Android استاندارد با Flutter...' -ForegroundColor Cyan
    flutter create --no-pub --platforms=android --org com.sameni --project-name vpn $temp
    if ($LASTEXITCODE -ne 0) { throw 'flutter create ناموفق بود.' }
    if (Test-Path (Join-Path $root 'android')) {
        Remove-Item (Join-Path $root 'android') -Recurse -Force
    }
    Copy-Item (Join-Path $temp 'android') (Join-Path $root 'android') -Recurse -Force
} finally {
    if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
}
$res = Join-Path $root 'android\app\src\main\res'
$anydpi = Join-Path $res 'mipmap-anydpi-v26'
if (Test-Path $anydpi) { Remove-Item $anydpi -Recurse -Force }
Get-ChildItem (Join-Path $root 'launcher_icons') -Directory -Filter 'mipmap-*' | ForEach-Object {
    $dest = Join-Path $res $_.Name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $_.FullName $dest -Recurse -Force
}
$manifestPath = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
$xml = [IO.File]::ReadAllText($manifestPath)
$xml = [regex]::Replace($xml, 'android:label="[^"]*"', 'android:label="SAMENI VPN"')
$xml = [regex]::Replace($xml, 'android:icon="[^"]*"', 'android:icon="@mipmap/ic_launcher"')
if ($xml -match 'android:roundIcon=') {
    $xml = [regex]::Replace($xml, 'android:roundIcon="[^"]*"', 'android:roundIcon="@mipmap/ic_launcher_round"')
} else {
    $xml = $xml.Replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@mipmap/ic_launcher" android:roundIcon="@mipmap/ic_launcher_round"')
}
if ($xml -notmatch 'android:usesCleartextTraffic=') { $xml = $xml.Replace('<application', '<application android:usesCleartextTraffic="false"') }
foreach ($permission in @('android.permission.INTERNET','android.permission.ACCESS_NETWORK_STATE','android.permission.POST_NOTIFICATIONS')) {
    if ($xml -notmatch [regex]::Escape($permission)) {
        $xml = $xml.Replace('    <application', "    <uses-permission android:name=`"$permission`" />`r`n    <application")
    }
}
[IO.File]::WriteAllText($manifestPath, $xml, (New-Object System.Text.UTF8Encoding $false))
$gradlePath = Join-Path $root 'android\app\build.gradle.kts'
if (-not (Test-Path $gradlePath)) { $gradlePath = Join-Path $root 'android\app\build.gradle' }
$g = [IO.File]::ReadAllText($gradlePath)
$g = [regex]::Replace($g, 'namespace\s*=\s*"[^"]+"', 'namespace = "com.sameni.vpn"')
$g = [regex]::Replace($g, 'applicationId\s*=\s*"[^"]+"', 'applicationId = "com.sameni.vpn"')
if ($gradlePath.EndsWith('.kts')) {
    $g = [regex]::Replace($g, 'minSdk\s*=\s*[^\r\n]+', 'minSdk = 23')
    if ($g -notmatch 'useLegacyPackaging') {
        $g = [regex]::Replace($g, '(?m)^android\s*\{', "android {`r`n    packaging {`r`n        jniLibs {`r`n            useLegacyPackaging = true`r`n        }`r`n    }", 1)
    }
} else {
    $g = [regex]::Replace($g, 'minSdkVersion\s+[^\r\n]+', 'minSdkVersion 23')
    if ($g -notmatch 'useLegacyPackaging') {
        $g = [regex]::Replace($g, '(?m)^android\s*\{', "android {`r`n    packaging {`r`n        jniLibs {`r`n            useLegacyPackaging true`r`n        }`r`n    }", 1)
    }
}
[IO.File]::WriteAllText($gradlePath, $g, (New-Object System.Text.UTF8Encoding $false))
Write-Host 'Android host آماده شد؛ Gradle Wrapper، آیکن و شناسه برنامه تنظیم شدند.' -ForegroundColor Green
