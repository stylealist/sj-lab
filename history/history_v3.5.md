# history v3.5 — 공개 API를 진짜로 쓸 수 있게 (외부 개방 + 대용량 차단)

- **날짜**: 2026-09-30
- **영향 저장소**: `sj-lab-apigateway`(CORS), `sj-lab-openapi`(카탈로그·문서), `sj-lab`(문서)
- **이전 버전**: [history_v3.4.md](history_v3.4.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| 공개 API 목록 | https://api.sj-lab.co.kr/open-api/catalog | 바뀐 내용이 보이는 곳 |
| API 센터 | https://sj-lab.co.kr/openapi/ | 눌러 보는 화면 |

## 실행한 프롬프트

```
현재 api 기능에서 추가하거나 보완해야할 부분이 있어?
커밋 푸시 진행한후에 1 -> 5 -> 2 순서로 진행해줘
```

## 먼저 점검했습니다

공개 API를 실제로 호출해 보고 코드·차트·DB를 확인해 **보완할 것 6가지**를 뽑았고,
그중 영향이 큰 순서로 세 개를 진행했습니다.

## 1. 외부 웹사이트에서 부를 수 있게 (가장 컸던 문제)

**전**: 남의 사이트에서 부르면 **403**. 공개 API인데 사실상 우리 도메인 전용이었습니다.

```
Origin: https://example.com   → 403
```

**후**: 공개 API 경로만 열었습니다.

| 경로 | 누가 부를 수 있나 |
|---|---|
| `/open-api/**` | **누구나** (GET·OPTIONS만, 쿠키 없이) |
| `/map/**` `/auth/**` 등 | 종전대로 sj-lab 도메인만 |

- 쿠키·로그인 정보는 주고받지 않습니다(`allowCredentials: false`). 공개 API는 `X-API-Key` 헤더만 받습니다.
- 설정에서 **공개 API 블록이 전체 블록보다 먼저** 와야 합니다. 순서가 바뀌면 다시 403이 됩니다(주석·문서에 남겼습니다).

## 2. 전국 데이터를 통째로 못 가져가게

공공데이터 6종(편의점·버스정류장·CCTV·약국·병원·관공서)에서 **화면 범위(`bbox`)를 필수로** 바꿨습니다.

```
GET /v1/convenience-store              → 400  필수 파라미터가 없습니다: bbox
GET /v1/convenience-store?bbox=...     → 200
```

왜: 범위 없이 부르면 전국을 통째로 만들어 응답이 **수십 MB**(실측 버스정류장 85MB · 병원 61MB)가 됩니다.
원천 호출이 20초 제한을 넘기고, **외부에 열어 둔 API라 한 사람이 서비스를 흔들 수 있습니다.**

- 시설물·행정구역 API는 영향 없습니다(그대로 동작).
- 활용 페이지는 예시값이 미리 채워져 있어 **바로 눌러도 정상**입니다.

## 3. 키 기능 — 켤 준비까지 확인했습니다 (남은 건 사람 손)

운영에서 키 발급·사용량이 **아직 꺼져 있습니다**(`/open-api/keys/status` → `ready: false`).
그래서 하루 1,000회 한도가 지금은 적용되지 않습니다.

제가 확인한 것 — **표·코드·차트가 서로 맞습니다**:

| 확인 | 결과 |
|---|---|
| 표 생성 스크립트 vs 코드가 쓰는 컬럼 | 일치 |
| 개발 DB의 실제 표 | 이미 있음 (키 9컬럼 · 사용량 7컬럼, 전부 일치) |
| 배포 차트의 Secret 연결 | 정상 |

**남은 3단계(순서대로)** — DB 권한·클러스터 접근이 필요해 제가 할 수 없습니다.

1. 운영 DB에 표 2개 생성 — `db/api/openapi_api_key.sql`, `db/api/openapi_api_usage.sql`
2. Secret 생성 — `openapi-db-credentials` (url · username · password)
3. 차트에서 `apiKey.enabled: true` → ArgoCD 동기화

⚠️ **순서를 지켜야 합니다.** Secret 없이 3번을 먼저 하면 파드가 기동에 실패합니다(의도된 안전장치).

## 바뀐 파일

| 저장소 | 파일 | 내용 |
|---|---|---|
| `sj-lab-apigateway` | `application.yml` | 공개 API 전용 CORS 블록 추가 |
| | `README.md` | CORS 절에 개방 범위·순서 주의 |
| `sj-lab-openapi` | `catalog/api-catalog.json` | 6종 `bbox` 필수, 설명 갱신, v1.0 → v1.1 |
| | `README.md` · `CLAUDE.md` | bbox 필수 이유, 브라우저 호출 가능 |
| `sj-lab` | `docs/system-architecture.md` | API 계약 표·공개 API 절·CORS 체크리스트. 옛 표기 2곳 정정 |

## 어떻게 확인했나

게이트웨이·공개 API를 **검증용 포트(8101·8111)에 따로 띄워** 확인하고 그 프로세스만 종료했습니다
(쓰고 계신 8100은 건드리지 않았습니다).

```
CORS  example.com → /open-api/catalog     200  (누구나 허용)
      example.com → /map/check            403  (종전대로 차단)
      localhost:4000 → /map/check         200  (기존 동작 유지)
사전요청  OPTIONS + X-API-Key              200  GET,OPTIONS 허용
          OPTIONS + POST                   403  (의도대로 차단)
bbox  없이 호출                            400  필수 파라미터가 없습니다: bbox
      주고 호출                            200
      시설물·행정구역                       200  (영향 없음)
테스트  게이트웨이 스모크 통과 · 공개 API 8건 통과
```
