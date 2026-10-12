# history v4.9 — 부동산 조회 서버 배포 잡 + ArgoCD 등록 정의

- **날짜**: 2026-10-12
- **영향 저장소**: `sj-lab`
- **이전 버전**: [history_v4.8.md](history_v4.8.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| 부동산 실거래 (운영) | https://sj-lab.co.kr/estate/ | 화면 배포 완료 (잡 #6 성공) |
| 부동산 조회 API (운영) | https://api.sj-lab.co.kr/estate/status | 503 → 이번 작업으로 배포 준비 |
| Jenkins | https://jenkins.sj-lab.co.kr | 서버 잡 생성 대상 |

## 실행한 프롬프트

```
이제 -web은 연결했어 서버도 jenkins 작성해줘 (openapi 잡 원문 참고)
```

## 1. 화면 잡은 끝났습니다

빌드 **#6 성공**(초록)을 확인했습니다. 앞선 다섯 번의 실패는 모두 이번 주 기록(v4.7·v4.8)에
적어 둔 두 가지 원인이었습니다.

## 2. 조회 서버 잡을 만들었습니다

공개 API 잡(`sj-lab-openapi`)과 **같은 구조**입니다 — 도구·스테이지·자격 증명이 모두 같습니다.

```
jar 빌드 → 이미지 빌드·push → 매니페스트의 image.tag 커밋 → ArgoCD 동기화 → 롤아웃
```

| 값 | 내용 |
|---|---|
| 잡 이름 | `PROD-SJ-LAB-ESTATE` |
| 이미지 | `sj-lab-registry.../sj-lab-estate` |
| 차트 | `sj-lab-k8s-manifests/sj-lab-estate` |
| 확인(Verify) | `GET /estate/status` |

**확인을 데이터 조회가 아니라 `status` 로 하는 이유**: 이 서비스는 DB 접속 정보가 없어도 뜨고
그때는 조회만 503 입니다. 데이터로 확인하면 "배포는 됐는데 DB 준비가 안 된 상태"와 "배포 실패"를
구분할 수 없습니다. `status` 는 두 경우 모두 200 이고 응답의 `ready` 로 갈립니다.

5분 안에 응답이 없으면 **"ArgoCD 등록을 확인하라"**는 안내를 찍게 했습니다 — 첫 배포에서 가장
흔한 원인이기 때문입니다.

## 3. ArgoCD 등록도 글로 남겼습니다

Jenkins 잡은 이미지를 올리고 태그를 커밋하는 데까지만 합니다. **배포 도구에 서비스가 등록돼
있지 않으면 태그만 조용히 올라가고 클러스터에서는 아무 일도 일어나지 않습니다.**
지금까지는 화면에서 손으로 만들어 왔는데, 같은 설정을 파일로 남겼습니다.

```
kubectl apply -f docs/argocd/sj-lab-estate-application.yaml
```

화면에서 만들 때 넣을 값도 같은 파일 주석에 적어 두었습니다.

## 4. 바뀐 파일

| 파일 | 내용 |
|---|---|
| `docs/jenkins/sj-lab-estate-pipeline.groovy` | 실패 안내에 ArgoCD 등록 확인 문구 추가 |
| `docs/jenkins/sj-lab-estate-job-config.xml` | **신규** — 서버 잡 가져오기용 설정 |
| `docs/argocd/sj-lab-estate-application.yaml` | **신규** — ArgoCD Application 정의(+ 화면 입력값·확인 명령) |
| `docs/jenkins/README.md`, `docs/system-architecture.md`, `CLAUDE.md` | 새 서비스는 **차트·잡·ArgoCD 세 가지**가 필요하다는 규칙·경로 |
| `history/history_v4.9.md` + 공유 페이지 2곳 | 이 기록 |

## 다음 순서 (사람이 하는 일)

1. **ArgoCD 등록** — 위 `kubectl apply` 한 번(또는 화면에서 같은 값으로 생성)
2. **Jenkins 잡 생성** `PROD-SJ-LAB-ESTATE` → 빌드
3. **운영 DB** — `db/estate/estate_apt.sql` 실행 + `estate-db-credentials` Secret
   (조회 전용 계정, 권한 목록은 `docs/k8s-secrets.md`). 없어도 배포는 성공하고 화면은 안내 배너를 띄웁니다
4. 전월세 보증금 재수집(v4.4 버그) — 시점 결정 필요
