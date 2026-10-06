# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## sj-lab 통합 허브 (총괄 기준 저장소)

이 저장소는 **sj-lab 플랫폼 전체를 총괄하는 기준 저장소**입니다(2026-09-30 `mapservice-rest`에서 이전).
저장소를 넘나드는 작업(DB → 백엔드 → 디스커버리 → 게이트웨이 → 프론트엔드 → 배포)은 여기서 세션을 띄워 진행하고,
공통 설정과 문서를 여기서 관리합니다.

- MCP 설정(`.mcp.json`), 로컬 비밀값(`.claude/settings.local.json`), Bash 가드 훅(`.claude/hooks/guard.sh`)
- 시스템 구조·API 계약·배포 경로 문서(`docs/`)
- 로컬 기동 스크립트(`scripts/`), 작업 로그(`history/`), 옮긴 파일 보관(`trash/`)
- DB 스크립트(`db/<스키마>/*.sql`) — 표 생성(DDL). **실행은 에이전트가 하지 않고 담당자가** 합니다(`db/README.md`)
- 저장소 자체의 `README.md`는 **플랫폼 소개 페이지**(면접관·처음 보는 사람이 읽는 문서)입니다. 서비스 주소 표가 있으니
  운영 주소가 바뀌면 지도 프론트의 "저장소 · 문의" 탭과 함께 갱신할 것.

각 저장소의 코드 규칙은 그 저장소의 `CLAUDE.md`를 따릅니다(백엔드 규칙은 `mapservice-rest/CLAUDE.md`).

- @docs/system-architecture.md — DB → 백엔드 → Eureka → 게이트웨이 → 프론트 전체 구조, API 계약 표, 저장소를 넘나드는 변경 체크리스트
- @docs/dev-environment.md — 로컬 저장소 경로, 포트·라우팅(8100=게이트웨이, 4000=지도, 4100=API 활용 페이지, 8761=Eureka), CORS
- @docs/mcp.md — GitHub/DB MCP 설정과 비밀값 관리 규칙
- `docs/k8s-secrets.md` — 운영 k8s Secret·Jenkins Credential 이름·용도·없을 때 증상. 차트의 `secretKeyRef`/`pullSecret`을 바꾸면 이 문서도 같이 고칠 것
- `docs/openapi-expose-checklist.md` — **백엔드에 새 조회 기능을 만들면 공개 API(`sj-lab-openapi`)에도 같은 작업에서 함께 열기**. 열 수 있는지 판단하는 4가지 기준, 카탈로그 항목 형식, 함께 고칠 문서, 확인 방법
- `docs/deploy-static-sites.md` — 허브·지도·API 활용 페이지 정적 배포(웹서버 노드에 파일 복사). **세 사이트가 한 디렉터리를 공유해 허브 배포가 하위 사이트를 지울 수 있음** — 안전한 배포 스테이지, 확인(`scripts/check-prod-sites.ps1`)·복구 방법
- `docs/jenkins/*.groovy` — 서비스별 Jenkins 파이프라인 원본. 잡을 고치면 이 파일도 같은 작업에서 갱신할 것
- `docs/analysis/*.md` — 개발 DB 연결·권한·스키마 점검 및 인덱스·뷰·데이터 품질 분석
- `db/README.md` — 표 생성 스크립트 목록, 실행 순서, 실행 전에는 어떤 기능이 막히는지

공통 규칙:
- 답변은 한글로 할 것.
- 코드 추가·수정 중 CLAUDE.md 또는 docs에 반영해야 할 내용이면 코드 변경 직후 바로 추가할 것.
- 함수·변수 이름은 카멜 형식으로 지을 것.
- 바로 commit, push하지말고 한번 물어본후에 진행할것
- 다른 저장소(백엔드·게이트웨이·디스커버리·scheduler·fast-api-ai·authserver·openapi·프론트엔드·hub·k8s-manifests·qfieldsync·infra-manage-app) 파일을 수정하기 전에 그 저장소의 `CLAUDE.md`를 먼저 Read할 것(이 세션에 자동 로드되지 않음). git 작업은 `git -C <경로>`로 저장소별로 할 것.
- API 경로·응답 형식을 바꾸면 백엔드와 프론트를 같은 작업에서 함께 수정하고 `docs/system-architecture.md`의 API 계약 표를 갱신할 것.
- **백엔드에 새 조회(GET) 기능을 추가하면 공개 API(`sj-lab-openapi`)에 열 수 있는지 판단하고, 열 수 있으면 같은 작업에서 카탈로그(`api-catalog.json`)에 함께 추가할 것** — 기준·절차는 `docs/openapi-expose-checklist.md`. 애매하면 열지 말고 사용자에게 먼저 물어볼 것.
- `.claude/hooks/guard.sh`가 `git reset --hard`, `git push --force`, 그리고 `claude` 문자열이 들어간 Bash 명령을 차단합니다. 차단되면 우회하지 말고 다른 도구(Read/Grep/PowerShell)로 해결할 것.

