# 쿠버네티스 실행 명령 모음 (사용자 실행용)

**쿠버네티스 작업은 에이전트가 실행하지 않습니다. 명령만 만들어 드리고, 실행은 사용자가 합니다**
(2026-11-16 정해진 방식). 그래서 이 문서는 "설명"이 아니라 **그대로 복사해 쓰는 명령 모음**입니다.
새 작업이 생기면 에이전트가 이 문서에 그 작업의 명령 블록을 추가합니다.

관련 문서: Secret 의 이름·용도는 `k8s-secrets.md`, 배포 경로(Jenkins → ArgoCD)는
`system-architecture.md` 의 "배포 경로", 로컬 포트·기동은 `dev-environment.md`.

## 0. 준비 — 클러스터에 붙기

에이전트 작업 PC(`C:\developer\workspace`)에는 `kubectl` 프로그램만 있고 **접속 설정이 없습니다**
(2026-11-16 확인: `kubectl config current-context` → `current-context is not set`).
명령을 실행하는 곳에서 아래가 되는지 먼저 확인하세요.

```powershell
kubectl config current-context
kubectl get nodes
kubectl get pods -n sj-lab
```

붙지 않으면 kubeconfig 를 가져옵니다.

```bash
# 마스터 노드에서 내용을 복사
cat ~/.kube/config
```

```powershell
# 작업 PC 에 저장(붙여넣기)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.kube"
notepad "$env:USERPROFILE\.kube\config"
```

- `server:` 주소가 `127.0.0.1`·내부 IP 면 외부에서 안 닿습니다 — 마스터의 **공인 주소**로 바꾸세요.
- 이 파일은 **클러스터 전체 권한**입니다. 저장소에 올리지 마세요(`~/.kube/config` 는 git 밖).
- NKS 콘솔을 쓰면 **클러스터 상세 → kubeconfig 다운로드**가 더 간단합니다.

## 1. 상태 보기

```powershell
kubectl get pods -n sj-lab
kubectl get deploy -n sj-lab
kubectl get svc -n sj-lab
kubectl get secret -n sj-lab
```

```powershell
# 로그(마지막 50줄)
kubectl logs -n sj-lab deploy/mapservice-rest   --tail=50
kubectl logs -n sj-lab deploy/sj-lab-scheduler  --tail=50
kubectl logs -n sj-lab deploy/sj-lab-estate     --tail=50
kubectl logs -n sj-lab deploy/sj-qfieldsync     --tail=50
```

운영 동작 확인:

```powershell
curl.exe -s https://api.sj-lab.co.kr/estate/status
curl.exe -s -o NUL -w "%{http_code}`n" https://sj-lab.co.kr/map/
curl.exe -s -o NUL -w "%{http_code}`n" https://sj-lab.co.kr/estate/
```

## 2. 파드가 안 뜰 때

```powershell
kubectl get pods -n sj-lab
kubectl describe pod -n sj-lab <파드이름> | findstr /i "error reason message secret image"
kubectl logs -n sj-lab <파드이름> --previous --tail=50
```

자주 보는 증상:

| 증상 | 뜻 |
|---|---|
| `ImagePullBackOff` | 레지스트리에서 이미지를 못 받음 — `ncp-registry-secret` 확인 |
| `CreateContainerConfigError` | 참조하는 Secret·키가 없음(`optional` 아닌 항목) |
| `CrashLoopBackOff` | 떴다가 죽음 — 위 `logs --previous` 로 원인 확인 |
| 게이트웨이가 503 | 롤아웃 중(옛 파드 종료 ~ 새 파드 Eureka 등록 사이). 몇 초 뒤 재확인 |

## 3. 재시작 · 되돌리기

```powershell
kubectl rollout restart deployment/<이름> -n sj-lab
kubectl rollout status  deployment/<이름> -n sj-lab

kubectl rollout history deployment/<이름> -n sj-lab
kubectl rollout undo    deployment/<이름> -n sj-lab
```

**DB 파드는 함부로 재시작하지 마세요** — 모든 서비스가 함께 끊깁니다.

## 4. Secret 보기 · 만들기

```powershell
# 목록과 키 이름만(값은 안 보임)
kubectl get secret -n sj-lab
kubectl get secret <이름> -n sj-lab -o jsonpath="{.data}"

# 파드에 주입됐는지 이름만 확인(값은 찍지 말 것)
kubectl exec -n sj-lab deploy/<이름> -- printenv | findstr /i "<환경변수이름>"
```

새로 만들거나 갱신할 때는 **셸 히스토리에 값이 남지 않게** `read -s` 로 입력받습니다.

```bash
read -rsp '비밀번호: ' PW; echo

kubectl create secret generic <이름> -n sj-lab \
  --from-literal=username='<계정>' \
  --from-literal=password="$PW" \
  --dry-run=client -o yaml | kubectl apply -f -

unset PW
```

- 이미 있으면 위 `--dry-run | apply` 가 덮어씁니다.
- **Secret 은 기동할 때 읽힙니다** — 바꾼 뒤 `rollout restart` 를 해야 반영됩니다.
- DB 접속 주소는 클러스터 안 서비스 이름(`postgresql-sjlab:5432`)으로 넣습니다. 파드가
  공인 IP·NodePort 로 돌아 나갈 필요가 없고, 그 주소는 바뀔 수 있습니다.

## 5. ArgoCD

`sj-lab-k8s-manifests` 에 push 하면 ArgoCD 가 차트를 반영합니다.

```powershell
kubectl get applications -n argocd
kubectl describe application <이름> -n argocd | findstr /i "sync health message"
```

세 서비스(`mapservice-rest`·`sj-lab-scheduler`·`sj-qfieldsync`)의 Application 정의는 저장소에 없고
화면에서 손으로 만든 것입니다 — 자동 동기화 여부는 위 명령으로 확인하세요.
저장소에 있는 정의는 `argocd/`(ArgoCD 자신)와 `docs/argocd/sj-lab-estate-application.yaml` 뿐입니다.

## 6. 참고 — 누가 무엇을 하는가

| 작업 | 누가 |
|---|---|
| `kubectl` 전반(Secret 생성, 재시작, 롤백, 조회) | **사용자** |
| Jenkins 잡 실행 | **사용자** |
| 외부 포털 키 재발급(공공데이터·ITS·생활안전지도·QFieldCloud) | **사용자** |
| 명령·스크립트 만들기, 문서화, 코드·차트 수정 | 에이전트 |
| DB 조회(SELECT) | 에이전트 |
| DB 변경(DDL·DML·DCL) | 스크립트로 남기고 **사용자 승인 후** |
