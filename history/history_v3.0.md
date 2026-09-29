# history v3.0 — 총괄 저장소를 sj-lab으로 옮김

- **날짜**: 2026-09-30
- **영향 저장소**: `sj-lab`(신규 총괄), `mapservice-rest`(백엔드 전용으로 정리), 나머지 12개 저장소(경로 안내 문구)
- **이전 버전**: [history_v2.59.md](history_v2.59.md)
- **major를 올린 이유**: 작업 기준이 되는 저장소 자체가 바뀌는 구조 변경

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 주소 그대로 유지 |
| 총괄 저장소 | https://github.com/stylealist/sj-lab | 이번에 옮겨온 곳 |
| 백엔드 저장소 | https://github.com/stylealist/mapservice-rest | 코드만 남음 |

## 실행한 프롬프트

```
jenkins 파일 history 파일등은 사실 mapservice-rest랑은 무관한거 같은데
sj-lab-hub에서 해당 파일을 관리하고 해당 프로젝트에서 실행해도 sj-lab에 있는 프로젝트들 모두
개발 진행이 가능하도록 할 수 있어?
→ 아니 정정할게 sj-lab-hub 말고 sj-lab에서 관리하고싶어
```

## 왜 옮겼나

지도 백엔드 저장소에 **다른 서비스의 배포 스크립트·작업 로그·플랫폼 문서**가 섞여 있었습니다.
백엔드와 상관없는 파일이 절반이라, 저장소를 열어 본 사람이 "이게 왜 여기 있지?" 하게 됩니다.

`sj-lab`은 원래 플랫폼 소개 README만 있던 저장소라 **Jenkins 잡이 없습니다.** 문서를 고쳐도 아무것도
배포되지 않아 총괄 자리로 가장 알맞았습니다(허브 저장소는 push마다 사이트가 재배포됩니다).

## 무엇이 어디로 갔나

| 옮긴 것 | 설명 |
|---|---|
| `docs/` | 시스템 구조, 로컬 개발 환경, MCP, 운영 Secret, 정적 배포, Jenkins 파이프라인 6종, DB 분석 |
| `history/` (99개) | 작업 로그 전체 + 공유 페이지 원본(`web/artifact.html`, `web/index.html`) |
| `scripts/` | `local-stack.ps1`, `static-server.js`, `check-prod-sites.ps1` |
| 설정 | `.mcp.json`, `.claude/settings.local.json`(비밀값, git 제외), `.claude/hooks/guard.sh` |
| `trash/` | 지우지 않고 보관해 둔 파일들 |
| `db/` | 표 생성 스크립트(DDL) 5개 — 폴더 이름이 곧 스키마(`map/`, `api/`), 실행 안내 `db/README.md` 신설 |

**백엔드 저장소에 남은 것**: 소스·`Dockerfile`·`pom.xml`·README, 그리고 그 저장소 전용인
리뷰 체크리스트(`.claude/agents/reviewer.md`)와 레이어 추가 스킬(`.claude/skills/add-wfs-layer`).

## 같이 고친 것

- **`sj-lab/CLAUDE.md` 신설** — 공통 규칙·작업 규칙·history 규칙·공유 페이지 규칙을 모두 여기로.
- **`mapservice-rest/CLAUDE.md`는 백엔드 규칙만** 남기고, 맨 위에 "총괄은 sj-lab" 안내표를 넣었습니다.
- **다른 12개 저장소의 `CLAUDE.md`** 안 "총괄 기준 저장소" 경로를 새 주소로 바꿨습니다.
- **`local-stack.ps1`**: 이 저장소에는 백엔드 소스가 없으므로, 빌드·실행 경로를 `workspaceRoot\mapservice-rest`로
  분리했습니다(상태 파일·비밀값은 총괄 저장소에서 읽음). 이미 떠 있던 프로세스 목록도 옮겨 `stop`이 그대로 동작합니다.
- **작업 범위 목록**에 `mapservice-rest`를 넣어, 새 세션에서 백엔드를 바로 읽고 고칠 수 있게 했습니다.

## 확인

| 확인 | 결과 |
|---|---|
| 새 위치에서 `local-stack.ps1 status` | 정상 — 포트 8761·8100·4000 확인, Eureka 4개 서비스 표시 |
| 문서 안 옛 경로 참조 | 남은 것 없음(백엔드 소스 위치를 가리키는 1곳은 의도된 표기) |
| 발행 페이지 주소 | 그대로 유지 |

## 이렇게 쓰시면 됩니다

```
총괄 세션:  C:\developer\workspace\sj-lab      ← 여기서 Claude Code 를 띄운다
백엔드 작업: C:\developer\workspace\mapservice-rest  (세션에서 바로 열림)
```

## 남은 일

- 새 세션을 `sj-lab`에서 한 번 띄워 MCP(GitHub·DB) 연결과 가드 훅이 그대로 붙는지 확인.
- Orca 프로젝트 목록에 `sj-lab` 추가(`orca repo add --path C:\developer\workspace\sj-lab`).
