# ============================================================================
# estate.apt_rent — 지정한 달의 "보증금이 빈 쌍둥이 행"만 정리
#
#   언제 쓰나: 보증금 복구 재적재를 **중간에 멈출 때**. 드라이버를 종료하면 스케줄러에 이미
#       들어간 그 달의 수집은 계속 끝나지만 **정리가 돌지 않아 쌍둥이 행이 남는다**
#       — 그러면 화면의 전월세 거래 건수가 그 달만 부풀어 보인다. 이 스크립트로 그 달을 마무리한다.
#
#   무엇을 지우나: 자연키에서 금액만 뺀 나머지가 같은 묶음 안에서, **금액이 들어간 짝이 있는
#       빈 행만** 지운다. 짝이 없는 빈 행은 건드리지 않는다. 자세한 근거는
#       `db/estate/estate_apt_rent_deposit_cleanup.sql` 에 있다.
#
#   대상 DB  : sjlab (개발 = 운영 동일 인스턴스) · 계정은 estate.apt_rent 소유자
#   접속정보 : scheduler 의 application.yml 에서 읽기만 하고 출력하지 않는다
#
#   보기: powershell -ExecutionPolicy Bypass -File scripts\estate-rent-cleanup-month.ps1 202103 201302
# ============================================================================
param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]] $months,                                      # YYYYMM 여러 개
    [string] $psqlPath = "C:\Program Files\PostgreSQL\15\bin\psql.exe"
)
$ErrorActionPreference = "Continue"

try {
    $yml = Get-Content "C:\developer\workspace\sj-lab-scheduler\src\main\resources\application.yml" -Raw
    $u = [regex]::Match($yml, 'url:\s*["'']?(jdbc:postgresql://[^\s"'']+)').Groups[1].Value
    $n = [regex]::Match($yml, 'username:\s*["'']?([^\s"''#]+)').Groups[1].Value
    $p = [regex]::Match($yml, 'password:\s*["'']([^"'']+)["'']').Groups[1].Value
    if (-not $p) { $p = [regex]::Match($yml, 'password:\s*([^\s"''#]+)').Groups[1].Value }
    $m = [regex]::Match($u, '^jdbc:postgresql://([^:/]+):(\d+)/([^?]+)')
    $h = $m.Groups[1].Value; $pt = $m.Groups[2].Value; $d = $m.Groups[3].Value
    if (-not ($h -and $pt -and $d -and $n -and $p)) { throw "접속 정보 부족" }
} catch {
    Write-Output ("접속 정보를 읽지 못했습니다: {0}" -f $_.Exception.GetType().Name)
    exit 1
}

foreach ($ym in $months) {
    if ($ym -notmatch '^\d{6}$') { Write-Output ("건너뜀(형식 오류): {0}" -f $ym); continue }
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
    $t0 = Get-Date
    try {
        $env:PGPASSWORD = $p
        $out = & $psqlPath -h $h -p $pt -U $n -d $d -v ON_ERROR_STOP=1 -q -t -A -c $sql 2>&1
        $env:PGPASSWORD = $null
        $num = ($out | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
        if ($null -ne $num) {
            Write-Output ("{0} — 지운 행 {1:N0} · {2:N0}초" -f $ym, [int] $num, ((Get-Date) - $t0).TotalSeconds)
        } else {
            Write-Output ("{0} — 응답을 숫자로 읽지 못했습니다(출력은 숨김)" -f $ym)
        }
    } catch {
        $env:PGPASSWORD = $null
        Write-Output ("{0} — 실패: {1}" -f $ym, $_.Exception.GetType().Name)
    }
}