작업 규칙:
- **작업 범위**: `docs/dev-environment.md`의 "로컬 저장소 경로" 표에 명시된 저장소 안에서만 작업할 것. 표에 없는 경로를 읽거나 고쳐야 하면 먼저 사용자에게 확인하고, 승인되면 그 표와 `additionalDirectories`에 추가할 것.
- **DB**: 기본은 조회(SELECT)만 할 것. 사용자가 특정 스크립트를 콕 집어 "실행해줘"라고 지시한 경우에만 예외로 실행하되, ① 실행할 SQL을 먼저 저장소에 스크립트 파일로 남기고 ② 대상 DB·계정을 밝힌 뒤 ③ 실행 결과와 함께 history에 기록할 것. 그 외에는 `CREATE`/`ALTER`/`DROP`(DDL), `GRANT`/`REVOKE`(DCL), `INSERT`/`UPDATE`/`DELETE`(DML)를 임의로 실행하지 말 것 — 필요한 SQL은 실행하지 말고 사용자에게 제안만 할 것. scheduler를 로컬에서 띄우면 cron 배치가 DB에 적재하므로 이것도 사용자 확인 후에.
- **파일 삭제**: 파일을 지우지 말고 `trash/<YYYY-MM-DD>/` 아래에 원래 경로 구조를 유지한 채 옮길 것(예: `trash/2026-09-16/docs/old.md`). 옮긴 파일은 그 버전의 history 문서에 기록할 것.
- **git push**: 자동으로 push하지 말 것. 사용자가 명시적으로 요청할 때만 push하며, 커밋은 저장소별로 `git -C <경로>`로 할 것.
- **변경 기록(history)**: 파일을 실제로 변경한 작업마다 `history/history_v<major>.<minor>.md`를 새로 만들 것(조회·질문만 한 턴은 기록하지 않음). 내용은 사용자가 입력한 프롬프트 원문, 변경된 결과물(파일별 요약), 접속 URL 링크를 포함할 것. 직전 버전에서 minor를 1 올리고, 구조가 바뀌는 큰 작업이면 major를 올릴 것.
- 작업 로그의 내용은 비개발자들도 공유가 쉽게되도록 최대한 일상적인 언어를 사용해서 작성할것.
- 최대한 한눈에 들어오도록 핵심위주로 심플하게 작성할것
- **공유 웹사이트**: history 문서를 추가·수정하면 같은 작업에서 두 곳을 함께 갱신할 것.
  1. `history/web/artifact.html` — 팀에 링크로 공유하는 발행 페이지의 원본. 버전 패널을 추가한 뒤 **같은 URL로 다시 발행**해야 링크가 유지됨(발행 주소: `https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9`). 발행은 외부 서비스에 내용을 올리는 행위이므로 민감 정보를 싣지 말 것.
  - 작업로그는 탭으로 관리되며 한 탭에 15개의 로그가 포함되도록 한다(예: v1.0 ~ v1.14, v1.15 ~ v1.29).
    - 페이지 스크립트(`chipsPerGroup = 15`)가 로드 시 버전 칩을 순서대로 15개씩 다시 묶고 탭 이름(`v첫 – v끝`)도 만든다. 새 버전은 마지막 묶음 끝에 칩만 추가하면 되며, 마크업의 묶음도 가능하면 15개 단위로 맞춰 둘 것(스크립트가 꺼진 환경 대비).
  2. `history/web/index.html` — 오프라인용 요약 페이지. 외부 CDN·빌드 도구 없이 단일 HTML로 유지할 것.
  - 새 history 문서의 접속 URL 표 맨 위에 발행 페이지 주소를 넣을 것
- **AI에이전트 오케스트레이션**: 오케스트레이션을 진행할 때 최종 검증은 반드시 Claude로 진행할 것.
  1. Claude를 메인으로 하되 일일 남은 토큰에 따라 antigravity도 활용할 것
  2. 프론트엔드 개발은 antigravity를 적극적으로 활용할 것

## 반드시 지킬것

- 프롬프트에 /orchestration 를 쓰지 않아도 기본값으로 /orchestration로 실행되도록 할 것

## 이 저장소에서 자주 쓰는 명령

이 저장소에는 빌드할 코드가 없습니다. 로컬 전체 기동과 운영 확인만 합니다.

```
powershell -ExecutionPolicy Bypass -File scripts\local-stack.ps1 start     # 빌드 후 전체 기동
powershell -ExecutionPolicy Bypass -File scripts\local-stack.ps1 start -NoBuild
powershell -ExecutionPolicy Bypass -File scripts\local-stack.ps1 status
powershell -ExecutionPolicy Bypass -File scripts\local-stack.ps1 stop      # 이 스크립트가 띄운 프로세스만 종료
powershell -ExecutionPolicy Bypass -File scripts\check-prod-sites.ps1      # 운영 정적 사이트 상태 확인
```

- `local-stack.ps1`은 **백엔드 소스를 `C:\developer\workspace\mapservice-rest`에서 빌드**합니다(이 저장소에는 소스가 없음).
  경로를 옮겼다면 `-workspaceRoot` 인자를 주거나 스크립트 상단 기본값을 고칠 것.
- 상태 파일(`.local-stack/`)과 로컬 비밀값(`.claude/settings.local.json`)은 이 저장소에 생기며 git에서 제외됩니다.

## README 유지 규칙

- **플랫폼에 서비스·주소·기능이 추가되거나 바뀌면 같은 작업에서 `README.md`도 함께 갱신할 것.**
- **README는 면접관·처음 보는 사람이 읽는 문서**입니다. 사용자·리뷰어 관점의 설명(무엇을·왜·어떻게 확인하는지)은 README에,
  에이전트/내부 작업 규칙은 이 문서(CLAUDE.md)에 둡니다.
- 문구가 실제와 어긋나지 않는지 확인하고, 구현되지 않은 기능을 적지 말 것. 한계·미구현 항목은 숨기지 말고 적습니다.
