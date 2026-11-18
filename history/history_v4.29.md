# history v4.29 — 자바 보안 결함 임시 막기 (CVE-2026-114938)

- **날짜**: 2026-11-18
- **영향 저장소**: `sj-lab-k8s-manifests`, `sj-lab`
- **이전 버전**: [history_v4.28.md](history_v4.28.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| 부동산 화면(운영) | https://sj-lab.co.kr/estate/ | 지도 · 단지 상세 |

## 실행한 프롬프트

```
현재 서버들에 대해서 openjdk 보안 취약점 해결하려고하는데
- "JAVA_TOOL_OPTIONS=-XX:-UseBASE64Intrinsics" # 임시 완화 옵션 추가 를 해서 진행하는 방식으로 진행 할 수 있어?
(다른 서버들에서는 docker-compose 에 추가해서 해결했다는 설명)
수정해서 커밋 푸시 해줘 젠킨스, 아르고CD 재배포 되도록 되어있어
```

## 1. 무슨 결함인가

**OpenJDK 가 Base64 를 풀 때 쓰는 가속 코드에 메모리 침범 결함**이 있습니다
(CVE-2026-114938, 별칭 "Java4Shell"). 외부에서 들어온 값이 그 디코더까지 닿으면 문제가 될 수
있습니다.

| | |
|---|---|
| 영향 | OpenJDK **17.0.6 이상** · **x86-64 + AVX-512 VBMI** CPU |
| 해당 없음 | **ARM64** · 그 CPU 기능이 없는 서버 |
| 패치 공개 | **2026-11-17** (Oracle · OpenJDK) |
| 우리 서비스 | 전부 `eclipse-temurin:17-jdk-alpine` 기반이라 **대상 범위** |

## 2. 한 일 — 가속 코드를 끄는 옵션을 넣었습니다

가속을 끄면 순수 자바 디코더로 돌아 그 경로를 타지 않습니다. 다른 서버에서 docker-compose 로
하신 것과 **같은 방식**이고, 쿠버네티스에서는 차트의 환경변수로 넣습니다.

```
JAVA_TOOL_OPTIONS = "-Duser.timezone=Asia/Seoul -XX:-UseBASE64Intrinsics"
```

**따로 한 줄 더 넣지 않고 기존 값에 이어 붙였습니다** — 이름이 같은 환경변수를 두 번 두면
뒤엣것만 남아 **타임존 설정이 사라집니다.**

대상 8개: 게이트웨이 · 디스커버리 · 지도 백엔드 · 로그인 · 부동산 · 공개 API · 수집기 · GeoServer
(파이썬으로 도는 `fast-api-ai`·`sj-qfieldsync` 는 해당 없음)

## 3. 중요 — 이건 임시입니다

**해결은 패치된 자바가 들어간 이미지로 다시 빌드하는 것**입니다. 다행히 Dockerfile 이 버전을
고정하지 않아(`17-jdk-alpine`) **코드 한 줄 고치지 않고 Jenkins 잡만 다시 돌리면** 됩니다.
그 뒤에는 이 옵션을 **빼는 것이 맞습니다**(Base64 처리가 조금 느려지므로).

그래서 차트마다 같은 내용을 주석으로 남겼고, 확인·제거 절차는 `docs/k8s-runbook.md` **5-2절**에
적어 두었습니다.

## 4. 확인한 것

- 8개 차트 **`helm lint` 통과 · `helm template` 렌더링 정상**, 환경변수 값이 의도대로 들어감
- 수정 전 `git pull` — Jenkins 자동 커밋(부동산 이미지 태그)을 먼저 받아 충돌 없이 push
- push 완료 → **ArgoCD 가 동기화하며 순차 롤아웃**(롤아웃 중 짧은 503 은 정상)

**사용자가 확인하실 것**(명령은 런북 5-2절):

1. 파드에서 `UseBASE64Intrinsics` 가 **false** 인지
2. `JAVA_TOOL_OPTIONS` 에 **타임존이 함께** 남아 있는지
3. CPU 가 AVX-512 VBMI 를 지원하지 않는 서버라면 **원래 false** 라 변화가 없는 것이 정상

## 바뀐 파일

| 저장소 | 파일 | 내용 |
|---|---|---|
| `sj-lab-k8s-manifests` | `apigateway` · `discoveryserver` · `mapservice-rest` · `sj-lab-authserver` · `sj-lab-estate` · `sj-lab-openapi` · `sj-lab-scheduler` 의 `templates/deployment.yaml` | `JAVA_TOOL_OPTIONS` 에 `-XX:-UseBASE64Intrinsics` 덧붙임 + 이유·제거 시점 주석 |
| | `geoserver/values.yaml` | 같음 |
| `sj-lab` | `docs/k8s-runbook.md` | 5-2절 신설 — 영향 여부·적용 확인·롤아웃 확인 명령, 패치 후 되돌리기 |
| | `history/history_v4.29.md` · `history/web/*` | 이 기록과 공유 페이지 |
