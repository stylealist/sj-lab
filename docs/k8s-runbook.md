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

## 5-1. DB 에 SQL 한 줄 돌리기 (psql 이 없을 때)

작업 PC 에 `psql` 이 없고 DB 툴(DBeaver 등)은 문장을 트랜잭션으로 감싸 **`CREATE INDEX
CONCURRENTLY` 같은 명령이 거부될 때**(`SQL Error [25001] ... cannot run inside a transaction
block`) 쓰는 길입니다. DB 파드 안의 `psql` 은 기본이 auto-commit 입니다.

```powershell
# 1) DB 파드 이름 찾기(네임스페이스는 환경에 맞게)
kubectl get pods -A | findstr /i postgres

# 2) 그 파드 안에서 한 줄 실행 — 비밀번호는 파드 안 환경변수를 그대로 쓴다(셸에 적지 않는다)
kubectl exec -n <네임스페이스> <파드이름> -- sh -lc "psql -U $POSTGRES_USER -d sjlab -c \"<SQL 한 줄>\""
```

- **비밀값을 명령에 적지 말 것** — 파드 안의 `$POSTGRES_USER`·`$PGPASSWORD` 를 쓰거나,
  대화형(`-it` + `psql`)으로 들어가 실행합니다.
- `CONCURRENTLY` 는 **한 명령에 하나씩**. 여러 문장을 묶어 보내면 같은 오류가 납니다.
- 오래 걸리는 작업(인덱스 만들기 수 분)은 연결이 끊기면 중단되므로, 끊겼을 때 **못 쓰는
  인덱스가 남았는지**(`indisvalid`) 확인하는 쿼리까지 스크립트에 함께 적어 둡니다.

## 5-2. JVM 보안 완화 옵션 확인 (CVE-2026-114938 · Java4Shell)

OpenJDK **17.0.6 이상 x86-64(AVX-512 VBMI)** 의 Base64 디코드 인트린식 결함입니다(ARM64 해당 없음,
패치 2026-11-17 공개). 2026-11-18 에 **Java 서비스 7개 + geoserver 차트의 `JAVA_TOOL_OPTIONS` 에
`-XX:-UseBASE64Intrinsics` 를 덧붙여** 임시로 막아 두었습니다.

```powershell
# 1) 이 파드가 애초에 영향받는지 / 완화가 먹었는지 — false 면 인트린식이 꺼진 것(정상)
kubectl exec -n sj-lab <파드이름> -- java -XX:+PrintFlagsFinal -version | findstr UseBASE64Intrinsics

# 2) 환경변수가 제대로 들어갔는지(타임존이 함께 남아 있어야 한다)
kubectl exec -n sj-lab <파드이름> -- printenv JAVA_TOOL_OPTIONS

# 3) 롤아웃이 끝났는지
kubectl get pods -n sj-lab -o wide
kubectl rollout status deploy/<이름> -n sj-lab
```

- **CPU 가 AVX-512 VBMI 를 지원하지 않으면 이 플래그는 원래 `false`** 입니다 — 그때는 넣어도
  바뀌는 것이 없습니다(영향 없음).
- **임시 완화입니다.** 해결은 **패치된 JDK 베이스 이미지로 재빌드**(Jenkins 잡 재실행)이고,
  Dockerfile 이 `eclipse-temurin:17-jdk-alpine`(떠다니는 태그)이라 **코드 변경 없이 잡만 다시**
  돌리면 됩니다. 재빌드 뒤에는 이 옵션을 **빼는 것이 맞습니다**(Base64 성능).
- 같은 이름의 환경변수를 따로 또 선언하면 **뒤엣것만 남아 `-Duser.timezone=Asia/Seoul` 이
  사라집니다.** 반드시 한 값에 이어 붙일 것.

## 6. 참고 — 누가 무엇을 하는가

| 작업 | 누가 |
|---|---|
| `kubectl` 전반(Secret 생성, 재시작, 롤백, 조회) | **사용자** |
| Jenkins 잡 실행 | **사용자** |
| 외부 포털 키 재발급(공공데이터·ITS·생활안전지도·QFieldCloud) | **사용자** |
| 명령·스크립트 만들기, 문서화, 코드·차트 수정 | 에이전트 |
| DB 조회(SELECT) | 에이전트 |
| DB 변경(DDL·DML·DCL) | 스크립트로 남기고 **사용자 승인 후** |
