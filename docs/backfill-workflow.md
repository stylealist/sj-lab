# 공공데이터 대량 백필 workflow

과거 기간을 한꺼번에 받아 오는 작업(backfill)의 **절차와 함정**을 정리한 문서입니다.
2026-10-06 ~ 10-08에 아파트 실거래(매매·전월세) 250개월을 받으면서 실제로 부딪힌 것만 적었습니다.
다른 공공데이터(약국·병원·버스 등)를 과거까지 받을 때도 같은 순서로 하면 됩니다.

관련 문서: 스키마·표는 `db/estate/estate_apt.sql`, 수집 코드 규칙은 `sj-lab-scheduler/CLAUDE.md`,
새 기능을 공개 API에 여는 절차는 `docs/openapi-expose-checklist.md`.

## 0. 시작 전에 확인할 것

| 확인 | 왜 |
|---|---|
| **대상 표에 자연키 유니크 인덱스가 있는가** | 없으면 같은 달을 다시 받을 때 중복이 쌓인다. 이게 백필의 전제다 |
| 매퍼가 `ON CONFLICT DO NOTHING` 인가 | 위와 한 쌍. 재수신이 안전해야 중간에 끊겨도 이어서 할 수 있다 |
| 적재 코드에 **기간 필터가 없는가** | 아래 "함정 1" — 이게 있으면 백필이 아예 불가능하다 |
| 서비스 키가 **운영 승인** 키인가 | 개발 키는 일일 한도가 작아 금방 429가 된다 |
| 예비 키가 있는가 | 한도가 떨어지면 자동 전환할 수 있다(`APIS_SERVICE_KEY_2`) |

## 1. 구성 요소

```
estate-backfill.ps1          드라이버 — 과거로 한 구간씩 내려가며 수집 엔드포인트를 호출
estate-backfill-watch.ps1    터미널 진행 화면(사람이 보는 용도)
estate-backfill-notify.py    구간 완료를 한 줄씩 알림(에이전트 감시용, 묶음 크기 인자)
estate-backfill-finish.py    완료를 감지해 스케줄러를 내리고 최종 결과를 파일로 기록
.local-stack/estate-backfill.json   진행 상황(커서·누계·멈춤 여부) — 끊겨도 여기서 이어진다
```

## 2. 띄우는 순서 (이 순서를 지킬 것)

```powershell
# 1) 스케줄러 — 응답이 올 때까지 기다린 뒤 다음으로
java -jar target\sj-lab-scheduler.jar --spring.profiles.active=local `
  --server.port=8120 --apis.request-delay-ms=50

# 2) 드라이버
powershell -ExecutionPolicy Bypass -File scripts\estate-backfill.ps1 `
  -chunkMonths 1 -baseUrl http://localhost:8120/scheduler

# 3) 완료 감시기 — 드라이버가 확실히 돌기 시작한 뒤에
python scripts\estate-backfill-finish.py
```

**순서를 바꾸면 사고가 난다.** 완료 감시기를 먼저 띄우면 "드라이버가 없다"를 완료로 보고
**기동 중인 스케줄러를 죽이고** 미완료 상태의 결과 파일을 써 버린다(2026-10-08 실제 발생).
반대로 멈출 때는 **완료 감시기 → 드라이버 → 스케줄러** 순으로 내린다.

## 3. 중간에 멈추고 재개하기

```powershell
# 진행 보기
powershell -ExecutionPolicy Bypass -File scripts\estate-backfill-watch.ps1

# 특정 구간 수에서 깔끔하게 멈추기(구간 경계에서 멈춰 반쯤 받은 달이 없게 한다)
python scripts\estate-backfill-stop-at.py <목표_구간_수>

# 재개 — 커서가 남아 있어 받은 구간은 건너뛴다
powershell -ExecutionPolicy Bypass -File scripts\estate-backfill.ps1 -chunkMonths 1 -baseUrl ...
```

