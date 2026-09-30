# 운영 Secret 정리 (k8s · Jenkins)

운영 클러스터와 Jenkins에 등록된 비밀값의 **이름·용도·확인 방법**만 정리합니다. **값은 이 문서에 절대 적지 말 것** — 이 저장소는 public입니다. 차트가 참조하는 Secret이 바뀌면(`sj-lab-k8s-manifests`의 `secretKeyRef`/`pullSecret`) 이 문서도 같은 작업에서 고칩니다.

## k8s Secret (네임스페이스 `sj-lab`)

| Secret | 키 | 쓰는 곳 → 환경변수 | 필수 여부 | 없으면 |
|---|---|---|---|---|
| `ncp-registry-secret` | (docker-registry 타입) | 모든 사내 서비스 차트의 `imagePullSecrets` — apigateway, discoveryserver, mapservice-rest, sj-lab-scheduler, fast-api-ai, sj-qfieldsync, sj-lab-authserver, jenkins | 필수 | NCP 레지스트리(`sj-lab-registry.kr.ncr.ntruss.com`)에서 이미지를 못 받아 `ImagePullBackOff` |
| `qfield-credentials` | `username`, `password` | mapservice-rest → `QFIELD_USERNAME`, `QFIELD_PASSWORD` | 선택(`optional: true`) | 파드는 정상, 시설물 첨부(사진·음성·영상) 중계 API만 503 |
| `auth-jwt-secret` | `secret` | sj-lab-authserver → `AUTH_JWT_SECRET` | **필수**(optional 아님) | 파드가 `CreateContainerConfigError`로 뜨지 않음(의도된 동작 — 공개 기본값으로 서명하지 않기 위함) |
| `auth-demo-credentials` | `username`, `password` | sj-lab-authserver → `AUTH_DEMO_USERNAME`, `AUTH_DEMO_PASSWORD` | 선택(`optional: true`) | 파드는 정상, 로그인 페이지의 "체험용 계정으로 로그인" 버튼만 503 |
| `openapi-db-credentials` | `url`, `username`, `password` | sj-lab-openapi → `OPENAPI_DB_URL`, `OPENAPI_DB_USERNAME`, `OPENAPI_DB_PASSWORD` | **키 기능을 켠 경우 필수**(차트 `apiKey.enabled: true`, 2026-09-30 켜짐) | 파드가 뜨지 않음 — 접속 주소가 비면 `ApiKeyStoreConfig`가 기동을 막는다(의도된 동작). 차트를 `false`로 되돌리면 Secret 없이도 뜨고 키 API만 503 |

**`openapi-db-credentials`의 계정은 `openapi_svc`입니다**(2026-09-30 분리). `api` 스키마 두 표에만 권한이 있는 전용 계정이며, superuser가 아닙니다. 다른 서비스나 사람 계정으로 되돌리지 마세요 — 이 서비스가 필요한 건 아래가 전부이고, 실제로 이 권한만으로 발급·사용량 기록·폐기가 모두 동작하는 것을 확인했습니다.

| 대상 | 권한 | 쓰이는 곳 |
|---|---|---|
| 스키마 `api` | `USAGE` | 접속 |
| `api.openapi_api_key` | `SELECT`, `INSERT`, `UPDATE` | 목록 · 발급 · 폐기(`use_yn`) · `last_used_at` 갱신 |
| `api.openapi_api_usage` | `SELECT`, `INSERT`, `UPDATE` | 하루 사용량 집계 · 호출 기록 |
| 시퀀스 2개 | `USAGE`, `SELECT` | `key_id` · `usage_id` 생성 |

`DELETE`는 필요 없습니다(폐기는 행 삭제가 아니라 `use_yn='n'` 갱신). 로컬도 같은 계정을 `.claude\settings.local.json`의 `env`에 두고 `local-stack.ps1`이 읽어 넣습니다.

그 밖에 `kubernetes-dashboard` 네임스페이스의 `kubernetes-dashboard-certs` 등은 dashboard 차트가 직접 만드는 Secret이라 따로 관리하지 않습니다. `sj-qfieldsync`는 k8s Secret을 쓰지 않습니다.

### 주의

- `auth-jwt-secret`: authserver가 발급하는 로그인 토큰의 서명 키입니다. **바꾸면 그때까지 발급된 모든 토큰이 무효**가 되어 사용자 전원이 다시 로그인해야 합니다. 32바이트 이상이어야 합니다(짧으면 기동 실패).
- `auth-demo-credentials`: 포트폴리오 방문자용 QFieldCloud 체험 계정입니다. 이 계정은 QFieldCloud **어떤 프로젝트에도 멤버로 넣지 말 것**(우리 로그인은 계정 존재만 확인). 비밀번호를 코드·문서에 적지 말 것(2026-09-22 처음엔 로그인 페이지 JS에 넣었다가 서버 처리로 바꾸고 비밀번호를 교체함).
- `qfield-credentials`: 첨부 중계용 운영 QFieldCloud 계정입니다. 체험 계정과 섞지 말 것.

