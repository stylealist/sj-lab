# 아파트 단지 좌표 받기 (지오코딩) — 절차와 함정

> 핀 지도를 만들기 위한 **좌표 수집** 작업입니다. 왜 필요한지와 API 선택 근거는
> `docs/estate-map-plan.md`, 과거 대량 수집에서 겪은 함정은 `docs/backfill-workflow.md` 를 봅니다.
> 2026-10-14 작성 — 코드는 준비돼 있고 **키 발급만 남았습니다**.

## 한 줄 요약

거래 2,100만 건이 아니라 **단지 44,581개**의 좌표만 구하면 `apt_seq` 로 모든 거래에 붙습니다.

## 0. 준비물 (사람이 하는 일)

| 준비물 | 내용 |
|---|---|
| **표 만들기** | `db/estate/estate_apt_complex.sql` — DB 담당자가 실행 |
| **행안부 키** | 도로명주소 **좌표제공 API** 승인키(무료). [business.juso.go.kr](https://business.juso.go.kr) 에서 신청 |
| VWorld 키 (선택) | [vworld.kr](https://www.vworld.kr) 오픈API 인증키. 1순위가 실패한 건을 지번으로 메움 |
| 키 주입 | scheduler 환경변수 `JUSO_CONFM_KEY`(필수) · `VWORLD_API_KEY`(선택) — **저장소에 적지 말 것** |

> 키가 없어도 서비스는 정상입니다. 좌표 받기만 "키 없음"으로 답하고 아무것도 바꾸지 않습니다.

## 1. 단지 긁어오기 (좌표 없이)

거래 표에서 단지를 뽑아 단지 마스터에 넣습니다. **여러 번 돌려도 이미 받아 둔 좌표는 지워지지
않습니다**(주소·건수만 갱신).

```
powershell -ExecutionPolicy Bypass -File scripts\estate-geocode.ps1 -Sync
```

## 2. 좌표 채우기

```
powershell -ExecutionPolicy Bypass -File scripts\estate-geocode.ps1 -Rounds 50
powershell -ExecutionPolicy Bypass -File scripts\estate-geocode.ps1 -SggCd 11680 -Rounds 5   # 한 지역만 먼저
powershell -ExecutionPolicy Bypass -File scripts\estate-geocode.ps1 -StatsOnly               # 진행 상황만
```

- **거래가 많은 단지부터** 받습니다(화면에 먼저 보일 곳).
- **상태가 DB 에 있어 끊겨도 그냥 다시 돌리면 이어집니다** — 커서 파일이 없습니다.
- 실패한 단지는 상태가 남아 다음 실행에서 다시 시도됩니다(3회까지).

## 3. 좌표를 구하는 두 가지 길

| 순서 | 방법 | 쓰는 값 | 좌표계 |
|---|---|---|---|
| 1 | **행안부 좌표제공 API** | 우리가 가진 **코드를 그대로 조립**(`admCd`·`rnMgtSn`·`udrtYn`·`buldMnnm`·`buldSlno`) | EPSG:5179 |
| 2 | VWorld 지오코더 | 지번 문자열(`읍면동 + 지번`) | EPSG:4326 |

- 1번은 주소 문자열 매칭이 아니라 코드 조립이라 **오타·별칭으로 깨지지 않습니다**(보유율 99.7%).
- **좌표계가 다릅니다.** 그대로 넣으면 엉뚱한 곳에 찍히므로, 배치가 원 좌표계를 함께 넘기고
  PostGIS 가 3857(지도 뷰)과 4326(사람이 확인용)으로 변환합니다.
- 전월세에만 있는 단지(3,069개)는 법정동코드가 없어 2번으로 처리됩니다.

## 4. 미리 막아 둔 함정

과거 대량 수집에서 실제로 당한 것들입니다 — 같은 실수를 반복하지 않도록 코드에 넣었습니다.

| 함정 | 어떻게 막았나 |
|---|---|
| **타임아웃이 없어 한 건에서 수십 분 멈춤** | 연결 5초 · 읽기 10초 고정 |
| **한도 초과를 빈 결과로 넘겨 조용히 구멍** | 한도로 판단되면 **그 자리에서 중단**하고 `quotaExceeded` 를 알림. 드라이버는 기다렸다가 같은 자리에서 재개 |
| 클라이언트가 끊겼는데 커서만 전진 | **커서를 쓰지 않음** — 상태가 DB 에 있어 구조적으로 불가능 |
| 로그 오류로 드라이버 사망 | 로그 기록 실패를 무시하고 계속 |
| 키가 로그·DB 에 남음 | 실패 사유는 **종류 이름만** 저장, 주소 로그에 키를 싣지 않음 |
| 같은 단지를 끝없이 재시도 | 3회까지만 시도하고 그 뒤에는 건너뜀 상태로 |

## 5. 확인

```sql
SELECT geocode_status, count(*) FROM estate.apt_complex GROUP BY geocode_status;
SELECT count(*) FILTER (WHERE geom IS NOT NULL) AS 좌표있음, count(*) AS 전체 FROM estate.apt_complex;

-- 눈으로 확인: 강남구 단지 몇 개가 서울 안에 찍혔는지
SELECT apt_nm, round(lon::numeric, 5) AS lon, round(lat::numeric, 5) AS lat
FROM estate.apt_complex WHERE sgg_cd = '11680' AND geom IS NOT NULL LIMIT 5;
```

서울이면 `lon` 이 126~127, `lat` 이 37 언저리여야 합니다. 값이 수십만 단위면 **좌표계 변환이
빠진 것**입니다.

## 6. 그다음 (좌표가 모이면)

1. `estate.v_apt_complex_geojson` 뷰 + 화면 영역(bbox) 조회 API — 지도 백엔드와 같은 패턴
2. 지도 화면 — 클러스터·핀. **핀 라벨(평형·가격)은 이미 만들어 둔 단지 API 로 바로 나옵니다**
3. 단지 부가정보(세대수·용적률)는 공동주택 기본정보(K-apt)를 붙입니다

## 주의

- scheduler 를 **로컬에서 띄우면 운영 DB 에 씁니다**(개발=운영 DB). 반드시 확인 후 실행하세요.
- 좌표 수집은 cron 에 넣지 않았습니다 — 한 번 받으면 끝나는 작업이고, 하루 한도 때문에
  사람이 보면서 나눠 돌리는 편이 안전합니다.