- 구간 **중간**에 끊으면 그 달을 처음부터 다시 받는다(중복은 안 쌓이지만 시간이 아깝다).
- 하루 한도를 나눠 쓰려면 `-maxChunks 20` 처럼 구간 수를 끊는다.

## 4. 실제로 부딪힌 함정

### 함정 1 — 적재 코드의 "최근 N일" 필터 (가장 치명적)

`insertAptTrades()` 가 **오늘로부터 30일 안의 거래일만** 골라 넣고 있었다.
API 는 2006년 것까지 정상으로 돌려주는데 **코드가 받아 와서 버렸다.**

```
2026-05~08 응답:  있음(강남구 474·226·169·94건)
적재 결과:        0건
```

증상이 "API 가 데이터를 안 준다"로 보여 원인을 찾는 데 오래 걸렸다.
**백필을 시작하기 전에 적재 코드에 기간 필터가 있는지 반드시 확인할 것.**
중복 방지용으로 넣은 장치라면 유니크 인덱스로 대체하고 걷어낸다.

### 함정 2 — 서비스 키 이중 인코딩

키가 이미 URL 인코딩된 형태(`%` 포함)인데 코드가 또 인코딩해서 **403**이 났다.
`busRouteInfo()` 만 `%` 검사를 하고 있어서 **그 수집만 살아남아** "아파트만 멈춘 것"처럼 보였다.
실제로는 약국·병원·아파트 매매·전월세 **네 개가 2025-12부터 함께 멈춰 있었다.**
→ 키 인코딩은 `serviceKeyParam()` 한 곳만 쓴다.

### 함정 3 — 타임아웃이 없는 HTTP 호출

`HttpURLConnection` 에 `setConnectTimeout`/`setReadTimeout` 이 없어, 호출 제한에 걸린 뒤
상대가 응답을 끊자 스레드가 **영구히 대기**했다(40분간 아무 일도 일어나지 않음).
→ 연결 10초 · 읽기 30초를 반드시 설정한다.

### 함정 4 — 429를 빈 결과로 넘기기

429를 그냥 실패로 처리하면 호출한 쪽이 **"그 달에 데이터가 없다"로 받아들여 조용히 건너뛴다.**
그러면 멈춤 규칙(연속 0건)이 잘못 발동하고 받지도 못한 과거 구간을 통째로 지나친다.
→ 429·5xx 는 2→8→18→32초 백오프로 재시도하고, 끝까지 실패하면 **건너뛴 횟수(`skipped`)를 세어
응답에 담는다.** 드라이버는 `skipped > 0` 이면 **커서를 전진시키지 않고** 20분 뒤 같은 구간을 다시 받는다.

### 함정 5 — 한도는 키마다 · 엔드포인트마다 따로

같은 키로 **매매는 429인데 전월세는 200**이 나왔다. 다른 키로는 매매도 200이었다.
"키가 막혔다"를 전체 차단으로 보면 안 되고, **쓰려는 엔드포인트마다** 확인해야 한다.
→ 수집 시작 전에 그 엔드포인트로 한 건만 찔러 보고(`numOfRows=1`) 되는 키를 고른다.
되는 키가 없으면 주 키로 진행해 429 가 `skipped` 로 올라오게 한다(조용히 넘어가지 않도록).

### 함정 6 — 로그 쓰기 실패로 드라이버가 죽음

`Add-Content` 가 감시 스크립트와 파일을 동시에 다루다 한 번 실패했고,
`$ErrorActionPreference = "Stop"` 때문에 **드라이버가 통째로 죽어** 38개월 남은 상태에서 멈췄다.
→ 로그 쓰기는 몇 번 재시도하고 끝까지 안 되면 **조용히 넘어간다.** 로그보다 수집이 중요하다.

### 함정 7 — 클라이언트 타임아웃은 커서가 전진한다

