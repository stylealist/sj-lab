<#
.SYNOPSIS
  부동산 조회 서비스(sj-lab-estate)의 DB 접속 Secret 을 만들거나 갱신한다.

.DESCRIPTION
  접속 정보를 **파일에서 읽어 바로 kubectl 로 넘긴다** — 화면·명령 기록·셸 히스토리에
  비밀번호가 남지 않게 하려는 것이 이 스크립트의 핵심이다.

  읽는 곳: sj-lab/.claude/settings.local.json 의 env
    - 기본값 SJLAB_DEV_DATABASE_URL (조회 전용 계정 mcp_readonly)
    - -EnvKey ESTATE_DB_DSN 처럼 다른 키를 지정할 수도 있다
  형식: postgresql://계정:비밀번호@호스트:포트/DB명  →  jdbc:postgresql://<k8s 서비스>:5432/<DB명>

  **호스트는 파일의 값이 아니라 클러스터 안 서비스 이름으로 바꿔 넣는다**(-DbHost).
  파드에서 공인 IP·NodePort 로 돌아 나갈 필요가 없고, 그 주소는 바뀔 수 있다.

  이미 Secret 이 있으면 덮어쓴다(create --dry-run | apply 패턴).
  Secret 은 기동할 때 읽히므로 마지막에 파드를 재시작하고 상태를 확인한다.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\create-estate-db-secret.ps1
  powershell -ExecutionPolicy Bypass -File scripts\create-estate-db-secret.ps1 -WhatIfOnly
  powershell -ExecutionPolicy Bypass -File scripts\create-estate-db-secret.ps1 -EnvKey ESTATE_DB_DSN

.NOTES
  2026-10-12 작성. 운영은 당장 mcp_readonly 로 시작하고, 전용 계정(estate_read, 스크립트
  db/estate/estate_read_role.sql)으로 바꿀 때는 그 계정의 DSN 을 -EnvKey 로 지정해 다시 돌리면 된다.
  mcp_readonly 는 MCP(에이전트 조회)와 **같은 계정**이므로, 비밀번호를 바꾸면 양쪽을 함께 고쳐야 한다.
