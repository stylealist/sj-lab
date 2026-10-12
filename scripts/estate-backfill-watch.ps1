# ============================================================================
# 아파트 백필 진행상황 보기
#
# estate-backfill.ps1 이 남기는 진행 상황 파일과 로그를 읽어, 터미널에 한 화면으로 보여 준다.
# 몇 초마다 다시 그리며, 멈추려면 Ctrl+C.
#
#   powershell -ExecutionPolicy Bypass -File scripts\estate-backfill-watch.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\estate-backfill-watch.ps1 -intervalSec 10
#   powershell -ExecutionPolicy Bypass -File scripts\estate-backfill-watch.ps1 -once
# ============================================================================

param(
    [int] $intervalSec = 15,
    [switch] $once          # 한 번만 출력하고 끝낸다(다른 스크립트에서 불러 쓸 때)
)

$repoRoot  = Split-Path -Parent $PSScriptRoot
$stateDir  = Join-Path $repoRoot ".local-stack"
$statePath = Join-Path $stateDir "estate-backfill.json"
$logPath   = Join-Path $stateDir "estate-backfill.log"

# 백필이 내려갈 수 있는 가장 과거(실거래 공개 시작 무렵) — 진행률 계산 기준
$oldestMonth = "200601"

function Get-MonthIndex([string] $yyyyMM) {
    $y = [int] $yyyyMM.Substring(0, 4)
    $m = [int] $yyyyMM.Substring(4, 2)
    return $y * 12 + $m
}

function Format-Bar([double] $ratio, [int] $width = 44) {
    if ($ratio -lt 0) { $ratio = 0 }
    if ($ratio -gt 1) { $ratio = 1 }
    $filled = [int] [Math]::Round($ratio * $width)
    return ("#" * $filled) + ("." * ($width - $filled))
}

function Show-Progress {
    if (-not (Test-Path $statePath)) {
        Write-Host ""
        Write-Host "  아직 진행 상황 파일이 없습니다: $statePath"
        Write-Host "  백필을 시작하면 생깁니다 (scripts\estate-backfill.ps1)"
        return
    }

    $s = Get-Content $statePath -Raw | ConvertFrom-Json

    # 진행률 — 시작한 달에서 2006-01 까지를 100% 로 본다
    $firstChunk = if ($s.chunks.Count -gt 0) { $s.chunks[0].Split("~")[1] } else { $s.cursor }
    $startIdx   = Get-MonthIndex $firstChunk
    $cursorIdx  = Get-MonthIndex ([string] $s.cursor)
    $oldestIdx  = Get-MonthIndex $oldestMonth
    $totalSpan  = [Math]::Max(1, $startIdx - $oldestIdx)
    $doneSpan   = $startIdx - $cursorIdx
    $ratio      = $doneSpan / $totalSpan

    $schedulerUp = $false
    try {
        Invoke-WebRequest -Uri "http://localhost:8120/scheduler/hello-world" -UseBasicParsing -TimeoutSec 3 | Out-Null
        $schedulerUp = $true
    } catch { }

    Clear-Host
    Write-Host ""
    Write-Host "  아파트 실거래 백필 진행상황          " -NoNewline
    Write-Host (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -ForegroundColor DarkGray
    Write-Host "  " ("=" * 66) -ForegroundColor DarkGray
    Write-Host ""

    # 진행 막대
    $pct = [Math]::Round($ratio * 100, 1)
    Write-Host "  기간   " -NoNewline
    Write-Host ("{0} -> {1}" -f $firstChunk, $s.cursor) -ForegroundColor White -NoNewline
    Write-Host ("   (목표 {0})" -f $oldestMonth) -ForegroundColor DarkGray
    Write-Host "  진행   " -NoNewline
    Write-Host ("[{0}] {1}%" -f (Format-Bar $ratio), $pct) -ForegroundColor Cyan
    Write-Host ("         받은 개월 {0} / 남은 개월 {1} / 처리 구간 {2}" -f `
        $doneSpan, [Math]::Max(0, $cursorIdx - $oldestIdx), $s.chunks.Count) -ForegroundColor DarkGray
    Write-Host ""

    # 데이터셋별 상태
    Write-Host "  데이터셋     적재 건수       연속 0건    상태"
    Write-Host "  " ("-" * 66) -ForegroundColor DarkGray
    foreach ($ds in @(
        @{ name = "매매   "; n = $s.insertedTrades; empty = $s.emptyTrades; done = $s.doneTrades },
        @{ name = "전월세 "; n = $s.insertedRents;  empty = $s.emptyRents;  done = $s.doneRents }
    )) {
        $status = if ($ds.done) { "멈춤(12개월 연속 0건)" } else { "진행 중" }
        $color  = if ($ds.done) { "DarkGray" } else { "Green" }
        Write-Host ("  {0}    {1,12}    {2,6}개월    " -f $ds.name, ("{0:N0}" -f $ds.n), $ds.empty) -NoNewline
        Write-Host $status -ForegroundColor $color
    }
    Write-Host ""

    # scheduler 상태 — 이게 꺼지면 백필이 더 진행되지 않는다
    Write-Host "  scheduler(8120)  " -NoNewline
    if ($schedulerUp) { Write-Host "응답" -ForegroundColor Green }
    else { Write-Host "응답 없음 — 백필이 멈춰 있습니다" -ForegroundColor Red }
    Write-Host ""

    # 최근 로그
    if (Test-Path $logPath) {
        Write-Host "  최근 기록" -ForegroundColor DarkGray
        Write-Host "  " ("-" * 66) -ForegroundColor DarkGray
        Get-Content $logPath -Tail 8 | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Gray }
    }
    Write-Host ""
    if (-not $once) {
        Write-Host ("  {0}초마다 갱신 · 멈추려면 Ctrl+C" -f $intervalSec) -ForegroundColor DarkGray
    }
}

if ($once) {
    Show-Progress
    return
}

while ($true) {
    Show-Progress
    Start-Sleep -Seconds $intervalSec
}
