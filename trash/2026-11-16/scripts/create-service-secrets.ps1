<#
.SYNOPSIS
  sj-lab-scheduler · mapservice-rest · sj-qfieldsync 의 접속 Secret 을 만들거나 갱신한다.

.DESCRIPTION
  2026-11-16 신설. 세 서비스는 그전까지 **이미지에 구워진 평문 값**으로 DB 에 붙고 있었고,
  그 값이 public 저장소 3곳에 노출돼 있었다(계정은 표 소유자 = superuser, QFieldCloud admin
  비밀번호도 같은 값 재사용). 코드·차트를 환경변수/Secret 방식으로 바꾸면서 함께 만든 스크립트다.

  **비밀번호를 화면·명령 기록·셸 히스토리에 남기지 않는 것이 이 스크립트의 핵심이다.**
  로컬 비밀값 파일에서 읽어 바로 kubectl 로 넘기고, 출력에는 키 이름과 길이만 적는다.

  읽는 곳: sj-lab 저장소의 로컬 비밀값 파일(.gitignore 대상) 의 env
  이미 Secret 이 있으면 덮어쓴다(create --dry-run=client | apply 패턴).
  Secret 은 기동할 때 읽히므로 마지막에 파드를 재시작한다(-NoRestart 로 끌 수 있다).

  **호스트는 파일의 값이 아니라 클러스터 안 서비스 이름으로 바꿔 넣는다**(-DbHost).
  파드에서 공인 IP·NodePort 로 돌아 나갈 필요가 없고, 그 주소는 바뀔 수 있다.

.PARAMETER Service
  scheduler | map | qfieldsync | all (기본 all)

.EXAMPLE
  # 무엇을 만들지만 보여 준다(값은 만들지 않는다)
  powershell -ExecutionPolicy Bypass -File scripts\create-service-secrets.ps1 -WhatIfOnly

  # 전부 만들기
  powershell -ExecutionPolicy Bypass -File scripts\create-service-secrets.ps1

  # 하나만
  powershell -ExecutionPolicy Bypass -File scripts\create-service-secrets.ps1 -Service scheduler

.NOTES
  필요한 env 키 — 없으면 그 Secret 만 건너뛰고 무엇이 없는지 알린다.

    공통(세 서비스가 같은 DB 를 쓴다)
      SJLAB_OWNER_DB_DSN      postgresql://계정:비밀번호@호스트:포트/DB명  (적재용 계정)
    스케줄러 API 키
      APIS_SERVICE_KEY, APIS_SERVICE_KEY_2, ITS_SERVICE_KEY,
      SAFEMAP_SERVICE_KEY, JUSO_CONFM_KEY, VWORLD_API_KEY
    qfieldsync 추가
      QFC_URL, QFC_USERNAME, QFC_PASSWORD, QFC_DB_DSN

  **비밀번호를 바꿀 때는 세 Secret 을 함께 갱신해야 한다**(같은 DB 계정을 공유).
  절차는 sj-lab/docs/k8s-secrets.md 의 "비밀값 교체" 절 참고.
