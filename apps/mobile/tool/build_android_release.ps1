<#
.SYNOPSIS
    构建可上架小米应用商店的 Android release APK，并校验签名、ABI 与版本。

.DESCRIPTION
    1. 校验 android/key.properties 与上传签名密钥是否存在（缺失直接中止，避免发出未签名包）。
    2. 调用 flutter build apk 生成 arm64-v8a + armeabi-v7a 通用包。
    3. 用 apksigner 校验签名，用 aapt2 校验包名、版本号与 ABI。
    4. 把产物归档到 dist/android/ 并输出 SHA-256。

.EXAMPLE
    pwsh -File tool/build_android_release.ps1 -Beian "京ICP备2026xxxxxx号-2A" `
        -PrivacyPolicyUrl "https://example.com/privacy" -SupportEmail "support@example.com"
#>
[CmdletBinding()]
param(
    # 商店版本不连接后端；如需云端模式，显式传 -ApiBaseUrl 且加 -EnableBackend。
    [string]$ApiBaseUrl = '',
    [switch]$EnableBackend,
    # 工信部 App 备案号，会显示在 App 的“隐私与协议”页。
    [string]$Beian = '',
    [string]$PrivacyPolicyUrl = '',
    [string]$TermsUrl = '',
    [string]$SupportEmail = '',
    [string]$DeveloperName = '',
    # 额外构建 x86_64 包，仅用于本机模拟器验收，不要上传商店。
    [switch]$IncludeX64,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mobileDir = Split-Path -Parent $scriptDir
$repoRoot = Split-Path -Parent (Split-Path -Parent $mobileDir)
$androidDir = Join-Path $mobileDir 'android'
$keyProperties = Join-Path $androidDir 'key.properties'
$distDir = Join-Path $repoRoot 'dist\android'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    Write-Host "`n[失败] $Message" -ForegroundColor Red
    exit 1
}

# --- 0. 环境检查 -----------------------------------------------------------
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) { Fail '找不到 flutter 命令，请把 Flutter SDK 的 bin 目录加入 PATH。' }

$sdkRoot = $env:ANDROID_HOME
if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
if (-not $sdkRoot) {
    $localProps = Join-Path $androidDir 'local.properties'
    if (Test-Path $localProps) {
        $line = Get-Content $localProps | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
        if ($line) { $sdkRoot = ($line -replace '^sdk\.dir=', '') -replace '\\\\', '\' }
    }
}
if (-not $sdkRoot -or -not (Test-Path $sdkRoot)) { Fail '找不到 Android SDK，请设置 ANDROID_HOME 或在 android/local.properties 里配置 sdk.dir。' }

$buildTools = Get-ChildItem (Join-Path $sdkRoot 'build-tools') -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $buildTools) { Fail 'Android SDK 中缺少 build-tools，无法校验签名。' }
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$aapt2 = Join-Path $buildTools.FullName 'aapt2.exe'

# --- 1. 版本号与签名检查 ---------------------------------------------------
Write-Step '读取版本号'
$pubspec = Get-Content (Join-Path $mobileDir 'pubspec.yaml')
$versionLine = ($pubspec | Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1)
if (-not $versionLine) { Fail 'pubspec.yaml 缺少 version 字段。' }
$fullVersion = ($versionLine -replace '^version:\s*', '').Trim()
$versionName = ($fullVersion -split '\+')[0]
Write-Host "versionName=$versionName  (pubspec: $fullVersion)"

Write-Step '校验上传签名'
if (-not (Test-Path $keyProperties)) {
    Fail "缺少 $keyProperties。请复制 android/key.properties.example 为 key.properties 并填写密钥信息；商店包必须使用正式签名。"
}
$keyProps = @{}
Get-Content $keyProperties | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') { $keyProps[$Matches[1].Trim()] = $Matches[2].Trim() }
}
$storeFile = $keyProps['storeFile']
if (-not $storeFile) { Fail 'key.properties 缺少 storeFile。' }
$keystorePath = if ([System.IO.Path]::IsPathRooted($storeFile)) { $storeFile } else { Join-Path (Join-Path $androidDir 'app') $storeFile }
if (-not (Test-Path $keystorePath)) { Fail "找不到签名文件：$keystorePath。请确 key.properties 的 storeFile 指向正确的 .jks。" }
Write-Host "签名文件：$keystorePath"

