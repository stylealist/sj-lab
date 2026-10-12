# ============================================================================
# 아파트 실거래(매매·전월세) 과거 데이터 백필
#
# 이번 달부터 6개월씩 과거로 내려가며 받고, 한 데이터셋이 "12개월 연속 0건"이 되면
# 그 데이터셋은 멈춘다. 둘 다 멈추면 전체 종료.
#
#   202605~202610  ->  202511~202604  ->  202505~202510  ->  ...
#
# 왜 "새로 들어간 건수"로 판단하나
#   표에 유니크 인덱스가 있고 수집이 ON CONFLICT DO NOTHING 이라, 이미 있는 거래는
#   세지 않는다. 그래서 0건이면 "그 구간은 더 받을 게 없다"는 뜻이 된다.
#   (매매는 2006년, 전월세는 2011년 무렵부터 데이터가 있어 각자 다른 시점에 멈춘다)
#
# 중간에 끊겨도 괜찮다
#   진행 상황을 .local-stack\estate-backfill.json 에 남긴다. 다시 실행하면 이어서 간다.
#   같은 구간을 다시 받아도 중복은 쌓이지 않는다.
#
# 먼저 되어 있어야 하는 것
#   1) db/estate/estate_apt.sql 실행(표·유니크 인덱스)
#   2) sj-lab-scheduler 기동 — 아래 -baseUrl 로 닿는 곳
#      주의: scheduler 를 띄우면 다른 수집 cron 도 함께 동작하고 실제 DB에 적재된다.
#
# 사용 예
#   powershell -ExecutionPolicy Bypass -File scripts\estate-backfill.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\estate-backfill.ps1 -chunkMonths 3
#   powershell -ExecutionPolicy Bypass -File scripts\estate-backfill.ps1 -maxChunks 2   # 2구간만
#   powershell -ExecutionPolicy Bypass -File scripts\estate-backfill.ps1 -dryRun        # 구간만 출력
#   powershell -ExecutionPolicy Bypass -File scripts\estate-backfill.ps1 -reset         # 처음부터
# ============================================================================

param(
    # scheduler 주소. 게이트웨이를 통하려면 http://localhost:8100/scheduler
    [string] $baseUrl = "http://localhost:8120/scheduler",

    # 한 번에 받는 개월 수
    [int] $chunkMonths = 6,

    # 몇 개월 연속 0건이면 그 데이터셋을 멈출지
    [int] $stopAfterEmptyMonths = 12,

    # 이번 실행에서 처리할 구간 수 상한(0 = 제한 없음). 일일 트래픽 한도를 나눠 쓸 때 사용
    [int] $maxChunks = 0,

    # 구간 사이 쉬는 시간(초)
    [int] $sleepBetweenChunks = 5,

    # 한 구간 호출의 응답 대기 상한(초). 6개월 × 251 시군구라 넉넉히 둔다
    [int] $timeoutSec = 7200,

    # 공공데이터 호출 한도(429)에 걸렸을 때 기다리는 시간(초). 기본 20분
    [int] $throttleWaitSec = 1200,

    # 한도 대기를 몇 번까지 반복할지. 기본 72회 = 최대 24시간 기다린 뒤 포기
    [int] $throttleMaxWaits = 72,

    # 받지 않고 대상 구간만 보여 준다
    [switch] $dryRun,

    # 진행 상황 파일을 지우고 이번 달부터 다시 시작
    [switch] $reset
)

$ErrorActionPreference = "Stop"

$repoRoot  = Split-Path -Parent $PSScriptRoot
$stateDir  = Join-Path $repoRoot ".local-stack"
$statePath = Join-Path $stateDir "estate-backfill.json"
$logPath   = Join-Path $stateDir "estate-backfill.log"

if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force $stateDir | Out-Null }

function Write-Log([string] $message) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $message
    Write-Host $line

    # 로그 쓰기가 실패해도 수집은 계속해야 한다.
    # 2026-10-08: 진행 감시 스크립트가 같은 파일을 읽는 사이 Add-Content 가
    # "Stream was not readable" 로 한 번 실패했고, ErrorActionPreference=Stop 때문에
    # 드라이버가 통째로 죽어 백필이 38개월 남은 상태에서 멈췄다.
    # 그래서 몇 번 다시 시도하고, 끝까지 안 되면 조용히 넘어간다(로그보다 수집이 중요).
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Add-Content -Path $logPath -Value $line -Encoding utf8 -ErrorAction Stop
            return
        } catch {
            Start-Sleep -Milliseconds (100 * $attempt)
        }
    }
}