드라이버의 `Invoke-RestMethod` 가 타임아웃되면 `skipped` 와 달리 **커서가 그냥 전진**해
그 달 데이터가 빠진다(실제로 `201509` 매매가 이렇게 빠졌다).
→ 백필이 끝난 뒤 로그에서 `호출 실패` 를 찾아 **그 달만 다시 받는다.**

```powershell
Select-String -Path .local-stack\estate-backfill.log -Pattern "호출 실패"
```

### 함정 8 — 수집 엔드포인트를 "기동 확인용"으로 부르지 말 것

스케줄러가 떴는지 보려고 `/apis/housing/aptRents?from=200001&to=200001` 을 호출하면
**그 달 수집이 실제로 돌아간다**(시군구 251개 호출). 거기에 짧은 타임아웃(`curl -m 3`)으로
재시도 루프를 돌리면 **서버에서는 수집이 5개가 동시에 돌고** 호출 한도에 걸려
`재시도 4번이 모두 실패` 가 쏟아진다(2026-11-12 실제 발생. 데이터 없는 달이라 적재 피해는 없었다).

또한 `aptRentsBackfill` 은 건너뛴 건수를 **static 카운터**(`DataConverter.resetSkippedCount()`)로
세므로, **두 백필을 동시에 돌리면 `skipped` 숫자가 서로 섞인다.** 한 번에 하나만 돌릴 것.

→ 기동 확인은 로그로 한다(수집을 일으키지 않는다).

```powershell
Select-String -Path .local-stack\scheduler-8130.log -Pattern "Started SchedulerRestApplication"
```

### 함정 9 — 보증금·금액은 쉼표 때문에 조용히 null 이 된다

원천은 금액을 `"48,000"` 처럼 **천 단위 쉼표가 들어간 문자열**로 준다. 쉼표를 떼지 않으면
숫자 변환이 실패해 **예외 없이 조용히 null** 이 되고, **쉼표가 없는 1,000 미만 값만 저장된다.**
전월세 보증금이 그렇게 들어가 **1,104만 행(93%)이 빈 값**이 됐다(2026-10-12 발견).

- 진단법: `max(금액컬럼)` 이 **999** 에서 멈춰 있으면 이 함정이다.
- 처리는 `DataTypeUtil.numeric()` 에 들어 있다 — 새 숫자 컬럼은 `toLong`/`toInt`/`toDecimal` 로 받을 것.
- **재수집으로 고쳐지지만 그냥 받으면 중복이 된다** — 유니크 키에 금액이 들어 있어 "빈 금액 행"과
  "제대로 받은 행"이 다른 키가 되기 때문이다. 재수집 뒤에 빈 쪽을 지워야 한다
  (`db/estate/estate_apt_rent_deposit_cleanup.sql`, 드라이버는 `scripts/estate-rent-deposit-refill.ps1`).

### 함정 10 — 1,000만 행이 넘으면 속도가 계단처럼 떨어진다 (VACUUM 으로는 안 고쳐진다)

보증금 복구 재적재(2026-11-12) 중 **달당 소요가 1.6분 → 12분으로 갑자기 4배** 뛰었다.
점점 느려진 것이 아니라 **2023-01(3.3분)과 2022-12(13.6분) 사이에서 계단처럼** 바뀌었고,
특정 지역이 아니라 시군구당 0.62초 → 2.86초로 **고르게** 느려졌다.

**죽은 자리(dead tuple) 때문이 아니다.** 그렇게 짐작해 `VACUUM (ANALYZE)` 를 돌려
197만 개(14.4%)를 0으로 만들었는데(16.5분 소요) **12분 → 11분, 사실상 그대로였다.**

진짜 원인은 VACUUM 로그에 있었다.

```
avg read rate: 5.5 MB/s
buffer usage: 142,647 hits / 569,743 misses   ← 대부분 디스크에서 읽음
WAL usage: 1,407,046,607 bytes
```

