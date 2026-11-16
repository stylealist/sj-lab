# ============================================================================
# estate.apt_rent 보증금 복구 — 전월세 재수집 + 쌍둥이 행 정리 (한 달씩 번갈아)
#
#   왜: 수집기가 금액의 천 단위 쉼표를 떼지 않아 1,000만원 이상 보증금이 모두 null 이 됐다
#       (전체 11,889,562 행 중 11,044,773 행 = 93%). 쉼표 처리는 2026-10-12 에 고쳐졌고
#       원천은 모든 기간에 보증금을 정상으로 주므로 **다시 받으면 채워진다**.
#       진단 근거: 과거 데이터의 `max(deposit)` 이 해마다 예외 없이 999 에서 멈춰 있었다.
#
#   무엇을: 전월세(aptRents)만 최신 달부터 과거로 **한 달 받고 → 그 달을 정리**하고 다음 달로 간다.
#           매매(aptTrades)는 건드리지 않는다 — 매매 금액은 호출부에서 쉼표를 떼고 있어 멀쩡하다.
#
#   왜 정리가 필요한가: 유니크 키 `ux_apt_rent_natural` 에 deposit 이 들어 있어, 재수집은 옛 행을
#           고치지 않고 **옆에 새 행을 만든다**(= 같은 계약이 두 줄). 그래서 받은 직후 빈 쪽을 지운다.
#           **반드시 재수집 → 정리 순서.** 먼저 지우면 재수집 실패 시 데이터가 빈다.
#           지우는 SQL 과 그 근거는 `db/estate/estate_apt_rent_deposit_cleanup.sql` 에 있다.
#
#   한 달씩 번갈아 하는 이유: 한 달 재수집은 그 달 행을 약 2배로 늘린다. 전 기간(189개월)을 먼저
#           다 받으면 표가 한동안 2배(약 +2.5GB 힙 + 인덱스)가 된다. 한 달마다 정리하면
#           늘어나는 양이 한 달치(수만 행)로 묶인다.
#
#   기간: 원천의 전월세는 **2011-01 부터** 있다(2006·2008·2010 은 전 지역 0건 — 신고제 시작 전).
#
#   주의: 대상 DB 는 운영과 같은 인스턴스다. 사용자 확인 후에만 돌릴 것.
#         접속 정보는 scheduler 의 application.yml 에서 읽기만 하고 **절대 출력하지 않는다.**
#
#   보기:
#     powershell -ExecutionPolicy Bypass -File scripts\estate-rent-deposit-refill.ps1 `
#       -fromYm 202609 -toYm 201101
#     # 재수집만 하고 정리는 나중에
#     ... -noCleanup
#     # 진행 보기
#     Get-Content .local-stack\rent-deposit-refill.log -Tail 20 -Wait
# ============================================================================
param(
    [string] $fromYm  = "202609",                            # 시작(최신) 달
    [string] $toYm    = "201101",                            # 끝(가장 과거) 달 — 원천의 시작
    [string] $baseUrl = "http://localhost:8130/scheduler",
    [int]    $timeoutSec = 1800,                             # 한 달 호출 상한(시군구 251개)
    [int]    $maxFailures = 3,                               # 연속 실패 허용 횟수
    [switch] $noCleanup,                                     # 정리(DELETE)를 하지 않는다
    [int]    $vacuumEveryMonths = 24,                        # 몇 달마다 VACUUM 할지(0=안 함)
    [string] $tag = "",                                      # 여러 개를 나란히 돌릴 때 구분용(로그·상태 파일 이름)
    [string] $psqlPath = "C:\Program Files\PostgreSQL\15\bin\psql.exe"
)

