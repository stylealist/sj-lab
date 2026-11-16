# ============================================================================
# estate.apt_rent 죽은 자리 정리(VACUUM ANALYZE)
#
#   왜: 보증금 복구 중 한 달마다 수만 행을 지우면 "죽은 자리"가 빠르게 쌓여,
#       197만 개(14.4%)에서 **달당 적재가 1.6분 → 12분으로 4배 느려졌다**(2026-11-12 실측).
#       새 행마다 중복검사 인덱스(`ux_apt_rent_natural`, 2.4GB)를 뒤지는데 읽을 페이지가 늘기 때문.
#
#   대상 DB  : sjlab (개발 = 운영 동일 인스턴스) · 계정은 estate.apt_rent 소유자
#   접속정보 : scheduler 의 application.yml 에서 읽기만 하고 출력하지 않는다
#   성격     : 평범한 VACUUM 은 **잠금을 걸지 않아** 사이트는 그대로 동작한다(조회가 다소 느려질 수 있음).
#              `VACUUM FULL` 은 쓰지 않는다 — 그건 표를 통째로 잠근다.
#
#   보기: powershell -ExecutionPolicy Bypass -File scripts\estate-rent-vacuum.ps1
# ============================================================================
param(
    [string] $table = "estate.apt_rent",
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

$t0 = Get-Date
Write-Output ("[{0}] VACUUM (ANALYZE) {1} 시작" -f (Get-Date -Format "HH:mm:ss"), $table)
try {
    $env:PGPASSWORD = $p
    & $psqlPath -h $h -p $pt -U $n -d $d -v ON_ERROR_STOP=1 `
        -c "VACUUM (ANALYZE, VERBOSE) $table;"
    $env:PGPASSWORD = $null
    Write-Output ("[{0}] 완료 — {1:N1}분" -f (Get-Date -Format "HH:mm:ss"), ((Get-Date) - $t0).TotalMinutes)
} catch {
    $env:PGPASSWORD = $null
    Write-Output ("실패: {0}" -f $_.Exception.GetType().Name)
    exit 1
}