## 로컬 개발에서는

k8s Secret이 없으므로 다음처럼 대신합니다(값은 git 제외 파일 `.claude/settings.local.json`의 `env`에만 둠).

| 운영 Secret | 로컬 |
|---|---|
| `auth-jwt-secret` | 필요 없음 — `local` 프로파일에서 로컬 전용 기본값 사용(운영 프로파일에선 이 기본값을 거부) |
| `auth-demo-credentials` | `AUTH_DEMO_USERNAME`/`AUTH_DEMO_PASSWORD` → `scripts\local-stack.ps1`이 authserver 기동 시 주입 |
| `qfield-credentials` | `QFIELD_USERNAME`/`QFIELD_PASSWORD` → `scripts\local-stack.ps1`이 mapservice-rest 기동 시 주입 |
| `ncp-registry-secret` | 필요 없음(로컬은 jar 직접 실행) |
| `openapi-db-credentials` | 기본은 필요 없음 — `OPENAPI_API_KEY_ENABLED`가 꺼져 있으면 키 API만 503이고 공개 조회는 정상. 로컬에서 키 기능을 써 보려면 `OPENAPI_DB_URL`/`OPENAPI_DB_USERNAME`/`OPENAPI_DB_PASSWORD`와 `OPENAPI_API_KEY_ENABLED=true`를 넣어 띄운다(`api` 스키마 두 표에 SELECT·INSERT·UPDATE 권한 필요) |

## Jenkins Credentials

k8s Secret이 아니라 Jenkins(`Manage Jenkins` → `Credentials`)에 등록된 값입니다. 서비스별 파이프라인이 공통으로 씁니다.

| Credential ID | 종류 | 용도 |
|---|---|---|
| `github_login` | Username/Password | 서비스 저장소 checkout |
| `ncp-api-key` | Username/Password (Access Key / Secret Key) | NCP 레지스트리 `docker login` 후 이미지 push |
| `GitHub_token` | Secret text | `sj-lab-k8s-manifests`를 clone해 `values.yaml`의 `image.tag`를 커밋·push |

## 확인 명령어

### 목록·키 확인 (값은 안 보임)

```bash
kubectl get secrets -n sj-lab
kubectl describe secret <이름> -n sj-lab        # Data 아래 키 이름과 바이트 길이만 표시
```

### 값 확인 (필요할 때만 — 화면 공유·로그가 남는 터미널에서는 하지 말 것)

Git Bash / Linux:

```bash
kubectl get secret <이름> -n sj-lab -o jsonpath='{.data.<키>}' | base64 -d; echo
# 예: kubectl get secret auth-demo-credentials -n sj-lab -o jsonpath='{.data.username}' | base64 -d; echo
```

PowerShell:

```powershell
$v = kubectl get secret <이름> -n sj-lab -o jsonpath='{.data.<키>}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($v))
```

### 파드에 실제로 주입됐는지

```bash
kubectl exec -n sj-lab deploy/<배포명> -- printenv <환경변수>
# 예: kubectl exec -n sj-lab deploy/sj-lab-authserver -- printenv AUTH_DEMO_USERNAME
```

값 대신 존재 여부만 보고 싶으면 `printenv | grep -c <환경변수>`를 씁니다.

### 파드가 Secret 때문에 못 뜰 때

```bash
kubectl get pods -n sj-lab -l app=<차트명>
kubectl describe pod -n sj-lab -l app=<차트명> | tail -20   # Events에 "secret ... not found" 확인
```

## 생성·변경 명령어

```bash
# 새로 만들기 (generic)
kubectl create secret generic <이름> -n sj-lab --from-literal=<키>=<값> [--from-literal=<키>=<값>]

# 이미 있는 Secret 값 바꾸기 (덮어쓰기)
kubectl create secret generic <이름> -n sj-lab --from-literal=<키>=<값> --dry-run=client -o yaml | kubectl apply -f -

# 값을 바꾼 뒤에는 파드를 재시작해야 반영됨 (환경변수는 기동 시에만 읽음)
kubectl rollout restart deploy/<배포명> -n sj-lab
```

`auth-jwt-secret`처럼 임의의 긴 값이 필요하면 `openssl rand -base64 32`로 만듭니다.
