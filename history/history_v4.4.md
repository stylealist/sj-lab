# history v4.4 — 부동산 조회 서버를 Spring 으로 따로 분리 (+ 전월세 보증금 적재 버그 발견)

- **날짜**: 2026-10-12
- **영향 저장소**: `sj-lab-estate`(신규), `sj-lab-estate-web`, `sj-lab-apigateway`, `fast-api-ai`, `sj-lab-scheduler`, `sj-lab`
- **이전 버전**: [history_v4.3.md](history_v4.3.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| 부동산 실거래 (로컬) | http://localhost:4200 | 화면 |
| 부동산 조회 API (게이트웨이) | http://localhost:8100/estate/status | 새 주소 |
| 부동산 조회 API (직접) | http://localhost:8120/estate/apt/meta | 새 서비스 |

## 실행한 프롬프트

```
fast-api-ai는 ai쪽의 기능들을 넣을거기때문에 spring서버로 따로 만들어주고
모두 만든후에 프론트 백엔드 모두 commit push 해줘
```

## 1. 부동산 조회 서버를 따로 만들었습니다

`fast-api-ai`(파이썬)에 들어 있던 부동산 조회를 **`sj-lab-estate`(Spring Boot)** 로 옮겼습니다.
`fast-api-ai` 는 이제 AI 기능만 담습니다.

| | 전 | 후 |
|---|---|---|
| 조회 서버 | `fast-api-ai` (FastAPI) | **`sj-lab-estate`** (Spring Boot 3.3.2 + MyBatis) |
| 주소 | `/fast-api-ai/estate/**` | **`/estate/**`** |
| 로컬 포트 | 8000 | **8120** |

**응답은 한 글자도 바꾸지 않았습니다.** 목록은 `{"items": [...]}`, 오류는
`{"detail": {"code", "message"}}`, 항목 키는 DB 컬럼명 그대로입니다. 그래서 화면은 **부르는 주소
한 줄만** 바꿨습니다. (결과를 DTO 가 아니라 Map 으로 받는 이유도 이것입니다 — DTO 로 받으면
스프링이 키를 camelCase 로 바꿔 내보내 화면을 전부 고쳐야 합니다.)

옮기면서 지켠 것:

- **접속 정보가 없어도 서버는 뜹니다.** 그 상태에서 조회만 503 이고 `/estate/status` 는
  "준비되지 않았다"로 답합니다 — 기동을 막으면 화면이 그 사실조차 알릴 수 없습니다.
- **커넥션을 읽기 전용으로** 엽니다(적재는 scheduler 담당). 실수로 쓰기 SQL 이 들어가면
  조용히 성공하는 대신 DB 가 거부합니다.
- 느린 조회를 만들던 두 가지(기간을 계산식으로 비교 · 건수를 정확히 세기)는 **같은 방식으로
  피했습니다**. 새 서버에서도 요약 0.1초, 지역 순위 1.5초입니다.

옛 파이썬 코드는 지우지 않고 `trash/2026-10-12/fast-api-ai/` 로 옮겼습니다.

## 2. 그 과정에서 전월세 보증금 적재 버그를 찾았습니다

새 서버로 같은 값을 확인하다가 **전월세 보증금이 거의 비어 있는 것**을 발견했습니다.

| 확인(2026년 데이터 53만 건) | 결과 |
|---|---|
| 보증금이 들어간 건수 | **33,946건 (6.4%)** |
| 보증금 최댓값 | **999** (만원) |
| 월세 최댓값 | **998** (만원) |

원인은 **천 단위 쉼표**였습니다. 공공데이터는 금액을 `"85,000"` 처럼 주는데, 숫자로 바꾸는
공통 함수가 쉼표를 떼지 않아 **변환이 실패하면 조용히 비워 두고** 넘어갔습니다. 그래서 쉼표가
없는 1,000 미만 값만 저장됐습니다. 매매 금액은 받는 쪽에서 쉼표를 따로 떼고 있어 멀쩡했습니다.

- **고쳤습니다**(`sj-lab-scheduler` 의 숫자 변환 함수가 쉼표·공백을 떼고 변환).
  앞으로 받는 데이터는 정상입니다.
- **이미 쌓인 과거 데이터는 다시 받아야 합니다** — 전월세만, 약 250개월. 언제 돌릴지는
  정해 주시면 백필 도구(`scripts/estate-backfill.ps1`)로 진행하겠습니다.
- 그때까지 화면의 **전세 보증금 추세는 비어 보입니다**(건수·월세는 정상).

## 3. 확인

로컬에서 새 경로로 전부 확인했습니다.

| 확인 | 결과 |
|---|---|
| 새 서버 직접(8120) 7개 엔드포인트 | 모두 200 |
| 게이트웨이(8100) `/estate/**` | 모두 200 |
| 준비 중 종류(`offi`) · 모르는 종류 · 잘못된 기간 | 503 · 400 · 400 |
| 화면(4200) → 프록시 → 게이트웨이 | 200 |
| `fast-api-ai` 재기동 후 | `/test/health` 200 · 옛 부동산 경로 404(제거 확인) |
| 응답 키·한글 인코딩 | 옛 응답과 동일 · UTF-8 정상 |

## 4. 바뀐 파일

| 저장소 | 파일 | 내용 |
|---|---|---|
| `sj-lab-estate` | 전체 | **신규 저장소** — pom, 설정, 컨트롤러·서비스·매퍼(XML), 예외 처리, Dockerfile, README, 규칙 문서 |
| `sj-lab-apigateway` | `application.yml`, `README.md` | `/estate/**` → `lb://SJ-LAB-ESTATE` 라우트 |
| `sj-lab-estate-web` | `src/api.js`, `webpack.config.js`, `components/Contact.js`, 문서 | 부르는 주소를 `/estate` 로, 프록시도 함께 |
| `fast-api-ai` | `main.py`, `core/config.py`, `requirements.txt`, `CLAUDE.md` | 부동산 라우터·DB 설정·psycopg 의존성 제거(AI 전용으로) |
| `sj-lab-scheduler` | `util/DataTypeUtil.java` | 숫자 변환 시 쉼표 제거(위 버그) |
| `sj-lab` | `docs/*`, `README.md`, `scripts/local-stack.ps1`, `history/history_v4.4.md` | 구성도·포트·API 계약·저장소 표, 로컬 기동에 8120 추가 |

## 남은 이야기

- **운영 배포**: Helm 차트(`sj-lab-k8s-manifests`)와 Jenkins 잡, 운영 DB Secret 이 필요합니다(부동산 화면도 아직 배포 전).
- **전월세 보증금 재수집** 시점 결정이 필요합니다(위 2번).
- 전국 조회 속도는 집계 스크립트(담당자 실행)로 해결됩니다.
- 오피스텔·빌라는 수집·표부터 필요합니다.