# ---------------------------------------------------------------------------
# 진행 상황
#   cursor              : 다음에 받을 구간의 "마지막 달"(yyyyMM)
#   emptyMonths.<이름>  : 그 데이터셋이 연속으로 0건을 받은 개월 수
#   done.<이름>         : 멈춘 데이터셋
# ---------------------------------------------------------------------------
if ($reset -and (Test-Path $statePath)) {
    Remove-Item $statePath -Force
    Write-Log "진행 상황을 지웠습니다. 이번 달부터 다시 시작합니다."
}

if (Test-Path $statePath) {
    $state = Get-Content $statePath -Raw | ConvertFrom-Json
    Write-Log ("이어서 진행합니다. 다음 구간 끝 = {0}" -f $state.cursor)
} else {
    $state = [pscustomobject]@{
        cursor          = (Get-Date -Format "yyyyMM")
        emptyTrades     = 0
        emptyRents      = 0
        doneTrades      = $false
        doneRents       = $false
        insertedTrades  = 0
        insertedRents   = 0
        chunks          = @()
    }
    Write-Log ("처음부터 진행합니다. 시작 구간 끝 = {0}" -f $state.cursor)
}

function Save-State {
    $state | ConvertTo-Json -Depth 5 | Out-File -FilePath $statePath -Encoding utf8
}

function Add-Months([string] $yyyyMM, [int] $delta) {
    $y = [int] $yyyyMM.Substring(0, 4)
    $m = [int] $yyyyMM.Substring(4, 2)
    $d = (Get-Date -Year $y -Month $m -Day 1).AddMonths($delta)
    return $d.ToString("yyyyMM")
}

