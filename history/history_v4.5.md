# history v4.5 — 부동산 운영 배포 준비(차트 · Jenkins · nginx) + Orca 등록

- **날짜**: 2026-10-12
- **영향 저장소**: `sj-lab-k8s-manifests`, `sj-lab`
- **이전 버전**: [history_v4.4.md](history_v4.4.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| 허브 (운영) | https://sj-lab.co.kr | 부동산 카드 → `/estate/` |
| 부동산 (운영, 배포 후) | https://sj-lab.co.kr/estate/ | 지금은 미배포 |
| 부동산 조회 API (운영, 배포 후) | https://api.sj-lab.co.kr/estate/status | 지금은 미배포 |

## 실행한 프롬프트

```
지금 내 orca에도 현재 프로젝트들을 왼쪽에 나오게 추가해주고 남은 작업 진행해줘
```

## 1. Orca 사이드바에 저장소를 추가했습니다

새로 만든 두 저장소가 Orca 목록에 없어서 추가했습니다 — 이제 **18개**가 왼쪽에 보입니다.

- `sj-lab-estate`(부동산 조회 서버), `sj-lab-estate-web`(부동산 화면)
- 같이 쓰는 다른 AI 도구(Antigravity · Gemini)의 **폴더 신뢰 목록**도 채웠습니다. 빠져 있으면
  작업을 맡길 때 "이 폴더를 믿습니까?" 창에서 멈춰 버립니다. 빠져 있던 4곳(인증 서버, 공개 API,
  부동산 서버·화면)을 넣었습니다.

## 2. 부동산 운영 배포를 준비했습니다 (아직 배포하지는 않았습니다)

운영에 올리려면 **차트 · 빌드 잡 · 웹서버 설정** 세 가지가 필요합니다. 셋 다 만들어 뒀습니다.

| 만든 것 | 내용 |
|---|---|
| 조회 서버 차트 | `sj-lab-k8s-manifests/sj-lab-estate/` — 기존 서비스 차트와 같은 구성 |
| 조회 서버 빌드 잡 | `docs/jenkins/sj-lab-estate-pipeline.groovy` |
| 화면 빌드 잡 | `docs/jenkins/sj-lab-estate-web-pipeline.groovy` |
| 웹서버 설정 | `/estate/` 경로를 부동산 화면으로 (없으면 404) |

**DB 접속 정보가 없어도 배포는 성공하게** 두었습니다. 그때는 화면이 "준비되지 않았다"고 안내하고
조회만 막힙니다 — 배포와 데이터 준비를 따로 진행할 수 있어야 하기 때문입니다.

**허브 배포가 부동산 화면을 지우지 않도록** 허브 잡의 보호 목록에 `estate/`를 넣었습니다.
네 사이트가 한 디렉터리를 공유해서 이 목록을 빠뜨리면 허브를 배포할 때마다 옆 사이트가 사라집니다
(지도에서 실제로 반복됐던 사고입니다).

## 3. 점검 스크립트에서 버그를 하나 찾았습니다

운영 사이트 점검(`scripts/check-prod-sites.ps1`)에 부동산·API 활용 페이지를 추가하다가,
**허브를 가려내는 표식이 잘못돼 있던 것**을 발견했습니다.

- `bundle`(webpack 산출물)을 "허브 표식"으로 쓰고 있었는데, 활용 페이지와 부동산 화면도 **같은 webpack**이라
  그 표식이 똑같이 들어 있습니다. 그대로 두면 **정상인 사이트를 "지워졌다"고 잘못 알립니다**(실제로 그렇게 나왔습니다).
- 허브에만 있는 제목(`<title>SJ-LAB</title>`)으로 바꿨습니다.
- **배포 전인 사이트는 실패로 세지 않습니다** — 404 든, 설정 반영 전이라 허브 화면이 와도 "미배포"로 표시합니다.

실행 결과(지금):

```
[정상]  허브    https://sj-lab.co.kr/
[정상]  지도    https://sj-lab.co.kr/map/
[정상]  API     https://sj-lab.co.kr/openapi/
[미배포] 부동산  https://sj-lab.co.kr/estate/   (아직 배포 전)
```

## 4. 바뀐 파일

| 저장소 | 파일 | 내용 |
|---|---|---|
| `sj-lab-k8s-manifests` | `sj-lab-estate/` (Chart·values·templates·files) | **신규 차트** — ClusterIP 8080, DB Secret 은 optional |
| | `sj-lab-webserver/files/nginx-set.conf` | `/estate/` 경로 추가(없으면 404) |
| | `README.md`, 규칙 문서 | 차트 목록·Secret 목록 갱신 |
| `sj-lab` | `docs/jenkins/sj-lab-estate-pipeline.groovy` | **신규** — 조회 서버 빌드·배포 |
| | `docs/jenkins/sj-lab-estate-web-pipeline.groovy` | **신규** — 화면 빌드·배포 |
| | `docs/jenkins/sj-lab-hub-pipeline.groovy` | 보호 목록에 `estate/` 추가, 확인 단계에 부동산 추가 |
| | `scripts/check-prod-sites.ps1` | 네 사이트 점검 + 표식 버그 수정 + 미배포 구분 |
| | `docs/k8s-secrets.md` | `estate-db-credentials`(필요 권한까지) 추가 |
| | `docs/deploy-static-sites.md`, `docs/system-architecture.md` | 하위 사이트 네 곳 구조·주의사항 |

`helm lint`·`helm template` 로 두 차트(신규·웹서버) 렌더링을 확인했습니다.

## 남은 이야기 (사람이 해야 하는 일)

1. **ArgoCD 에 `sj-lab-estate` Application 등록** — 안 하면 이미지 태그만 올라가고 배포가 안 됩니다.
2. **Jenkins 잡 2개 생성** — 위 groovy 파일을 붙여 넣기. 화면 잡은 웹서버 노드에
   `mkdir -p /respal/deploy-estate` 가 먼저 필요합니다.
3. **운영 DB 준비** — `db/estate/estate_apt.sql` 실행 + `estate-db-credentials` Secret 생성
   (조회 전용 계정 권장, 필요 권한은 `docs/k8s-secrets.md`).
4. **전월세 보증금 재수집**(v4.4 에서 찾은 버그) — 약 250개월. 시점을 정해 주시면 진행합니다.
5. 전국 조회 집계 스크립트와 지도용 단지 좌표는 그다음 단계입니다.
