# DB 스크립트 (DDL)

sj-lab 서비스들이 쓰는 표를 만드는 스크립트를 모아 둔 곳입니다. **폴더 이름 = 스키마 이름**입니다.

| 폴더 | 스키마 | 쓰는 서비스 |
|---|---|---|
| `map/` | `map` | `mapservice-rest` — 시설물 아이콘, 내업 기록·사진 |
| `api/` | `api` | `sj-lab-openapi` — 공개 API 키, 사용량 |

## 실행 주체 — 에이전트가 아니라 사람

프로젝트 규칙상 **에이전트는 DB를 조회(SELECT)만** 합니다. 여기 있는 스크립트는 DB 권한이 있는 담당자가
직접 실행합니다. 모두 `IF NOT EXISTS`라 여러 번 실행해도 안전합니다.

```bash
psql -h <호스트> -p 5432 -U <계정> -d sjlab -f map/map_facility_office_work.sql
```

## 실행 순서와 주의

| 스크립트 | 먼저 필요한 것 | 실행 전에는 |
|---|---|---|
| `map/map_facility_icon.sql` | - | 아이콘 API가 빈 배열 → 프론트는 기본 아이콘으로 동작(정상) |
| `map/map_facility_office_work.sql` | - | 시설물 목록은 폴백으로 동작, 내업 API만 500 |
| `map/map_facility_office_work_photo.sql` | 위 내업 기록 표(FK) | 내업 사진 API만 500 |
| `api/openapi_api_key.sql` | - | 키 API만 503, 공개 API 조회는 정상 |
| `api/openapi_api_usage.sql` | 위 키 표(FK) | 〃 |
| `estate/estate_apt.sql` | - | **아파트 매매·전월세 수집이 실패**하고 부동산 화면이 빈 상태. 다른 기능은 영향 없음 |
| `estate/estate_drop_legacy_apt.sql` | 위 `estate_apt.sql` | 옛 `ai.apt_*` 표가 그대로 남아 있음(기능 영향 없음) |
| `estate/estate_apt_monthly_matview.sql` | 위 `estate_apt.sql` | 화면은 그대로 되지만 **전국 조회가 느림**(매매 8.6초·전월세 28.7초 실측). 지역을 고르면 0.04초 — 급하지 않으면 미뤄도 됨 |

- **스키마를 바꾸지 말 것**: `qfield` 스키마는 `sj-qfieldsync` 워커가 관리하며, 프로젝트 이름 패턴이 아닌
  표를 "삭제된 프로젝트 표"로 보고 지웁니다(2026-09-16·09-18 실제로 두 번 삭제됨). 앱이 쓰는 표는 `map`,
  공개 API 관련 표는 `api` 스키마에 둡니다.
- **스키마별 용도**(2026-10-06 정리): `map` 지도·시설물 / `api` 공개 API 키·사용량 /
  `estate` 부동산 실거래(아파트 매매·전월세) / `ai` **AI·RAG 관련 표만**(아파트 데이터는 `estate` 로 이전) /
  `qfield` 현장조사 동기화(워커 관리).
- **`estate_drop_legacy_apt.sql` 은 되돌릴 수 없습니다** — 옛 `ai.apt_trades`(1,075만 행, 2006~2025)와
  `ai.apt_rents`(1,253만 행, 2011~2025)가 사라집니다. 그래서 DROP 문은 **주석 처리해 두었고**,
  버리지 않고 `estate` 로 옮기는 INSERT 문도 같은 파일에 함께 있습니다. 어느 쪽으로 할지 정한 뒤 주석을 풀 것.
- 표가 없을 때의 동작은 위 표대로 **기능 일부만 막히고 서비스는 뜹니다**. 폴백을 없애지 마세요.
- 실행했으면 그 작업의 `history/` 문서에 대상 DB·계정·결과를 남깁니다.

## 관련 문서

- 전체 구조와 표가 쓰이는 맥락: `docs/system-architecture.md`
- 운영 Secret(접속 정보): `docs/k8s-secrets.md`
- 각 서비스의 코드 규칙: `mapservice-rest/CLAUDE.md`, `sj-lab-openapi/CLAUDE.md`
