<#
.SYNOPSIS
    Flutter 플랫폼 스캐폴딩을 채워 넣는다.

.DESCRIPTION
    이 저장소에는 손으로 작성할 수 없는 파일들이 빠져 있다.
      - android/gradle/wrapper/gradle-wrapper.jar (바이너리)
      - gradlew, gradlew.bat
      - 런처 아이콘(mipmap PNG)
      - 설치된 Flutter 버전에 맞는 gradle 스크립트

    이 스크립트는 임시 폴더에 `flutter create` 로 표준 템플릿을 만든 뒤,
    **아직 없는 파일만** 복사해 온다.
    따라서 이미 작성된 AndroidManifest.xml, Kotlin 소스, lib/ 는 절대 덮어쓰지 않는다.

    gradle 스크립트를 손으로 고정하지 않고 템플릿에서 가져오는 이유:
    AGP / Kotlin / Gradle 버전 조합은 Flutter 버전마다 다르다.
    설치된 Flutter 가 기대하는 조합을 그대로 쓰는 것이 가장 안전하다.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\bootstrap.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipPubGet
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Write-Host "프로젝트 경로: $projectRoot" -ForegroundColor Cyan

# ---------------------------------------------------------------- 사전 확인
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    Write-Host ''
    Write-Host 'flutter 명령을 찾을 수 없습니다.' -ForegroundColor Red
    Write-Host 'Flutter SDK 를 설치하고 PATH 에 추가한 뒤 다시 실행하세요.'
    Write-Host '  https://docs.flutter.dev/get-started/install/windows'
    exit 1
}
Write-Host "flutter: $($flutter.Source)" -ForegroundColor Green

if ($projectRoot -match '\s') {
    Write-Host ''
    Write-Host '경고: 프로젝트 경로에 공백이 있습니다.' -ForegroundColor Yellow
    Write-Host '      대부분 문제없지만 Android 빌드가 실패하면 공백 없는 경로로'
    Write-Host '      폴더를 옮긴 뒤 다시 시도하세요.'
}

# --------------------------------------------------------------- 템플릿 생성
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bb_tmpl_" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
Write-Host ''
Write-Host "표준 템플릿 생성 중: $tempRoot" -ForegroundColor Cyan

& flutter create --platforms=android --org com.example --project-name budget_book "$tempRoot"
if ($LASTEXITCODE -ne 0) {
    Write-Host 'flutter create 실패' -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------- 없는 파일만 복사
$copied = New-Object System.Collections.Generic.List[string]
$skipped = 0

function Copy-MissingTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path $Source)) { return }

    foreach ($item in Get-ChildItem -Path $Source -Recurse -File) {
        $relative = $item.FullName.Substring($Source.Length).TrimStart('\', '/')
        $target = Join-Path $Destination $relative

        if (Test-Path $target) {
            $script:skipped++
            continue
        }

        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }
        Copy-Item -Path $item.FullName -Destination $target
        $script:copied.Add($relative)
    }
}

Write-Host ''
Write-Host 'android/ 스캐폴딩 복사 (기존 파일은 건너뜀)' -ForegroundColor Cyan
Copy-MissingTree -Source (Join-Path $tempRoot 'android') -Destination (Join-Path $projectRoot 'android')

# .metadata 는 flutter 툴링이 참조한다.
$metaSource = Join-Path $tempRoot '.metadata'
$metaTarget = Join-Path $projectRoot '.metadata'
if ((Test-Path $metaSource) -and -not (Test-Path $metaTarget)) {
    Copy-Item $metaSource $metaTarget
    $copied.Add('.metadata')
}

Write-Host ''
Write-Host "복사한 파일: $($copied.Count)개 / 유지한 기존 파일: $skipped개" -ForegroundColor Green
if ($copied.Count -gt 0) {
    $copied | Select-Object -First 25 | ForEach-Object { Write-Host "  + $_" -ForegroundColor DarkGray }
    if ($copied.Count -gt 25) {
        Write-Host "  ... 외 $($copied.Count - 25)개" -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------------- 정리
try {
    Remove-Item -Recurse -Force $tempRoot
} catch {
    Write-Host "임시 폴더 삭제 실패(무시 가능): $tempRoot" -ForegroundColor Yellow
}

# ----------------------------------------------------------------- pub get
if (-not $SkipPubGet) {
    Write-Host ''
    Write-Host 'flutter pub get 실행' -ForegroundColor Cyan
    Push-Location $projectRoot
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'flutter pub get 실패' -ForegroundColor Red
            exit 1
        }
    } finally {
        Pop-Location
    }
}

Write-Host ''
Write-Host '완료. 다음 단계:' -ForegroundColor Green
Write-Host '  1) flutter analyze          # 정적 분석'
Write-Host '  2) flutter test             # 파서/검증 단위 테스트'
Write-Host '  3) flutter run              # 기기/에뮬레이터에 설치'
Write-Host ''
Write-Host '  설치 후 앱에서 [알림 접근 권한 허용] 을 눌러 권한을 켜야 수집이 시작됩니다.'