# ---------------------------------------------------------------------------
# 여러 개를 나란히 돌릴 때 (`-tag a` · `-tag b` …)
#
# 병목은 API 가 아니라 **DB 적재**다(실측: 800건 한 지역에서 API 0.3~1.2초 · DB 3.8~5.7초).
# 수집기는 시군구를 하나씩 차례로 처리하므로 DB 가 디스크를 기다리는 동안 놀고 있다.
# **겹치지 않는 기간**을 맡겨 둘셋을 나란히 돌리면 그 대기를 겹칠 수 있다.
#
# 반드시 지킬 것:
#   · 기간이 겹치지 않게 할 것(같은 달을 둘이 받으면 헛일만 한다)
#   · `-tag` 를 서로 다르게 줄 것 — 안 그러면 상태 파일을 서로 덮어쓴다
#   · 건너뛴 요청 수(`skipped`)는 **믿지 말 것** — 수집기가 static 카운터로 세어 나란히 돌리면
#     숫자가 섞인다. 대신 스케줄러 로그에서 달별로 셀 것:
#       grep "재시도 4번이 모두 실패" scheduler-8130.log | grep -o "DEAL_YMD=[0-9]*" | sort | uniq -c
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 왜 중간에 VACUUM 을 하는가 (2026-11-12 실측)
#
# 한 달마다 수만 행을 지우므로 "죽은 자리"가 빠르게 쌓인다. 197만 개(14.4%)가 쌓인 시점에
# **달당 소요가 1.6분 → 12분으로 4배 느려졌다.** 특정 지역이 아니라 시군구당 0.62초 → 2.86초로
# 고르게 느려졌다 — 새 행을 넣을 때마다 중복검사 인덱스(`ux_apt_rent_natural`, 2.4GB)를
# 뒤져야 하는데 죽은 자리 때문에 읽을 페이지가 늘기 때문이다.
# PostgreSQL 자동 청소는 이 속도의 churn 을 따라오지 못한다(기본 임계값 20%).
#
# 그래서 일정 달마다 직접 `VACUUM ANALYZE` 를 돌린다. **평범한 VACUUM 은 잠금을 걸지 않아**
# 사이트는 그대로 동작한다(그동안 조회가 다소 느려질 수 있다). `VACUUM FULL` 은 쓰지 않는다
# — 그건 표를 통째로 잠근다.
# ---------------------------------------------------------------------------

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# 도는 동안 시스템이 잠들지 못하게 한다 (2026-11-12 밤에 실제로 당한 일)
#
# 절전 시간을 "없음"으로 둬도 요즘 노트북은 **Modern Standby** 로 알아서 저전력 상태에 들어간다.
# 그러면 이 프로세스가 멈추고, 멈춰 있는 동안 DB 가 유휴 연결을 끊어
# `FATAL: terminating connection due to administrator command` 로 그 달 수집이 죽는다.
# (실측: 밤새 네 번 절전 → Hikari 가 `clock leap detected (6h13m)` 를 남기고 작업이 멈춤)
#
# 전원 설정을 건드리지 않고, **이 스크립트가 도는 동안만** 절전을 막는다(끝나면 스스로 풀린다).
# ---------------------------------------------------------------------------
try {
    Add-Type -Name PowerKeeper -Namespace Win32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern uint SetThreadExecutionState(uint esFlags);
'@ -ErrorAction Stop
    # ES_CONTINUOUS(0x80000000) | ES_SYSTEM_REQUIRED(0x1) | ES_AWAYMODE_REQUIRED(0x40)
    # **[uint32] 캐스트가 꼭 필요하다.** PowerShell 5.1 은 `0x80000041` 을 부호 있는
    # Int32(-2147483583)로 읽어 변환 오류로 **조용히 실패**한다(2026-11-13 실제로 당함).
    $r = [Win32.PowerKeeper]::SetThreadExecutionState([uint32]2147483713)
    $powerKept = ($r -ne 0)
} catch {
    $powerKept = $false
}

$repoRoot  = Split-Path -Parent $PSScriptRoot
$stateDir  = Join-Path $repoRoot ".local-stack"
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force $stateDir | Out-Null }
$suffix    = if ($tag) { "-$tag" } else { "" }
$logPath   = Join-Path $stateDir ("rent-deposit-refill{0}.log"  -f $suffix)
$statePath = Join-Path $stateDir ("rent-deposit-refill{0}.json" -f $suffix)

function Write-Log([string] $line) {
    $msg = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $line
    Write-Output $msg
    try { Add-Content -Path $logPath -Value $msg -Encoding utf8 } catch { }
}

function Add-Months([string] $ym, [int] $delta) {
    $y = [int] $ym.Substring(0, 4); $m = [int] $ym.Substring(4, 2)
    $t = (Get-Date -Year $y -Month $m -Day 1).AddMonths($delta)
    return $t.ToString("yyyyMM")
}

