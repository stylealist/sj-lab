# history v4.25 — 공개 저장소에 평문으로 있던 비밀값 걷어내기 (1단계)

- **날짜**: 2026-11-16
- **영향 저장소**: `sj-lab`, `sj-lab-scheduler`, `mapservice-rest`, `sj-qfieldsync`, `sj-lab-k8s-manifests`
- **이전 버전**: [history_v4.24.md](history_v4.24.md)
- **상태**: **1단계 완료** — 코드·차트·스크립트·문서 준비. **아직 배포하지 않았습니다**
  (2단계 Secret 생성 → 3단계 배포 → 4·5단계 값 교체가 남음)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| 부동산 화면(운영) | https://sj-lab.co.kr/estate/ | 지도 · 단지 상세 |
| 지도 화면(운영) | https://sj-lab.co.kr/map/ | 이번 작업의 영향 범위 |

## 실행한 프롬프트

```
변경 파일 커밋 푸시 진행해주고 개선 목록 다시 한번 띄워줘
2번 진행하고 싶어 어떻게 하면돼?
아니 2번이 아니라 현재 순서대로
진행해줘
```

## 1. 무엇이 문제였나

**공개(public) 저장소 다섯 곳에 운영 비밀값이 평문으로 들어 있었습니다.**

| 공개 저장소 · 파일 | 들어 있던 것 |
|---|---|
| `sj-lab-scheduler` `application.yml` | DB 주소(**공인 IP + 포트**) · 계정 · 비밀번호 · 공공데이터 키 · ITS 키 · 생활안전지도 키 |
| `mapservice-rest` `application.yml` | 같은 DB 주소 · 계정 · 비밀번호 |
| `sj-qfieldsync` `qfield_data_sync.py` | 같은 DB 정보 + QFieldCloud 메타DB 정보 + **QFieldCloud admin 비밀번호** |
| `sj-qfieldsync` `qfield_data_sync_20260828.py` | 위와 같은 값이 든 **백업 사본**(뒤늦게 발견) |
| `sj-lab-k8s-manifests` `postgres/values.yaml`, `postgres-qfield/values.yaml` | **DB 비밀번호가 정의되는 곳** |

**왜 심각한가**

- 그 계정은 표의 **소유자이자 superuser** 입니다 — 조회뿐 아니라 **표 삭제·계정 생성**까지 됩니다.
- 접속 주소가 클러스터 내부 이름이 아니라 **공인 IP + NodePort** 입니다. 주소와 비밀번호를 아는
  누구나 **바깥에서 바로 접속**할 수 있었습니다(실제로 그 경로로 붙는 것을 확인).
- **개발 DB 와 운영 DB 가 같은 인스턴스**라 피해가 곧 운영 피해입니다.
- **QFieldCloud admin 비밀번호가 DB 비밀번호와 같은 값**이었습니다(재사용).
- `sj-lab-scheduler` 는 **2025-08-01 부터** 공개돼 있었습니다(15개월).

**그리고 운영도 그 평문 값으로 돌고 있었습니다.** 세 서비스 모두 차트에 비밀값 주입 설정이
없어, 이미지에 구워진 설정 파일 값으로 DB 에 붙고 있었습니다.

## 2. 코드만 고쳐서는 해결되지 않습니다

**git 이력에는 과거 값이 그대로 남습니다.** 과거 커밋에서 읽히므로 **값 자체를 바꾸지 않으면
아무 의미가 없습니다.** 이력 재작성(history rewrite)은 이미 퍼진 클론·포크에 효과가 없고 위험해
택하지 않았습니다 — **교체(로테이션)가 유일한 해결**입니다.

그래서 작업을 단계로 나눴습니다. **이번에 한 것은 1단계뿐이고, 운영에는 아직 영향이 없습니다.**

| 단계 | 할 일 | 누가 | 상태 |
|---|---|---|---|
| 1 | 코드·차트를 환경변수/Secret 방식으로 · 스크립트·문서 준비 | 에이전트 | **완료** |
| 2 | Secret 을 **지금 값 그대로** 만들기 | 사용자(kubectl) | 대기 |
| 3 | 세 서비스 빌드·배포 후 동작 확인 | 사용자(Jenkins) | 대기 |
| 4 | DB 비밀번호 교체 → Secret·로컬 갱신 → 재시작 | 사용자 + SQL | 대기 |
| 5 | 포털 키·QFieldCloud 비밀번호 재발급 | 사용자(각 포털) | 대기 |

## 3. ⚠️ 배포 순서를 반드시 지켜야 합니다

**Secret 을 만들기 전에 push 하면 운영이 멈춥니다.** push → Jenkins → ArgoCD 로 자동 배포되는데,
새 코드는 접속 정보가 없으면 **일부러 기동하지 않습니다.** Secret 이 없는 상태로 배포되면
지도 서비스와 수집기가 뜨지 않습니다.

```
  ❶ Secret 4개 만들기  →  ❷ push·배포  →  ❸ 확인  →  ❹ 값 교체
```

## 4. 고치는 중에 제 가정이 틀린 것을 발견했습니다

차트와 문서에 **"접속 정보가 없으면 기동이 실패한다"** 고 적었는데, 실제로 빈 값으로 띄워 보니
**기동이 성공했습니다.** Spring 이 "Started" 를 찍고, 첫 수집에서야
`Driver claims to not accept jdbcUrl, ${SCHEDULER_DB_URL}` 로 터졌습니다.