#>
[CmdletBinding()]
param(
  [ValidateSet('scheduler','map','qfieldsync','postgres','all')]
  [string]$Service = 'all',
  [string]$SettingsPath,
  [string]$DbHost = 'postgresql-sjlab',
  [int]$DbPort = 5432,
  [string]$Namespace = 'sj-lab',
  [switch]$NoRestart,
  [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

if (-not $SettingsPath) {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $SettingsPath = Join-Path $scriptDir '..\.claude\settings.local.json'
}

function Say([string]$m, [string]$c = 'Gray') { Write-Host "  $m" -ForegroundColor $c }
function Fail([string]$m) { Write-Host "  [중단] $m" -ForegroundColor Red; exit 1 }

# ── 1. 로컬 비밀값 읽기 ──────────────────────────────────────────────────────
if (-not (Test-Path $SettingsPath)) { Fail "설정 파일이 없습니다: $SettingsPath" }
try {
  $envMap = (Get-Content $SettingsPath -Raw | ConvertFrom-Json).env
} catch {
  Fail ("설정 파일을 읽지 못했습니다: {0}" -f $_.Exception.GetType().Name)
}
function GetEnv([string]$key) {
  if ($envMap -and $envMap.PSObject.Properties.Name -contains $key) { return [string]$envMap.$key }
  return $null
}

# postgresql://user:pass@host:port/db → 조각으로 나눈다. 실패해도 원문을 찍지 않는다.
function ParseDsn([string]$dsn, [string]$label) {
  if (-not $dsn) { return $null }
  try {
    $m = [regex]::Match($dsn, '^postgres(?:ql)?://([^:]+):([^@]+)@([^:/]+):(\d+)/(.+)$')
    if (-not $m.Success) { Say "$label 형식을 알아보지 못했습니다(postgresql://계정:비밀번호@호스트:포트/DB명)" 'Yellow'; return $null }
    return @{ user = $m.Groups[1].Value
              pass = [uri]::UnescapeDataString($m.Groups[2].Value)
              host = $m.Groups[3].Value
              port = [int]$m.Groups[4].Value
              db   = $m.Groups[5].Value }
  } catch {
    Say ("$label 파싱 실패: {0}" -f $_.Exception.GetType().Name) 'Yellow'
    return $null
  }
}

# ── 2. Secret 하나를 만들거나 갱신 ──────────────────────────────────────────
function Apply-Secret([string]$name, [hashtable]$data) {
  $missing = @($data.Keys | Where-Object { -not $data[$_] })
  if ($missing.Count -gt 0) {
    Say ("$name 건너뜀 — 값이 없는 키: " + ($missing -join ', ')) 'Yellow'
    return
  }
  Write-Host "  $name" -ForegroundColor Cyan
  foreach ($k in ($data.Keys | Sort-Object)) {
    Say ("  {0,-16} 길이 {1}" -f $k, $data[$k].Length)
  }
  if ($WhatIfOnly) { Say '  (WhatIfOnly — 만들지 않음)' 'DarkGray'; return }

  $args = @('create','secret','generic',$name,'-n',$Namespace,'--dry-run=client','-o','yaml')
  foreach ($k in $data.Keys) { $args += "--from-literal=$k=$($data[$k])" }
  $yaml = & kubectl @args
  if ($LASTEXITCODE -ne 0) { Fail "$name 생성 실패(kubectl create --dry-run)" }
  $yaml | & kubectl apply -f -
  if ($LASTEXITCODE -ne 0) { Fail "$name 적용 실패(kubectl apply)" }
  Say '  적용 완료' 'Green'
}

function Restart([string]$deployment) {
  if ($WhatIfOnly -or $NoRestart) { return }
  & kubectl rollout restart "deployment/$deployment" -n $Namespace | Out-Null
  if ($LASTEXITCODE -eq 0) { Say "  $deployment 재시작 요청" 'Green' }
  else { Say "  $deployment 재시작 실패(배포가 없을 수 있음)" 'Yellow' }
}

# ── 3. 대상별 처리 ───────────────────────────────────────────────────────────
Write-Host ''
Write-Host '접속 Secret 만들기/갱신' -ForegroundColor White
Say "네임스페이스 $Namespace · 파드에서 쓸 DB 호스트 $DbHost`:$DbPort"
if ($WhatIfOnly) { Say '모의 실행(WhatIfOnly) — 아무것도 바꾸지 않습니다' 'DarkGray' }
Write-Host ''

$owner = ParseDsn (GetEnv 'SJLAB_OWNER_DB_DSN') 'SJLAB_OWNER_DB_DSN'
if (-not $owner) {
  Say '적재용 DB 접속 정보(SJLAB_OWNER_DB_DSN)가 없습니다 — DB Secret 은 만들 수 없습니다.' 'Yellow'
}
# 파드는 클러스터 안 서비스 이름으로 붙는다(파일의 공인 IP·NodePort 가 아니라).
$jdbc = if ($owner) { "jdbc:postgresql://$DbHost`:$DbPort/$($owner.db)" } else { $null }

if ($Service -in @('scheduler','all')) {
  if ($owner) {
    Apply-Secret 'scheduler-db-credentials' @{ url = $jdbc; username = $owner.user; password = $owner.pass }
  }
  Apply-Secret 'scheduler-api-keys' @{
    apis   = GetEnv 'APIS_SERVICE_KEY'
    apis2  = GetEnv 'APIS_SERVICE_KEY_2'
    its    = GetEnv 'ITS_SERVICE_KEY'
    safe   = GetEnv 'SAFEMAP_SERVICE_KEY'
    juso   = GetEnv 'JUSO_CONFM_KEY'
    vworld = GetEnv 'VWORLD_API_KEY'
  }
  Restart 'sj-lab-scheduler'
}

if ($Service -in @('map','all')) {
  if ($owner) {
    Apply-Secret 'map-db-credentials' @{ url = $jdbc; username = $owner.user; password = $owner.pass }
    Restart 'mapservice-rest'
  }
}

if ($Service -in @('qfieldsync','all')) {
  $qfc = ParseDsn (GetEnv 'QFC_DB_DSN') 'QFC_DB_DSN'
  if ($owner -and $qfc) {
    Apply-Secret 'qfieldsync-credentials' @{
      qfcUrl         = GetEnv 'QFC_URL'
      qfcUsername    = GetEnv 'QFC_USERNAME'
      qfcPassword    = GetEnv 'QFC_PASSWORD'
      qfcDbHost      = $qfc.host
      qfcDbName      = $qfc.db
      qfcDbUser      = $qfc.user
      qfcDbPassword  = $qfc.pass
      dataDbHost     = $DbHost
      dataDbName     = $owner.db
      dataDbUser     = $owner.user
      dataDbPassword = $owner.pass
    }
    Restart 'sj-qfieldsync'
  } else {
    Say 'qfieldsync 건너뜀 — SJLAB_OWNER_DB_DSN 또는 QFC_DB_DSN 이 없습니다.' 'Yellow'
  }
}

Write-Host ''
if ($Service -in @('postgres','all')) {
  # DB 차트 자신의 계정 정보. 이 값은 postgres 이미지가 **데이터 디렉터리가 빈 경우에만**
  # (최초 초기화) 쓴다 — 이미 만들어진 DB 에서는 없어도 기동되므로 차트에서 optional: true 다.
  # 그래도 만들어 두는 이유: 비밀번호를 바꿀 때 여기도 같이 고쳐야 재배포 시 옛 값으로
  # 되돌아가지 않고, 볼륨을 새로 잡을 때 초기화가 정상 동작한다.
  if ($owner) {
    Apply-Secret 'postgres-auth' @{ username = $owner.user; password = $owner.pass }
  }
  $qfc2 = ParseDsn (GetEnv 'QFC_DB_DSN') 'QFC_DB_DSN'
  if ($qfc2) {
    Apply-Secret 'postgres-qfield-auth' @{ username = $qfc2.user; password = $qfc2.pass }
  }
  # DB 파드는 재시작하지 않는다 — 운영 DB 가 잠깐 끊긴다. 이 값은 지금 동작에 영향이 없다.
  Say '  (DB 파드는 재시작하지 않습니다 — 이 값은 최초 초기화에만 쓰입니다)' 'DarkGray'
}
Say '확인: kubectl get secret -n sj-lab | findstr /i "credentials api-keys"'
Say '확인: kubectl get pods -n sj-lab'
Write-Host ''
