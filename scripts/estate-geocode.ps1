<#
.SYNOPSIS
  아파트 단지 좌표(지오코딩)를 나눠서 받는 드라이버.

.DESCRIPTION
  실거래 API 는 좌표를 주지 않아 지도에 핀을 찍으려면 주소를 좌표로 바꿔야 한다.
  대상은 거래 2,100만 건이 아니라 **단지 약 44,581개**다(apt_seq 로 거래에 붙는다).

  이 스크립트는 scheduler 의 엔드포인트를 반복해서 부른다 — 실제 호출·저장은 scheduler 가 한다.
    1) /scheduler/estate/complex/sync      거래 표에서 단지를 긁어 넣는다(좌표 없음)
    2) /scheduler/estate/complex/geocode   좌표를 limit 개씩 채운다(여러 번)
    3) /scheduler/estate/complex/stats     진행 상황

  **상태가 DB(estate.apt_complex.geocode_status)에 있으므로 끊겨도 그냥 다시 돌리면 이어진다.**
  커서 파일이 없다 — 백필에서 "클라이언트 타임아웃인데 커서만 전진"으로 구멍이 났던 일을
  구조적으로 막는다.

  하루 한도에 걸리면 scheduler 가 quotaExceeded 를 돌려준다. 그때는 **건너뛰지 않고**
  기다렸다가 같은 자리에서 다시 받는다(건너뛰면 그만큼 좌표가 빈다).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\estate-geocode.ps1 -Sync
  powershell -ExecutionPolicy Bypass -File scripts\estate-geocode.ps1 -Rounds 50
  powershell -ExecutionPolicy Bypass -File scripts\estate-geocode.ps1 -SggCd 11680 -Rounds 5
  powershell -ExecutionPolicy Bypass -File scripts\estate-geocode.ps1 -StatsOnly

.NOTES
  준비물
    - estate.apt_complex 표 (sj-lab/db/estate/estate_apt_complex.sql, 담당자 실행)
    - scheduler 에 키 주입: JUSO_CONFM_KEY (필수) · VWORLD_API_KEY (선택)
    - scheduler 가 떠 있을 것. **로컬에서 띄우면 운영 DB 에 쓴다**(개발=운영 DB)
  절차와 함정은 sj-lab/docs/estate-geocode-workflow.md 에 적어 두었다.
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = "http://localhost:8100",
  # 한 번에 받을 단지 수. 너무 크게 잡으면 한 번 호출이 길어져 중간 상태를 보기 어렵다.
  [int]$BatchSize = 200,
  # 몇 번 반복할지. 0 이면 더 받을 게 없을 때까지 계속한다.
  [int]$Rounds = 0,
  [string]$SggCd,
  # 한도에 걸렸을 때 기다리는 시간(초). 하루 한도면 길게 잡아야 한다.
  [int]$QuotaWaitSec = 1800,
  [switch]$Sync,
  [switch]$StatsOnly
)

$ErrorActionPreference = "Stop"
$logPath = Join-Path $PSScriptRoot "..\.local-stack\estate-geocode.log"

function Write-Log([string]$message) {
  $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $message
  Write-Host $line
  # 로그 기록이 실패해도 수집은 계속한다(백필에서 로그 오류로 드라이버가 죽은 적이 있다)
  for ($i = 0; $i -lt 5; $i++) {
    try { Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 200 }
  }
}

function Call-Scheduler([string]$path) {
  $url = $BaseUrl.TrimEnd("/") + $path
  if ($SggCd) {
    # Windows PowerShell 5.1 에는 삼항 연산자가 없다 — if 로 쓴다
    if ($url -like "*?*") { $url += "&sggCd=$SggCd" } else { $url += "?sggCd=$SggCd" }
  }
  return Invoke-RestMethod -Uri $url -TimeoutSec 600
}

function Show-Stats($stats) {
  if (-not $stats) { return }
  Write-Log ("  전체 {0} · 좌표 있음 {1} · 대기 {2} · 실패 {3} · 건너뜀 {4}" -f `
    $stats.total, $stats.with_geom, $stats.pending, $stats.failed, $stats.skipped)
}

$logDir = Split-Path -Parent $logPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

Write-Log "=== 단지 좌표 받기 시작 ==="
Write-Log ("  대상: {0}{1}" -f $BaseUrl, $(if ($SggCd) { " (시군구 $SggCd)" } else { " (전국)" }))

# ── 상태만 보기 ─────────────────────────────────────────────────────────────
if ($StatsOnly) {
  $res = Call-Scheduler "/scheduler/estate/complex/stats"
  Write-Log ("  키 설정됨: {0}" -f $res.configured)
  Show-Stats $res.stats
  exit 0
}

# ── 1) 단지 긁어오기 ────────────────────────────────────────────────────────
if ($Sync) {
  Write-Log "거래 표에서 단지를 긁어 넣습니다(좌표는 비운 채)…"
  $stats = Call-Scheduler "/scheduler/estate/complex/sync"
  Show-Stats $stats
  Write-Log "동기화 완료"
}

# ── 2) 좌표 채우기 ──────────────────────────────────────────────────────────
$round = 0
$okTotal = 0
$failTotal = 0
$quotaWaits = 0

while ($true) {
  if ($Rounds -gt 0 -and $round -ge $Rounds) {
    Write-Log "지정한 횟수($Rounds)를 마쳤습니다."
    break
  }
  $round++

  $path = "/scheduler/estate/complex/geocode?limit=$BatchSize"
  $res = Call-Scheduler $path

  if (-not $res.configured) {
    Write-Log "중단: $($res.message)"
    Write-Log "  scheduler 에 JUSO_CONFM_KEY 를 넣고 다시 띄우세요."
    exit 1
  }

  $okTotal += [int]$res.ok
  $failTotal += [int]$res.failed
  Write-Log ("[{0}회] 받음 {1} · 실패 {2} · 건너뜀 {3} (대상 {4})" -f `
    $round, $res.ok, $res.failed, $res.skipped, $res.picked)
  Show-Stats $res.stats

  if ($res.quotaExceeded) {
    # 한도다. **건너뛰지 않는다** — 건너뛰면 그만큼 좌표가 빈다(실거래에서 광주·전남이 그렇게 비었다).
    $quotaWaits++
    Write-Log ("  하루 한도에 걸렸습니다. {0}초 기다렸다가 같은 자리에서 다시 받습니다(대기 {1}회째)." -f $QuotaWaitSec, $quotaWaits)
    Start-Sleep -Seconds $QuotaWaitSec
    $round--   # 한도로 못 받은 회차는 세지 않는다
    continue
  }

  if ([int]$res.picked -eq 0) {
    Write-Log "더 받을 단지가 없습니다 — 끝났습니다."
    break
  }
}

Write-Log ("=== 마침: 이번 실행에서 좌표 {0}개 확보 · 실패 {1} · 한도 대기 {2}회 ===" -f $okTotal, $failTotal, $quotaWaits)
$final = Call-Scheduler "/scheduler/estate/complex/stats"
Show-Stats $final.stats
Write-Log "  (실패한 단지는 상태가 남아 있어 다시 돌리면 재시도됩니다)"