# ---------------------------------------------------------------------------
# DB 접속 정보 — 읽기만 하고 출력하지 않는다. 실패해도 예외 타입만 알린다.
# ---------------------------------------------------------------------------
$db = $null
if (-not $noCleanup) {
    try {
        $yml = Get-Content "C:\developer\workspace\sj-lab-scheduler\src\main\resources\application.yml" -Raw
        $u = [regex]::Match($yml, 'url:\s*["'']?(jdbc:postgresql://[^\s"'']+)').Groups[1].Value
        $n = [regex]::Match($yml, 'username:\s*["'']?([^\s"''#]+)').Groups[1].Value
        $p = [regex]::Match($yml, 'password:\s*["'']([^"'']+)["'']').Groups[1].Value
        if (-not $p) { $p = [regex]::Match($yml, 'password:\s*([^\s"''#]+)').Groups[1].Value }
        $m = [regex]::Match($u, '^jdbc:postgresql://([^:/]+):(\d+)/([^?]+)')
        $db = @{ h = $m.Groups[1].Value; p = $m.Groups[2].Value; d = $m.Groups[3].Value; u = $n; pw = $p }
        if (-not ($db.h -and $db.p -and $db.d -and $db.u -and $db.pw)) {
            Write-Log "접속 정보를 모두 읽지 못했습니다 — 정리를 건너뜁니다(-noCleanup 과 같게 동작)"
            $db = $null
        } elseif (-not (Test-Path $psqlPath)) {
            Write-Log ("psql 을 찾지 못했습니다: {0} — 정리를 건너뜁니다" -f $psqlPath)
            $db = $null
        }
    } catch {
        Write-Log ("접속 정보 읽기 실패({0}) — 정리를 건너뜁니다" -f $_.Exception.GetType().Name)
        $db = $null
    }
}

# 그 달의 "보증금이 빈 쌍둥이 행"만 지우고 지운 건수를 돌려준다.
# 묶음 기준은 유니크 키에서 deposit 만 뺀 것. 짝이 없는 빈 행은 건드리지 않는다.
function Invoke-Cleanup([string] $ym) {
    if (-not $db) { return -1 }
    $y = [int] $ym.Substring(0, 4); $mo = [int] $ym.Substring(4, 2)
    $sql = @"
WITH d AS (
    DELETE FROM estate.apt_rent
    WHERE id IN (
        SELECT id FROM (
            SELECT id, deposit,
                   count(deposit) OVER (
                       PARTITION BY sgg_cd, umd_nm, jibun, apt_nm, exclu_use_ar, floor,
                                    deal_year, deal_month, deal_day,
                                    monthly_rent, contract_term, contract_type
                   ) AS real_cnt
            FROM estate.apt_rent
            WHERE deal_year = $y AND deal_month = $mo
        ) x
        WHERE x.deposit IS NULL AND x.real_cnt > 0
    )
    RETURNING 1
)
SELECT count(*) FROM d;
"@
    try {
        $env:PGPASSWORD = $db.pw
        $out = & $psqlPath -h $db.h -p $db.p -U $db.u -d $db.d `
                   -v ON_ERROR_STOP=1 -q -t -A -c $sql 2>&1
        $env:PGPASSWORD = $null
        $num = ($out | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
        if ($null -ne $num) { return [int] $num }
        Write-Log ("  정리 응답을 숫자로 읽지 못했습니다(출력은 숨김)")
        return -1
    } catch {
        $env:PGPASSWORD = $null
        Write-Log ("  정리 실패: {0}" -f $_.Exception.GetType().Name)
        return -1
    }
}

# 죽은 자리 정리. 잠금을 걸지 않으므로 사이트는 그대로 동작한다.
function Invoke-Vacuum([string] $why) {
    if (-not $db) { return }
    Write-Log ("  VACUUM ANALYZE 시작 ({0})…" -f $why)
    $t0 = Get-Date
    try {
        $env:PGPASSWORD = $db.pw
        & $psqlPath -h $db.h -p $db.p -U $db.u -d $db.d `
            -v ON_ERROR_STOP=1 -q -c "VACUUM (ANALYZE) estate.apt_rent;" | Out-Null
        $env:PGPASSWORD = $null
        Write-Log ("  VACUUM 완료 — {0:N1}분" -f ((Get-Date) - $t0).TotalMinutes)
    } catch {
        $env:PGPASSWORD = $null
        Write-Log ("  VACUUM 실패: {0}" -f $_.Exception.GetType().Name)
    }
}

# ---------------------------------------------------------------------------
# 재개: 이미 끝낸 달은 건너뛴다
# ---------------------------------------------------------------------------
$done = @{}
if (Test-Path $statePath) {
    try {
        $prev = Get-Content $statePath -Raw | ConvertFrom-Json
        foreach ($d in $prev.done) { $done["$d"] = $true }
        Write-Log ("이전 진행 상태를 읽었습니다 — 이미 끝낸 달 {0}개" -f $done.Count)
    } catch { Write-Log "진행 상태 파일을 읽지 못했습니다(처음부터 시작)" }
}