표 5GB 중 **중복검사 인덱스만 2.4GB**(`ux_apt_rent_natural`, 13개 컬럼)인데 DB 메모리에 들어가지
않는다. 행을 넣을 때마다 `ON CONFLICT` 가 그 인덱스를 디스크에서 뒤진다. 초반이 빨랐던 것은
캐시에 여유가 있었기 때문이고, **여유가 사라지는 지점이 그 계단**이다. 저장장치 속도의 한계다.

→ **대책은 셋뿐이고, VACUUM 은 그중에 없다.**
  1. 그냥 기다린다(무인으로 돌고 끊겨도 재개된다). **최신 달부터 과거로** 내려가게 짜서
     중간에 멈춰도 값진 구간이 먼저 끝나게 할 것.
  2. 받을 기간을 줄인다.
  3. 조회용 인덱스를 임시로 뗀다(행마다 쓰는 인덱스 5→3개, 25~30% 단축). 운영 중인 사이트가
     그 인덱스를 쓰면 그동안 느려진다 — 맞바꾸는 선택이다.

**계획을 세울 때 초반 속도로 전체를 추산하지 말 것.** 1.6분/월로 191개월을 잡으면 5시간이지만
실제는 25시간이었다.

## 4-1. 전월세 보증금 복구 — 멈추고 이어서 하기 (2026-11-12 시작, 진행 중)

보증금이 빈 1,104만 행을 되살리는 재적재다. 배경과 원인은 위 **함정 9**, 속도는 **함정 10**.

```powershell
# 1) 스케줄러 (CCTV 는 기동 시 1회 수집되는 것이 정상)
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
& "$env:JAVA_HOME\bin\java.exe" -jar C:\developer\workspace\sj-lab-scheduler\target\sj-lab-scheduler.jar `
  --spring.profiles.active=local --server.port=8130 --apis.request-delay-ms=50 `
  --eureka.client.enabled=false --eureka.client.register-with-eureka=false --eureka.client.fetch-registry=false

# 2) 기동 확인 — 로그로 한다(수집 주소로 부르면 수집이 돌아간다. 함정 8)
Select-String -Path .local-stack\scheduler-8130.log -Pattern "Started SchedulerRestApplication"

# 3) 드라이버 둘을 나란히 (기간이 겹치지 않게 · tag 를 다르게)
powershell -ExecutionPolicy Bypass -File scripts\estate-rent-deposit-refill.ps1 -fromYm 202103 -toYm 201401
powershell -ExecutionPolicy Bypass -File scripts\estate-rent-deposit-refill.ps1 -fromYm 201302 -toYm 201101 -tag b -vacuumEveryMonths 0

# 4) 진행 보기
Get-Content .local-stack\rent-deposit-refill.log   -Tail 5
Get-Content .local-stack\rent-deposit-refill-b.log -Tail 5
```

- **끝낸 달은 상태 파일(`.local-stack\rent-deposit-refill*.json`)을 보고 건너뛴다** — 같은 명령을
  다시 줘도 안전하다. `-fromYm` 을 넉넉히 과거로 잡아도 이미 한 달은 지나간다.
- **멈출 때**: 드라이버를 종료한 뒤 **스케줄러에 이미 들어간 그 달의 수집이 끝나기를 기다리고**
  그 달만 정리(DELETE)한 다음 스케줄러를 내린다. 안 그러면 그 달에 쌍둥이 행이 남아
  **화면의 거래 건수가 부풀어 보인다.**
- **진행 중인 달 확인**: `Select-String -Path .local-stack\scheduler-8130.log -Pattern "대상 1개월"` 의 마지막 줄.
- **`skipped` 숫자는 나란히 돌릴 때 믿지 말 것**(static 카운터). 달별로는 이렇게 센다.

```powershell
Select-String -Path .local-stack\scheduler-8130.log -Pattern "재시도 4번이 모두 실패" |
  ForEach-Object { [regex]::Match($_.Line, "DEAL_YMD=(\d+)").Groups[1].Value } |
  Group-Object | Select-Object Name, Count
```