그게 바로 제가 위험하다고 말한 **"조용히 아무것도 안 하는"** 상태입니다 — "왜 데이터가 안
쌓이지?"를 한참 뒤에 알게 됩니다. 그래서 두 서비스의 `main()` 에 **시작 전 검사**를 넣었습니다.
값은 출력하지 않고 **없는 환경변수 이름만** 알립니다.

```
[중단] DB 접속 환경변수가 없습니다: SCHEDULER_DB_URL, SCHEDULER_DB_USERNAME, SCHEDULER_DB_PASSWORD
       이 서비스는 적재 배치라, 접속 정보 없이 뜨면 조용히 아무것도 적재하지 않습니다.
```

확인한 것: 값이 없으면 **위 메시지와 함께 종료**, 값이 있으면 **정상 기동 + DB 연결 성공**
(`HikariPool Start completed`).

## 5. 바뀐 파일

| 저장소 | 파일 | 내용 |
|---|---|---|
| `sj-lab-scheduler` | `application.yml` | DB·API 키를 **환경변수로만** 받게 바꾸고 평문 제거 |
| | `SchedulerRestApplication.java` | **시작 전 검사** 추가(없으면 이름만 알리고 종료) |
| | `CLAUDE.md` · `README.md` | 환경변수 표와 "없으면 어떻게 되는지" |
| `mapservice-rest` | `application.yml` | 같은 처리 |
| | `MapServiceRestApplication.java` | **시작 전 검사** 추가 |
| | `CLAUDE.md` · `README.md` | 같은 처리 |
| `sj-qfieldsync` | `qfield_data_sync.py` | 두 DB·QFieldCloud 계정을 환경변수로. `_require_env()` 가 없는 이름을 알리고 멈춤 |
| | `qfield_data_sync_20260828.py` | 백업 사본을 `trash/2026-11-16/` 로 **옮김**(지우지 않음) · `trash/` 를 추적 제외 |
| | `CLAUDE.md` · `README.md` · `.gitignore` | 환경변수 표와 추적 제외 |
| `sj-lab-k8s-manifests` | `sj-lab-scheduler/`, `mapservice-rest/`, `sj-qfieldsync/` 차트 | `secretKeyRef` 주입 추가(DB 는 필수, API 키는 선택) |
| | `postgres/`, `postgres-qfield/` 차트 | 계정 정보를 Secret 으로. **`optional: true`** — 그 값은 DB 최초 초기화에만 쓰여서, 없다고 DB 가 못 뜨면 안 되기 때문 |
| `sj-lab` | `scripts/create-service-secrets.ps1` | **신규** — Secret 4개 생성·갱신. 값을 화면·명령 기록에 남기지 않음(키 이름과 길이만 출력) |
| | `scripts/local-stack.ps1` | `loadMapDbCredentials` 추가 — 없으면 mapservice-rest 가 안 뜨므로 미리 알린다 |
| | `db/estate/estate_rotate_credentials.sql` | **신규** — 비밀번호 교체 절차와 순서, 후속 과제 |
| | `docs/k8s-secrets.md` | Secret 4개 표 + **"비밀값 교체"** 절차 |
| | `docs/dev-environment.md` | 로컬 env 키 표 + 스케줄러 기동 예시 |
| | `CLAUDE.md` | 비밀값 규칙(진단 스크립트에서 값이 출력에 섞이지 않게 할 것 포함) |
| | `history/history_v4.25.md` · `history/web/*` | 이 기록과 공유 페이지 |

## 6. 확인한 것

- 두 Java 서비스 **빌드 통과**(JDK 17), 파이썬 **문법 검사 통과**
- 차트 5개 **`helm lint` 통과** 및 렌더링 확인
- Secret 생성 스크립트 **모의 실행** — 네 개 Secret 모두 값이 채워짐
- `mapservice-rest` 를 환경변수로 띄워 **DB 연결까지 확인**
- **git 이 추적하는 파일에 남은 평문 0건**(다섯 저장소 전수 검사)

## 7. 아직 남은 것

- **2~5단계**(위 표) — Secret 생성·배포·값 교체. 클러스터 접근과 포털 계정이 필요해
  에이전트가 할 수 없습니다.
- **후속 과제**: 적재 서비스가 superuser 를 쓰는 것은 권한이 과합니다. 적재 전용 계정으로
  분리하고, DB 의 공인 노출(NodePort)을 줄이는 것을 따로 진행할 것.
- `sj-lab-k8s-manifests/sj-qfieldsync/files/config.yaml` 에 QFieldCloud 주소와 `admin` 사용자명이
  남아 있습니다 — **비밀번호는 없어** 그대로 두었습니다.

## 8. 작업 중 제 실수

**진단하다가 비밀값을 두 번 출력했습니다.** `grep`/`Select-String` 으로 설정 파일 줄을 그대로
찍어 DB 주소·계정·비밀번호가 작업 기록에 남았습니다. 이미 공개 저장소에 있던 값이라 외부 노출이
새로 늘어난 것은 아니지만, 프로젝트 규칙을 어긴 것입니다. 이후에는 줄 번호로만 다루고 값을
가려서 진행했으며, 같은 일이 반복되지 않도록 `CLAUDE.md` 에 규칙으로 적어 두었습니다.
