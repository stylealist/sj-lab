# history v4.6 — 부동산 화면 Jenkins 잡을 "붙여넣기만 하면 되게" 준비

- **날짜**: 2026-10-12
- **영향 저장소**: `sj-lab`
- **이전 버전**: [history_v4.5.md](history_v4.5.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| Jenkins | https://jenkins.sj-lab.co.kr | 잡 생성 대상 |
| 부동산 (운영, 배포 후) | https://sj-lab.co.kr/estate/ | 지금은 미배포 |

## 실행한 프롬프트

```
커밋 푸시해줘 그리고 프론트쪽부터 jenkins 작성해줘
```

## 1. 먼저 커밋·푸시했습니다

v4.5 의 결과물(부동산 차트 · Jenkins 파이프라인 2개 · nginx 경로 · 점검 스크립트 수정 · 문서)을
두 저장소에 나눠 커밋하고 올렸습니다.

## 2. 프론트(부동산 화면) 잡을 준비했습니다

Jenkins 잡은 **사람 계정으로만 만들 수 있어** 제가 직접 만들 수는 없습니다(로그인 없이 목록은
보이지만, 설정을 읽거나 만드는 것은 막혀 있습니다 — 확인했습니다). 그래서 **만드는 순간의 손을
최소로 줄여** 두었습니다.

| 만든 것 | 쓰임 |
|---|---|
| `docs/jenkins/sj-lab-estate-web-job-config.xml` | 잡 설정 전체(파이프라인 + GitHub 주소 + push 트리거)를 담은 가져오기용 파일 |
| `scripts/make-jenkins-job-config.py` | 파이프라인 원본(groovy)에서 위 XML 을 만드는 스크립트 |
| `docs/jenkins/README.md` | 잡 이름 규칙, 만드는 두 가지 방법(웹 화면 / 명령 한 줄), 만들기 전 준비물 |

**파이프라인 원본(groovy)이 단일 소스**입니다. XML 은 그것을 그대로 읽어 만들기 때문에, 잡을
고칠 때는 groovy 만 고치고 스크립트를 다시 돌리면 됩니다. 두 곳을 각각 고치다 어긋나는 일을
막으려는 구조입니다.

만드는 방법은 둘 중 하나입니다.

- **웹 화면**: 새 Item → Pipeline → GitHub 주소·push 트리거 체크 → groovy 전문 붙여넣기
- **명령 한 줄**: 위 XML 을 Jenkins 에 POST (API 토큰 필요). **토큰은 저장소·문서·대화에 남기지 않습니다** —
  사용자가 직접 실행하는 쪽이 안전합니다.

현재 등록된 잡은 11개이고 이름이 `PROD-<서비스>` 형식이라, 부동산 화면은 `PROD-SJ-LAB-ESTATE-WEB`
으로 맞췄습니다.

## 3. 바뀐 파일

| 파일 | 내용 |
|---|---|
| `docs/jenkins/sj-lab-estate-web-job-config.xml` | **신규** — 잡 가져오기용 설정 |
| `docs/jenkins/README.md` | **신규** — 잡 목록·이름 규칙·만드는 방법·준비물 |
| `scripts/make-jenkins-job-config.py` | **신규** — groovy → XML 생성기 |
| `CLAUDE.md` | 위 구조를 규칙에 반영 |
| `history/history_v4.6.md` + 공유 페이지 2곳 | 이 기록 |

## 남은 이야기

1. **잡 생성**(사람) — 화면 잡부터. 그다음 조회 서버 잡은 같은 방법으로 XML 을 만들어 쓰면 됩니다
2. 웹서버 노드에 `mkdir -p /respal/deploy-estate` (화면 잡의 스테이징 경로)
3. ArgoCD 에 `sj-lab-estate` Application 등록 + 운영 DB 표·Secret
4. 전월세 보증금 재수집(v4.4 버그) — 시점 결정 필요