**남은 구간(2026-11-13 11:00 기준)**: `201801 ~ 201509`(29개월) · `201507 ~ 201401`(19개월) ·
`202610` 다시 받기(6개 시군구 건너뜀). 그 밖의 전 기간(2011-01 ~ 2026-11)은 **복구 완료**.

```powershell
# 다음에 이어서 할 때 (두 드라이버가 가운데서 만난다)
powershell -ExecutionPolicy Bypass -File scripts\estate-rent-deposit-refill.ps1 -fromYm 201801 -toYm 201401
powershell -ExecutionPolicy Bypass -File scripts\estate-rent-deposit-refill.ps1 -fromYm 201507 -toYm 201401 -tag b -vacuumEveryMonths 0
```

### 함정 11 — 밤새 돌릴 때 Modern Standby 로 멈춘다

절전 시간을 "없음(0)"으로 둬도 요즘 노트북은 **Modern Standby** 로 알아서 저전력 상태에 들어간다.
그러면 드라이버와 스케줄러가 멈추고, 멈춘 사이 DB 가 유휴 연결을 끊어
`FATAL: terminating connection due to administrator command` 로 그 달 수집이 죽는다.
2026-11-12 밤에 실제로 당했다(밤새 네 번 절전 · Hikari 가 `clock leap detected (6h13m)` 를 남김).

→ 긴 작업 전에 `scripts\keep-awake.ps1` 을 띄울 것. 전원 설정을 바꾸지 않고 그 프로세스가 살아
있는 동안만 절전을 막는다(드라이버에도 같은 장치가 들어 있다).

```powershell
Start-Process powershell -ArgumentList "-ExecutionPolicy","Bypass","-File","scripts\keep-awake.ps1","-hours","20" -WindowStyle Hidden
```

**주의**: `SetThreadExecutionState` 에 넘기는 플래그는 **반드시 `[uint32]` 로 캐스트**할 것.
Windows PowerShell 5.1 은 `0x80000041` 을 부호 있는 Int32 로 읽어 변환 오류로 **조용히 실패**한다
(오류도 없이 "켜짐"으로 보인다). 반환값이 0 이 아닌지로 성공을 확인할 것.

### 함정 12 — 느린 원인은 디스크가 아니라 **강제 체크포인트**일 수 있다

`max_wal_size` 가 기본값(1GB)이면 대량 적재 중 WAL 이 2분마다 차고, 그때마다 **강제 체크포인트**가
돈다. 체크포인트 직후에는 변경 페이지가 통째로(full page image) WAL 에 다시 기록되므로 쓰기량이
몇 배로 불어난다. 2026-11-13 실측(가동 76분).

```
정상(시간) 체크포인트     4 회
강제 체크포인트         37 회     ← 2분마다
체크포인트 쓰기 시간  3,162 초     ← 가동 시간의 70%
```

확인 쿼리와 처방은 `db/estate/estate_db_wal_tuning.sql`. **둘 다 재시작 없이 바뀐다.**

```sql
SELECT num_timed, num_requested FROM pg_stat_checkpointer;  -- requested 가 크면 이 함정
```

적용 결과(`max_wal_size` 1GB→3GB · `wal_compression` on): **강제 체크포인트 37회 → 0회**.
다만 **속도는 15% 만 빨라졌다** — 남은 벽은 캐시였다(아래).

### 함정 13 — `shared_buffers` 가 작으면 속도가 5배씩 흔들린다

이 DB 는 `shared_buffers` 가 **128MB** 인데 전월세 표의 중복검사 인덱스 하나가 **2.4GB** 다.
적중률은 94.9% 로 좋아 보이지만 조회가 9,400만 번이라 **빗나간 5%가 484만 번의 디스크 읽기**가
되고, 초당 약 4MB(이 디스크의 한계)에 묶인다.