$totalMonths = 0
$cur = $fromYm
while ([int] $cur -ge [int] $toYm) { $totalMonths++; $cur = Add-Months $cur -1 }

Write-Log ("=== 전월세 보증금 복구 시작: {0} ~ {1} ({2}개월) · 정리 {3} · 절전막기 {4} ===" -f `
    $fromYm, $toYm, $totalMonths, $(if ($db) { "함께" } else { "안 함" }), $(if ($powerKept) { "켜짐" } else { "실패" }))

$cur = $fromYm
$idx = 0; $grandIns = 0; $grandDel = 0; $failures = 0; $sinceVacuum = 0
$startedAt = Get-Date

while ([int] $cur -ge [int] $toYm) {
    $idx++
    if ($done.ContainsKey($cur)) {
        Write-Log ("[{0}/{1}] {2} — 이미 끝남, 건너뜀" -f $idx, $totalMonths, $cur)
        $cur = Add-Months $cur -1
        continue
    }

    $t0 = Get-Date
    try {
        $url = "{0}/apis/housing/aptRents?from={1}&to={2}" -f $baseUrl, $cur, $cur
        $res = Invoke-RestMethod -Uri $url -TimeoutSec $timeoutSec
        $ins = [int] $res.inserted
        $skp = [int] $res.skipped
        $failures = 0
    } catch {
        $failures++
        Write-Log ("[{0}/{1}] {2} — 수집 실패({3}): {4}" -f `
            $idx, $totalMonths, $cur, $failures, $_.Exception.GetType().Name)
        if ($failures -ge $maxFailures) {
            Write-Log ("연속 {0}회 실패 — 멈춥니다. 스케줄러가 떠 있는지 확인하세요." -f $failures)
            break
        }
        Start-Sleep -Seconds 10
        continue   # 같은 달을 다시 시도
    }

    $del = Invoke-Cleanup $cur
    $sec = [math]::Round(((Get-Date) - $t0).TotalSeconds, 0)
    $grandIns += $ins
    if ($del -gt 0) { $grandDel += $del }
    $done[$cur] = $true

    $mins = [math]::Round(((Get-Date) - $startedAt).TotalMinutes, 1)
    $delTxt = if ($del -lt 0) { "정리안됨" } else { "{0}" -f $del }
    Write-Log ("[{0}/{1}] {2} — 추가 {3} · 정리 {4} · 건너뜀 {5} · {6}초 (누계 +{7}/-{8} · 경과 {9}분)" -f `
        $idx, $totalMonths, $cur, $ins, $delTxt, $skp, $sec, $grandIns, $grandDel, $mins)

    if ($skp -gt 0) {
        Write-Log ("  주의: {0}건의 요청을 건너뛰었습니다 — 이 달은 끝에 다시 받을 것" -f $skp)
    }

    @{ done = @($done.Keys | Sort-Object -Descending); lastYm = $cur
       totalInserted = $grandIns; totalDeleted = $grandDel } |
        ConvertTo-Json -Depth 3 | Set-Content -Path $statePath -Encoding utf8

    $sinceVacuum++
    if ($vacuumEveryMonths -gt 0 -and $sinceVacuum -ge $vacuumEveryMonths) {
        Invoke-Vacuum ("{0}개월 적재 뒤" -f $sinceVacuum)
        $sinceVacuum = 0
    }

    $cur = Add-Months $cur -1
}

$mins = [math]::Round(((Get-Date) - $startedAt).TotalMinutes, 1)
Write-Log ("=== 끝: 끝낸 달 {0}개 · 추가 {1}행 · 정리 {2}행 · {3}분 ===" -f `
    $done.Count, $grandIns, $grandDel, $mins)

if ($db) {
    Write-Log "통계 갱신(ANALYZE) 중…"
    try {
        $env:PGPASSWORD = $db.pw
        & $psqlPath -h $db.h -p $db.p -U $db.u -d $db.d -q -c "ANALYZE estate.apt_rent;" | Out-Null
        $env:PGPASSWORD = $null
        Write-Log "통계 갱신 완료"
    } catch {
        $env:PGPASSWORD = $null
        Write-Log ("통계 갱신 실패: {0}" -f $_.Exception.GetType().Name)
    }
} else {
    Write-Log "정리를 하지 않았습니다 — db\estate\estate_apt_rent_deposit_cleanup.sql 을 돌릴 것"
}

# 절전 막기 해제(ES_CONTINUOUS 만 남기면 원래대로 돌아간다)
if ($powerKept) { $null = [Win32.PowerKeeper]::SetThreadExecutionState([uint32]2147483648) }