$expectedFingerprint = $null
$keytool = Join-Path (Join-Path $env:JAVA_HOME 'bin') 'keytool.exe'
if (Test-Path $keytool) {
    $certInfo = & $keytool -list -v -keystore $keystorePath -alias $keyProps['keyAlias'] `
        -storepass $keyProps['storePassword'] 2>&1 | Out-String
    $match = [regex]::Match($certInfo, 'SHA256:\s*([0-9A-F:]{95})')
    if ($match.Success) {
        $expectedFingerprint = ($match.Groups[1].Value -replace ':', '').ToUpperInvariant()
        Write-Host "签名证书 SHA-256：$($match.Groups[1].Value)"
    }
}

# --- 2. 构建 ---------------------------------------------------------------
$defines = @("APP_VERSION=$versionName")
if ($ApiBaseUrl) { $defines += "API_BASE_URL=$ApiBaseUrl" }
if ($EnableBackend) { $defines += 'ENABLE_BACKEND=true' }
if ($Beian) { $defines += "APP_BEIAN=$Beian" }
if ($PrivacyPolicyUrl) { $defines += "PRIVACY_POLICY_URL=$PrivacyPolicyUrl" }
if ($TermsUrl) { $defines += "TERMS_URL=$TermsUrl" }
if ($SupportEmail) { $defines += "SUPPORT_EMAIL=$SupportEmail" }
if ($DeveloperName) { $defines += "DEVELOPER_NAME=$DeveloperName" }

$targetPlatforms = if ($IncludeX64) { 'android-arm,android-arm64,android-x64' } else { 'android-arm,android-arm64' }

Write-Step "flutter build apk --release (target-platform=$targetPlatforms)"
$flutterArgs = @('build', 'apk', '--release', '--target-platform', $targetPlatforms) +
    ($defines | ForEach-Object { "--dart-define=$_" })
Push-Location $mobileDir
try {
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { Fail "flutter build 失败（exit=$LASTEXITCODE）。" }
} finally {
    Pop-Location
}

$apkSource = Join-Path $mobileDir 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apkSource)) { Fail "未找到构建产物：$apkSource" }

# --- 3. 校验 ---------------------------------------------------------------
if (-not $SkipVerify) {
    Write-Step '校验签名'
    $signerOut = & $apksigner verify --print-certs $apkSource 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Fail "apksigner 校验失败：`n$signerOut" }
    $apkFingerprint = [regex]::Match($signerOut, 'SHA-256 digest:\s*([0-9A-Fa-f:]+)')
    if ($apkFingerprint.Success) {
        $actual = ($apkFingerprint.Groups[1].Value -replace ':', '').ToUpperInvariant()
        if ($expectedFingerprint -and $actual -ne $expectedFingerprint) {
            Fail "APK 签名与 keystore 不一致：`n  APK : $actual`n  期望: $expectedFingerprint"
        }
        Write-Host "APK 签名 SHA-256：$($apkFingerprint.Groups[1].Value)" -ForegroundColor Green
    }
    if ($signerOut -match 'Android Debug') { Fail '检测到 debug 签名，禁止上架。' }

    Write-Step '校验包名 / 版本 / ABI'
    $badging = & $aapt2 dump badging $apkSource 2>&1 | Out-String
    $packageLine = [regex]::Match($badging, "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'")
    if (-not $packageLine.Success) { Fail 'aapt2 无法解析 APK 的包信息。' }
    Write-Host "包名：$($packageLine.Groups[1].Value)"
    Write-Host "versionCode：$($packageLine.Groups[2].Value)"
    Write-Host "versionName：$($packageLine.Groups[3].Value)"
    if ($packageLine.Groups[3].Value -ne $versionName) {
        Fail "APK versionName($($packageLine.Groups[3].Value)) 与 pubspec($versionName) 不一致。"
    }
    $abis = [regex]::Matches($badging, "'([a-z0-9_\-]+)'") | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -in @('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64') } | Select-Object -Unique
    Write-Host "native-code：$($abis -join ', ')"
    if ($abis -contains 'x86_64' -and -not $IncludeX64) {
        Write-Host '[提醒] 包里带了 x86_64，商店包请保留 arm 架构并去掉 -IncludeX64。' -ForegroundColor Yellow
    }
}

# --- 4. 归档 ---------------------------------------------------------------
Write-Step '归档产物'
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$archName = if ($IncludeX64) { 'yan-studio-x64-test' } else { 'yan-studio' }
$apkName = "$archName-v$versionName-release.apk"
$apkTarget = Join-Path $distDir $apkName
Copy-Item $apkSource $apkTarget -Force

$hash = (Get-FileHash -Algorithm SHA256 $apkTarget).Hash
$sizeMb = [math]::Round((Get-Item $apkTarget).Length / 1MB, 2)
"$hash  $apkName" | Set-Content (Join-Path $distDir "$archName-v$versionName-release.apk.sha256") -Encoding ASCII

Write-Host "`n产物：$apkTarget" -ForegroundColor Green
Write-Host "大小：$sizeMb MB"
Write-Host "SHA-256：$hash"
Write-Host "`n提审材料与待补资质见 docs/xiaomi-release-checklist.md" -ForegroundColor Cyan
