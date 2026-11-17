# 지금 실행할 쿠버네티스 명령

**사용자가 직접 실행하는 명령만 모은 파일입니다.** 위에서 아래로 순서대로 실행하세요.
끝난 항목은 `[x]` 로 바꿔 두면 다음에 이어서 하기 쉽습니다.

- 명령의 배경·진단 방법은 [`k8s-runbook.md`](k8s-runbook.md)
- Secret 의 이름·용도·교체 절차는 [`k8s-secrets.md`](k8s-secrets.md)
- 이 작업의 전체 기록은 [`../history/history_v4.25.md`](../history/history_v4.25.md)

**지금 상태**: 코드·차트는 Secret 방식으로 바꿔 두었고 **아직 커밋·배포하지 않았습니다.**
Secret 을 먼저 만들어야 배포해도 서비스가 뜹니다.

---

## [ ] 1. 클러스터에 붙는지 확인

```powershell
kubectl config current-context
kubectl get pods -n sj-lab
```

**성공 기준**: 파드 목록이 나온다.

`current-context is not set` 이면 kubeconfig 가 없는 것입니다. 마스터 노드에서
`cat ~/.kube/config` 내용을 복사해 아래에 붙여 넣으세요.

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.kube"
notepad "$env:USERPROFILE\.kube\config"
```

`server:` 주소가 `127.0.0.1`·내부 IP 면 **마스터의 공인 주소로 바꿔야** 외부에서 닿습니다.

---

## [ ] 2. Secret 만들기

```powershell
cd C:\developer\workspace\sj-lab
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\create-service-secrets.ps1 -WhatIfOnly
```

**성공 기준**: Secret 6개가 보이고 각 키에 `길이 N` 이 찍힌다(값은 안 보임).
`값이 없는 키:` 가 나오면 멈추고 알려 주세요.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\create-service-secrets.ps1
```

**성공 기준**: 각 Secret 아래에 `적용 완료`, 그 뒤에 `재시작 요청`.

---

## [ ] 3. 만들어졌는지 확인

```powershell
kubectl get secret -n sj-lab | findstr /i "credentials api-keys auth"
kubectl get pods -n sj-lab
```

**성공 기준**: 아래 6개가 보인다.

```
scheduler-db-credentials
scheduler-api-keys
map-db-credentials
qfieldsync-credentials
postgres-auth
postgres-qfield-auth
```

파드는 아직 **옛 이미지**라 Secret 과 무관하게 정상이어야 합니다.

---

## [ ] 4. 여기까지 되면 에이전트에게 알려 주세요

커밋·푸시를 진행합니다(배포가 시작됩니다). 배포 대상은 `sj-lab-scheduler` ·
`mapservice-rest` · `sj-qfieldsync` · `sj-lab-k8s-manifests` 입니다.

---

## [ ] 5. 배포 후 확인

```powershell
kubectl get pods -n sj-lab
kubectl rollout status deployment/mapservice-rest -n sj-lab
```

```powershell
curl.exe -s https://api.sj-lab.co.kr/estate/status
curl.exe -s -o NUL -w "%{http_code}`n" https://sj-lab.co.kr/map/
```

**성공 기준**: 파드가 `Running`, `/estate/status` 가 `ready:true`, 지도 화면이 `200`.

### 파드가 못 뜨면

```powershell
kubectl describe pod -n sj-lab <파드이름> | findstr /i "secret error reason message"
kubectl logs -n sj-lab deploy/mapservice-rest --tail=30
```

`[중단] DB 접속 환경변수가 없습니다: ...` 가 보이면 그 Secret 의 키 이름이 틀린 것입니다.
2번을 다시 돌리면 됩니다. 급하면 되돌리기:

```powershell
kubectl rollout undo deployment/mapservice-rest -n sj-lab
```

---

## [ ] 6. (배포 확인 후) 비밀번호·키 교체

**여기부터가 실제로 노출을 무효화하는 단계입니다.** 앞 단계가 끝난 뒤에 하세요.

### 6-1. DB 비밀번호 바꾸기

새 비밀번호를 만듭니다(화면에 한 번만 보입니다. 32자 이상, 다른 곳과 재사용 금지).

```powershell
-join ((48..57) + (65..90) + (97..122) + @(45,46,95) | Get-Random -Count 40 | ForEach-Object { [char]$_ })
```

DB 에 적용합니다. 계정 이름과 새 비밀번호를 채워 실행하세요
(절차·주의는 `../db/estate/estate_rotate_credentials.sql`).

```sql
ALTER ROLE "<계정이름>" WITH PASSWORD '<새 비밀번호>';
```

### 6-2. 로컬 비밀값 파일 고치기

`C:\developer\workspace\sj-lab\.claude\settings.local.json` 의 `env` 에서 아래 두 값의
**비밀번호 부분**을 새 값으로 바꿉니다(`@`·`:`·`/`·`#` 는 URL 인코딩, `@` → `%40`).

```
SJLAB_OWNER_DB_DSN
QFC_DB_DSN      ← QFieldCloud DB 비밀번호도 바꿨다면
```

### 6-3. Secret 갱신 + 재시작

```powershell
cd C:\developer\workspace\sj-lab
powershell -ExecutionPolicy Bypass -File scripts\create-service-secrets.ps1
```

### 6-4. 확인

```powershell
kubectl get pods -n sj-lab
curl.exe -s https://api.sj-lab.co.kr/estate/status
```

### 6-5. 포털에서 직접 재발급 (에이전트가 할 수 없음)

| 대상 | 영향 |
|---|---|
| 공공데이터포털 서비스 키 | 버스·약국·병원·실거래·시설 수집 전반 |
| 국가교통정보센터(ITS) 키 | CCTV |
| 생활안전지도 키 | 편의점·관공서 |
| QFieldCloud admin 비밀번호 | 현장조사 동기화 · 첨부 재생 (**DB 와 같은 값을 쓰지 말 것**) |

받은 뒤 로컬 비밀값 파일의 해당 키를 고치고 **6-3 을 다시** 실행합니다.
