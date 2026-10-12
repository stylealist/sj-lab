<#
.SYNOPSIS
  운영 정적 사이트(허브 / 지도)가 각각 제 파일로 서빙되고 있는지 확인한다.

.DESCRIPTION
  허브(sj-lab-hub)와 지도(sj-lab-mapservice)는 웹서버의 같은 디렉터리를 공유한다.
      /home/kuber-volume/sj-lab-webserver/html        ← 허브
      /home/kuber-volume/sj-lab-webserver/html/map    ← 지도
  그래서 한쪽 배포 잡이 상위 디렉터리를 비우면 다른 쪽이 통째로 지워진다.
  게다가 nginx 가 `try_files $uri $uri/ /index.html` 로 SPA 폴백을 하므로,
  지도가 지워져도 /map/ 은 404 가 아니라 **허브 첫 화면을 200 으로** 돌려준다.
  허브·지도·API 활용 페이지·부동산 네 곳을 확인한다(배포 전인 곳의 404 는 실패로 세지 않는다).
  이 스크립트는 응답 본문의 표식으로 그 상태를 구분한다.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\check-prod-sites.ps1
  powershell -ExecutionPolicy Bypass -File scripts\check-prod-sites.ps1 -BaseUrl http://localhost:4000 -MapPath /
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = "https://sj-lab.co.kr",
  [string]$HubPath = "/",
  [string]$MapPath = "/map/",
  [string]$OpenapiPath = "/openapi/",
  [string]$EstatePath = "/estate/",
  [int]$TimeoutSec = 20
)

$ErrorActionPreference = "Stop"

# 각 사이트를 가려내는 표식 (index.html 에 반드시 들어 있는 문자열)
$hubMarkers = @("bundle")                                  # webpack 번들 스크립트(허브 자체 확인용)
# 하위 사이트 경로에서 "허브가 나왔는지" 가릴 때 쓰는 표식.
# "bundle" 은 활용 페이지·부동산도 webpack 이라 겹치므로 제목으로 가린다.
$hubOnlyMarkers = @("<title>SJ-LAB</title>")
$mapMarkers = @("js/auth-gate.js", "openlayers/ol.js")     # 로그인 게이트 + OpenLayers
$openapiMarkers = @("SJ-LAB OpenAPI")                        # 활용 페이지 제목
$estateMarkers = @("SJ-LAB 부동산 실거래")                   # 부동산 화면 제목(<title>)

$failCount = 0

function Get-Page {
  param([string]$Url)
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec $TimeoutSec
    # 본문을 **UTF-8로 직접 디코딩**한다. Windows PowerShell 5.1 은 Content-Type 에 charset 이
    # 없으면 ISO-8859-1 로 읽어 한글 표식이 깨진다 — 그 상태로 비교하면 정상인 사이트를
    # "표식 없음"으로 잘못 알린다(2026-10-12 부동산 제목에서 실제로 발생).
    $body = ""
    try {
      $bytes = $response.RawContentStream.ToArray()
      $body = [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
      $body = [string]$response.Content
    }
    return @{ ok = $true; status = [int]$response.StatusCode; body = $body }
  } catch {
    $status = 0
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode.value__ }
    return @{ ok = $false; status = $status; body = ""; error = $_.Exception.Message }
  }
}

function Test-Site {
  param(
    [string]$Label,
    [string]$Url,
    [string[]]$Expected,
    [string[]]$NotExpected = @(),
    # 아직 배포하지 않은 사이트는 404 가 정상이다(허브 폴백이면 =404 로 내보내도록 nginx 에 설정해 둠).
    # 그 경우 실패로 세지 않고 안내만 한다.
    [switch]$AllowMissing
  )

  $page = Get-Page -Url $Url
  if (-not $page.ok) {
    if ($AllowMissing -and $page.status -eq 404) {
      Write-Host ("  [미배포] {0,-6} {1} → 404 (아직 배포 전)" -f $Label, $Url) -ForegroundColor DarkGray
      return $true
    }
    Write-Host ("  [실패] {0,-6} {1} → 응답 없음/오류 (status={2})" -f $Label, $Url, $page.status) -ForegroundColor Red
    return $false
  }

  $missing = @($Expected | Where-Object { $page.body -notlike "*$_*" })
  $wrongSite = @($NotExpected | Where-Object { $page.body -like "*$_*" })

  # 아직 배포하지 않은 하위 사이트: nginx 의 =404 설정이 반영되기 전에는 404 대신
  # 허브 화면이 200 으로 온다. 자기 표식이 하나도 없고 허브 표식만 나오면 "미배포"로 본다.
  if ($AllowMissing -and $missing.Count -eq $Expected.Count -and $wrongSite.Count -gt 0) {
    Write-Host ("  [미배포] {0,-6} {1} → 200 이지만 허브 화면 (아직 배포 전)" -f $Label, $Url) -ForegroundColor DarkGray
    return $true
  }

  if ($missing.Count -eq 0 -and $wrongSite.Count -eq 0) {
    Write-Host ("  [정상] {0,-6} {1} → {2} ({3:N0} bytes)" -f $Label, $Url, $page.status, $page.body.Length) -ForegroundColor Green
    return $true
  }

  Write-Host ("  [실패] {0,-6} {1} → {2} ({3:N0} bytes)" -f $Label, $Url, $page.status, $page.body.Length) -ForegroundColor Red
  if ($missing.Count -gt 0) {
    Write-Host ("         표식 없음: {0}" -f ($missing -join ", ")) -ForegroundColor Red
  }
  if ($wrongSite.Count -gt 0) {
    # 지도 경로에서 허브 표식이 나오면 = 지도 파일이 지워져 SPA 폴백이 허브를 돌려준 것
    Write-Host ("         다른 사이트의 표식이 나옴: {0} — 파일이 지워졌을 수 있음" -f ($wrongSite -join ", ")) -ForegroundColor Red
  }
  return $false
}

Write-Host ""
Write-Host ("정적 사이트 점검: {0}" -f $BaseUrl)

if (-not (Test-Site -Label "허브" -Url ($BaseUrl.TrimEnd("/") + $HubPath) -Expected $hubMarkers)) { $failCount++ }
if (-not (Test-Site -Label "지도" -Url ($BaseUrl.TrimEnd("/") + $MapPath) -Expected $mapMarkers -NotExpected $hubOnlyMarkers)) { $failCount++ }
if (-not (Test-Site -Label "API" -Url ($BaseUrl.TrimEnd("/") + $OpenapiPath) -Expected $openapiMarkers -NotExpected $hubOnlyMarkers -AllowMissing)) { $failCount++ }
if (-not (Test-Site -Label "부동산" -Url ($BaseUrl.TrimEnd("/") + $EstatePath) -Expected $estateMarkers -NotExpected $hubOnlyMarkers -AllowMissing)) { $failCount++ }

Write-Host ""
if ($failCount -eq 0) {
  Write-Host "확인한 사이트가 모두 제 파일로 서빙 중입니다(배포 전인 곳은 404)." -ForegroundColor Green
  exit 0
}

Write-Host ("실패 {0}건 — 사이트가 지워졌다면 해당 Jenkins 잡을 다시 실행하면 복구됩니다." -f $failCount) -ForegroundColor Yellow
Write-Host "재발 방지는 docs/deploy-static-sites.md 참고 (배포 잡이 상위 디렉터리를 비우지 않게 할 것)." -ForegroundColor Yellow
exit 1