# ---------------------------------------------------------------------------
# scheduler 가 떠 있는지 먼저 확인 — 없으면 아무것도 하지 않고 안내만 한다
# ---------------------------------------------------------------------------
if (-not $dryRun) {
    try {
        Invoke-WebRequest -Uri "$baseUrl/hello-world" -UseBasicParsing -TimeoutSec 10 | Out-Null
        Write-Log "scheduler 응답 확인: $baseUrl"
    } catch {
        Write-Log "scheduler 에 닿지 못했습니다: $baseUrl"
        Write-Log "먼저 띄우세요. 예:"
        Write-Log "  cd C:\developer\workspace\sj-lab-scheduler"
        Write-Log "  `$env:JAVA_HOME='C:\Program Files\Java\jdk-17'"
        Write-Log "  .\mvnw.cmd -DskipTests package"
        Write-Log "  java -jar target\*.jar --spring.profiles.active=local --server.port=8120"
        Write-Log "주의: scheduler 를 띄우면 다른 수집 cron 도 함께 돌며 실제 DB에 적재됩니다."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 한 데이터셋의 한 구간을 받는다. 새로 들어간 건수를 돌려준다(-1 이면 호출 실패)
# ---------------------------------------------------------------------------
function Invoke-Chunk([string] $dataset, [string] $from, [string] $to) {
    $url = "{0}/apis/housing/{1}?from={2}&to={3}" -f $baseUrl, $dataset, $from, $to
    try {
        $r = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $timeoutSec
        $inserted = 0
        if ($null -ne $r.inserted) { $inserted = [int] $r.inserted }
        $skipped = 0
        if ($null -ne $r.skipped) { $skipped = [int] $r.skipped }
        return [pscustomobject]@{ inserted = $inserted; skipped = $skipped; failed = $false }
    } catch {
        Write-Log ("  [{0}] 호출 실패: {1}" -f $dataset, $_.Exception.Message)
        return [pscustomobject]@{ inserted = 0; skipped = 0; failed = $true }
    }
}

# 한도(429)에 걸려 건너뛴 호출이 있으면 이 구간은 "데이터 없음"이 아니라 "못 받음"이다.
# 커서를 전진시키지 않고 기다렸다 같은 구간을 다시 받는다.
# 이걸 구분하지 않으면 못 받은 구간이 0건으로 세어져 멈춤 규칙이 잘못 발동한다.
$throttleWaits = 0

$chunkIndex = 0
while ($true) {

    if ($state.doneTrades -and $state.doneRents) {
        Write-Log "두 데이터셋 모두 멈춤 조건에 도달했습니다. 종료합니다."
        break
    }
    if ($maxChunks -gt 0 -and $chunkIndex -ge $maxChunks) {
        Write-Log ("이번 실행 상한({0}구간)에 도달했습니다. 다시 실행하면 이어서 갑니다." -f $maxChunks)
        break
    }

    $to   = [string] $state.cursor
    $from = Add-Months $to (-1 * ($chunkMonths - 1))

    # 너무 과거까지 내려가는 것을 막는 안전장치(실거래 공개 시작 이전)
    if ([int] $from -lt 200601) {
        Write-Log "2006-01 이전까지 내려왔습니다. 안전장치로 종료합니다."
        break
    }

    $chunkIndex++
    Write-Log ("구간 {0}: {1} ~ {2}" -f $chunkIndex, $from, $to)

    if ($dryRun) {
        $state.cursor = Add-Months $from -1
        continue
    }

    $tradeResult = if (-not $state.doneTrades) { Invoke-Chunk "aptTrades" $from $to } else { $null }
    $rentResult  = if (-not $state.doneRents)  { Invoke-Chunk "aptRents"  $from $to } else { $null }

    # 한도에 걸렸는지 먼저 본다 — 걸렸으면 이 구간은 집계하지 않고 커서도 그대로 둔다
    $skipped = 0
    if ($tradeResult) { $skipped += $tradeResult.skipped }
    if ($rentResult)  { $skipped += $rentResult.skipped }

    if ($skipped -gt 0) {
        $throttleWaits++
        Write-Log ("  호출 한도로 {0}건을 받지 못했습니다. 이 구간({1}~{2})은 집계하지 않고 {3}초 뒤 다시 받습니다. (대기 {4}/{5})" -f `
            $skipped, $from, $to, $throttleWaitSec, $throttleWaits, $throttleMaxWaits)
        if ($throttleWaits -ge $throttleMaxWaits) {
            Write-Log "한도 대기 횟수를 넘겼습니다. 여기서 멈춥니다 — 나중에 다시 실행하면 이 구간부터 이어서 갑니다."
            break
        }
        $chunkIndex--   # 이 구간은 처리한 것으로 세지 않는다
        Start-Sleep -Seconds $throttleWaitSec
        continue
    }
    $throttleWaits = 0

    # --- 매매 ---
    if ($tradeResult) {
        if ($tradeResult.failed) {
            Write-Log "  매매: 호출이 실패해 이 구간을 건너뜁니다(진행 상황은 올리지 않음)."
        } else {
            $n = $tradeResult.inserted
            Write-Log ("  매매: 새로 {0}건" -f $n)
            $state.insertedTrades += $n
            if ($n -eq 0) {
                $state.emptyTrades += $chunkMonths
                if ($state.emptyTrades -ge $stopAfterEmptyMonths) {
                    $state.doneTrades = $true
                    Write-Log ("  매매: {0}개월 연속 0건 — 멈춤" -f $state.emptyTrades)
                }
            } else {
                $state.emptyTrades = 0
            }
        }
    }

    # --- 전월세 ---
    if ($rentResult) {
        if ($rentResult.failed) {
            Write-Log "  전월세: 호출이 실패해 이 구간을 건너뜁니다."
        } else {
            $n = $rentResult.inserted
            Write-Log ("  전월세: 새로 {0}건" -f $n)
            $state.insertedRents += $n
            if ($n -eq 0) {
                $state.emptyRents += $chunkMonths
                if ($state.emptyRents -ge $stopAfterEmptyMonths) {
                    $state.doneRents = $true
                    Write-Log ("  전월세: {0}개월 연속 0건 — 멈춤" -f $state.emptyRents)
                }
            } else {
                $state.emptyRents = 0
            }
        }
    }

    $state.chunks += ("{0}~{1}" -f $from, $to)
    $state.cursor = Add-Months $from -1
    Save-State

    if ($sleepBetweenChunks -gt 0) { Start-Sleep -Seconds $sleepBetweenChunks }
}

# -dryRun 은 실제로 받지 않았으므로 진행 상황을 남기지 않는다.
# (남기면 다음 실행이 "이미 받은 것"으로 보고 그 구간을 건너뛴다)
if ($dryRun) {
    Write-Log "dry-run 이므로 진행 상황을 저장하지 않았습니다."
    return
}

Save-State
Write-Log ("누적 — 매매 {0}건, 전월세 {1}건 / 처리 구간 {2}개" -f `
    $state.insertedTrades, $state.insertedRents, $state.chunks.Count)
Write-Log ("진행 상황: {0}" -f $statePath)