#>
[CmdletBinding()]
param(
  [string]$SettingsPath,
  [string]$EnvKey = 'SJLAB_DEV_DATABASE_URL',
  [string]$DbHost = 'postgresql-sjlab',
  [int]$DbPort = 5432,
  [string]$Namespace = 'sj-lab',
  [string]$SecretName = 'estate-db-credentials',
  [string]$Deployment = 'sj-lab-estate',
  [string]$StatusUrl = 'https://api.sj-lab.co.kr/estate/status',
  # 실제로 만들지 않고 무엇을 할지만 보여 준다(비밀번호는 가린다)
  [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

# param 기본값에서 $PSScriptRoot 가 비어 있는 경우가 있어(Windows PowerShell 5.1) 본문에서 구한다.
if (-not $SettingsPath) {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $SettingsPath = Join-Path $scriptDir '..\.claude\settings.local.json'
}

function Fail([string]$message) {
  Write-Host "  [중단] $message" -ForegroundColor Red
  exit 1
}

# ── 1. 접속 정보 읽기 ────────────────────────────────────────────────────────
if (-not (Test-Path $SettingsPath)) { Fail "설정 파일이 없습니다: $SettingsPath" }

$dsn = $null
try {
  $env1 = (Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json).env
  $dsn = $env1.$EnvKey
} catch {
  # 예외 메시지에 파일 내용이 섞여 나오지 않도록 타입만 알린다
  Fail "설정 파일을 읽지 못했습니다($($_.Exception.GetType().Name))"
}
if (-not $dsn) { Fail "$EnvKey 값이 설정 파일에 없습니다" }

if ($dsn -notmatch '^postgres(ql)?://([^:]+):([^@]+)@([^:/]+):(\d+)/([^?]+)') {
  Fail "$EnvKey 형식을 알 수 없습니다 (postgresql://계정:비밀번호@호스트:포트/DB 형태여야 합니다)"
}
$dbUser   = [System.Uri]::UnescapeDataString($Matches[2])
$dbPass   = [System.Uri]::UnescapeDataString($Matches[3])
$dsnHost  = $Matches[4]
$dbName   = $Matches[6]

$jdbcUrl = "jdbc:postgresql://${DbHost}:${DbPort}/${dbName}"

Write-Host ''
Write-Host '부동산 DB Secret 만들기' -ForegroundColor Cyan
Write-Host ("  네임스페이스 : {0}" -f $Namespace)
Write-Host ("  Secret       : {0}" -f $SecretName)
Write-Host ("  접속 주소    : {0}" -f $jdbcUrl)
Write-Host ("  계정         : {0}" -f $dbUser)
Write-Host ("  비밀번호     : (설정 파일에서 읽어 그대로 넘깁니다 - 출력하지 않음)")
Write-Host ("  참고         : 설정 파일의 호스트는 {0} 이며, 클러스터 안에서는 {1} 로 붙습니다" -f $dsnHost, $DbHost)

if ($WhatIfOnly) {
  Write-Host ''
  Write-Host '  -WhatIfOnly 이므로 아무것도 만들지 않았습니다.' -ForegroundColor Yellow
  exit 0
}

# ── 2. kubectl 확인 ─────────────────────────────────────────────────────────
$kubectl = Get-Command kubectl -ErrorAction SilentlyContinue
if (-not $kubectl) { Fail 'kubectl 을 찾을 수 없습니다' }

$context = (& kubectl config current-context 2>&1)
if ($LASTEXITCODE -ne 0) {
  Fail 'kubectl 에 클러스터 설정(context)이 없습니다 — 클러스터에 접근 가능한 자리에서 실행하세요'
}
Write-Host ("  클러스터     : {0}" -f $context)

# DB 서비스가 그 이름으로 실제 있는지 먼저 본다(없으면 파드가 접속에 실패한다)
$svc = (& kubectl get svc $DbHost -n $Namespace -o name 2>&1)
if ($LASTEXITCODE -ne 0) {
  Write-Host ("  주의: {0} 네임스페이스에 서비스 {1} 가 보이지 않습니다." -f $Namespace, $DbHost) -ForegroundColor Yellow
  Write-Host '        kubectl get svc -A | findstr postgres 로 확인하고 -DbHost 로 지정하세요.' -ForegroundColor Yellow
  Write-Host '        (다른 네임스페이스면 postgresql-sjlab.<네임스페이스>.svc.cluster.local 형태)' -ForegroundColor Yellow
}

# ── 3. Secret 생성·갱신 ─────────────────────────────────────────────────────
# create --dry-run=client -o yaml | apply -f -  : 없으면 만들고 있으면 갱신한다.
$yaml = & kubectl create secret generic $SecretName `
  -n $Namespace `
  --from-literal=url=$jdbcUrl `
  --from-literal=username=$dbUser `
  --from-literal=password=$dbPass `
  --dry-run=client -o yaml
if ($LASTEXITCODE -ne 0) { Fail 'Secret YAML 생성 실패' }

$yaml | & kubectl apply -f - | Out-Host
if ($LASTEXITCODE -ne 0) { Fail 'Secret 적용 실패' }
Remove-Variable yaml, dbPass -ErrorAction SilentlyContinue

# ── 4. 파드 재시작 (Secret 은 기동 시 읽는다) ───────────────────────────────
& kubectl -n $Namespace rollout restart ("deploy/" + $Deployment) | Out-Host
if ($LASTEXITCODE -ne 0) { Fail '재시작 실패 — Deployment 이름을 확인하세요' }
& kubectl -n $Namespace rollout status ("deploy/" + $Deployment) --timeout=180s | Out-Host

# ── 5. 확인 ────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '상태 확인 (게이트웨이 경유, 최대 2분)' -ForegroundColor Cyan
$deadline = (Get-Date).AddMinutes(2)
while ((Get-Date) -lt $deadline) {
  try {
    $client = New-Object System.Net.WebClient
    $client.Encoding = [System.Text.Encoding]::UTF8
    $body = $client.DownloadString($StatusUrl)
    if ($body -match '"ready"\s*:\s*true') {
      Write-Host '  ready:true — 부동산 조회가 가능합니다.' -ForegroundColor Green
      Write-Host ('  ' + $body)
      exit 0
    }
    Write-Host ('  아직 ready:false — ' + $body)
  } catch {
    Write-Host ('  응답 대기 중... (' + $_.Exception.Message + ')')
  }
  Start-Sleep -Seconds 10
}

Write-Host '  2분 안에 ready:true 가 되지 않았습니다.' -ForegroundColor Yellow
Write-Host '  확인할 것: kubectl -n sj-lab logs deploy/sj-lab-estate --tail=50' -ForegroundColor Yellow
Write-Host '             (접속 거부면 계정·권한, 이름 못 찾음이면 -DbHost 값)' -ForegroundColor Yellow
exit 1