그래서 **DB 를 재시작한 직후에는 5배 빠르다가 300만 행쯤 넣으면 다시 느려진다**(2026-11-12·13
양일 모두 같은 양상). 하드웨어가 빨라진 것이 아니라 그때 필요한 부분이 캐시에 있었을 뿐이다.

→ 근본 해결은 `shared_buffers` 를 1~2GB 로 올리는 것. **`context = postmaster` 라 재시작이
필요**하고 k8s 차트의 메모리 제한과 함께 봐야 하므로, 사용자와 시점을 정해 따로 진행할 것.
그 전에는 **초반 속도로 전체를 추산하지 말 것** — 1.5분/월로 잡으면 5시간, 실제는 10분/월이었다.

## 5. 속도에 대해 (측정으로 확인한 것)

병목은 **API 가 아니라 DB 적재**다. 로그 시각으로 나눠 재면 이렇게 나온다.

```
DB 적재   433회 · 평균 1.74초   ← 합계 12.6분
API 응답   70회 · 평균 0.09초   ← 합계 0.1분
```

| 손댄 것 | 효과 |
|---|---|
| 호출 간격 300ms → 50ms | 초기에는 체감 없었고, 데이터가 적은 구간에서만 이득 |
| 배치 크기 올리기 | **효과 없음.** 1000건당 단가가 배치 수와 무관하게 일정했다. 게다가 컬럼 33개라 파라미터 상한(65,535) 때문에 1,985 이상 올릴 수 없다 |
| 조회용 인덱스 임시 제거 | **가장 효과적**(행마다 인덱스 기록 5개 → 2개). 단 1,000만 행 넘는 표에서는 `DROP INDEX` 자체가 오래 걸려 중단한 적 있음 |

행당 비용은 **표가 커지면서 올라간다**(4.1분/월 → 12분/월). 즉 일찍 받을수록 빠르다.
오래 걸릴 작업이면 **조회용 인덱스를 떼고 시작해 끝난 뒤 다시 만드는 것**을 권한다.

```sql
-- 시작 전 (유니크 인덱스는 반드시 남길 것)
DROP INDEX IF EXISTS estate.ix_apt_trade_region_period;  -- 등 조회용만
-- 끝난 뒤
\i db/estate/estate_apt.sql   -- CREATE INDEX IF NOT EXISTS 라 안전
```

## 6. 끝난 뒤 할 일

1. `.local-stack/estate-backfill-final.md` 확인(완료 감시기가 기록)
2. 로그에서 `호출 실패` 를 찾아 **빠진 달 다시 받기**(함정 7)
3. 조회용 인덱스를 뗐다면 **다시 만들기**
4. 적재 결과를 연도별로 세어 **빈 구간이 없는지** 확인

```sql
select deal_year, count(*) from estate.apt_trade group by deal_year order by deal_year;
```

## 7. 이번 작업 기록 (2026-10-06 ~ 10-12)

| 항목 | 값 |
|---|---|
| 대상 | 아파트 매매(2006~) · 전월세(2011~) |
| 범위 | 2026-10 부터 과거로 1개월씩, 12개월 연속 0건이면 멈춤 |
| 결과 | **매매 9,911,036건(250개월 완비) · 전월세 11,494,802건** · 합계 8.7 GB |
| 걸린 시간 | 실제 수집 약 20시간(3일에 걸쳐) |
| 중단 | API 일일 한도 2회, 로그 오류 1회, 재기동 순서 실수 1회 — 모두 커서로 복구 |
| 빠진 구간 | `201509` 매매(클라이언트 타임아웃) → 완료 후 재수신해 50,278건 채움 |

**끝난 뒤 점검이 실제로 한 달을 잡아냈습니다.** 연도별 개월 수를 세어 2015년만 11개월인 것을
발견하고 그 달을 다시 받았습니다. 6절의 점검 쿼리를 건너뛰지 말 것.
