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

- **스키마를 바꾸지 말 것**: `qfield` 스키마는 `sj-qfieldsync` 워커가 관리하며, 프로젝트 이름 패턴이 아닌
  표를 "삭제된 프로젝트 표"로 보고 지웁니다(2026-09-16·09-18 실제로 두 번 삭제됨). 앱이 쓰는 표는 `map`,
  공개 API 관련 표는 `api` 스키마에 둡니다.
- 표가 없을 때의 동작은 위 표대로 **기능 일부만 막히고 서비스는 뜹니다**. 폴백을 없애지 마세요.
- 실행했으면 그 작업의 `history/` 문서에 대상 DB·계정·결과를 남깁니다.

## 관련 문서

- 전체 구조와 표가 쓰이는 맥락: `docs/system-architecture.md`
- 운영 Secret(접속 정보): `docs/k8s-secrets.md`
- 각 서비스의 코드 규칙: `mapservice-rest/CLAUDE.md`, `sj-lab-openapi/CLAUDE.md`
