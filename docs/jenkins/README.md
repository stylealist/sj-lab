# Jenkins 잡 원본

운영 Jenkins(`https://jenkins.sj-lab.co.kr`)에 등록된 **파이프라인 스크립트의 원본**을 저장소에 둡니다.
Jenkins 안의 값이 진짜 동작하는 것이고, 이 폴더는 그것을 읽고·검토하고·되돌릴 수 있게 하는 사본입니다.
**잡을 고치면 같은 작업에서 여기 파일도 갱신할 것**(`CLAUDE.md` 규칙).

## 파일

| 파일 | 대상 잡 | 비고 |
|---|---|---|
| `sj-lab-hub-pipeline.groovy` | `PROD_SJ-LAB-HUB-FRONT(REACT)` | 허브. **하위 사이트(map·openapi·estate) 제외 목록**이 여기 있음 |
| `sj-lab-mapservice-pipeline.groovy` | `PROD-SJ-LAB-MAPSERVICE` | 지도(무빌드 정적) |
| `sj-lab-openapi-web-pipeline.groovy` | `PROD-SJ-LAB-OPENAPI-WEB` | API 활용 페이지 |
| `sj-lab-estate-web-pipeline.groovy` | `PROD-SJ-LAB-ESTATE-WEB` | 부동산 화면 |
| `sj-lab-openapi-pipeline.groovy` | `PROD-SJ-LAB-OPENAPI` | 공개 API 서비스(이미지) |
| `sj-lab-estate-pipeline.groovy` | `PROD-SJ-LAB-ESTATE`(생성 예정) | 부동산 조회 서버(이미지). ArgoCD Application 등록이 선행돼야 한다 |
| `*-original.groovy` | - | 수정 전 원본(롤백용). 되돌리면 그때의 문제도 함께 돌아옴 |
| `*-job-config.xml` | - | 잡 설정까지 담은 가져오기용 XML(아래 참고) |

잡 이름은 `PROD-<서비스>` 형식입니다(허브만 예외적으로 `PROD_SJ-LAB-HUB-FRONT(REACT)`).
현재 등록된 잡 목록은 로그인 없이도 확인할 수 있습니다.

```
curl -s "https://jenkins.sj-lab.co.kr/api/json?tree=jobs[name,color]"
```

## 새 잡 만들기

### 방법 A — 웹 UI (권장: 한 번만 할 일)

1. `새로운 Item` → 이름 `PROD-SJ-LAB-ESTATE-WEB` → **Pipeline** 선택
2. `GitHub project` 체크 → `https://github.com/stylealist/sj-lab-estate-web/`
3. `빌드 유발` → **GitHub hook trigger for GITScm polling** 체크
4. `Pipeline` → `Definition: Pipeline script` → 이 폴더의 `*-pipeline.groovy` **전문을 붙여 넣기**
5. 저장 → `지금 빌드`

### 방법 B — API 로 한 번에 (config.xml)

`*-job-config.xml` 은 위 2~4단계를 모두 담고 있습니다. 계정과 **API 토큰**이 필요합니다
(토큰은 Jenkins → 내 계정 → 설정에서 발급. **저장소·문서·대화에 적지 말 것**).

```bash
# 만들기
curl -X POST "https://jenkins.sj-lab.co.kr/createItem?name=PROD-SJ-LAB-ESTATE-WEB" \
     -u "<계정>:<API 토큰>" -H "Content-Type: text/xml" \
     --data-binary @docs/jenkins/sj-lab-estate-web-job-config.xml

# 이미 있는 잡 갱신
curl -X POST "https://jenkins.sj-lab.co.kr/job/PROD-SJ-LAB-ESTATE-WEB/config.xml" \
     -u "<계정>:<API 토큰>" -H "Content-Type: text/xml" \
     --data-binary @docs/jenkins/sj-lab-estate-web-job-config.xml
```

XML 은 파이프라인 원본(`*-pipeline.groovy`)을 그대로 읽어 만듭니다 — **groovy 가 단일 소스**입니다.
groovy 를 고쳤으면 XML 도 다시 만드세요.

```bash
python scripts/make-jenkins-job-config.py docs/jenkins/sj-lab-estate-web-pipeline.groovy \
    --repo https://github.com/stylealist/sj-lab-estate-web \
    --description "부동산 실거래 화면 빌드 → 웹서버 html/estate 배포"
```

## 잡을 만들기 전에 준비할 것

| 대상 | 준비물 |
|---|---|
| 정적 화면 잡(허브·지도·활용 페이지·부동산) | 웹서버 노드에 **잡 전용 스테이징 경로**(`mkdir -p /respal/deploy-estate`), nginx 의 해당 `location` |
| 이미지 잡(서비스) | `sj-lab-k8s-manifests` 의 차트, **ArgoCD Application 등록**(없으면 태그만 올라감). 부동산은 `docs/argocd/sj-lab-estate-application.yaml` 를 `kubectl apply` 하면 된다 |
| 공통 자격 증명 | `github_login` · `ncp-api-key` · `GitHub_token` (용도는 `docs/k8s-secrets.md`) |

## 실제로 겪은 문제 (2026-10-12, 부동산 화면 첫 빌드)

첫 빌드가 배포 단계에서 깨졌습니다. 두 가지가 겹친 것이고, 둘 다 **원격 명령(`execCommand`)에만**
해당합니다.

```
bash: -c: line 9: syntax error near unexpected token ';&'
```

1. **XML 안의 script 를 사람이 복사해 UI 에 붙여 넣으면 escape 가 그대로 들어갑니다.**
   `>` 는 `&gt;`, `&` 는 `&amp;` 로 적혀 있으므로 원격 bash 가 `2&gt;&amp;1` 를 받고 죽습니다.
   → **잡에 넣을 때는 `*-pipeline.groovy` 를 그대로 붙여 넣으세요.** XML 은 API 로 POST 할 때만 씁니다
   (그 경로에서는 Jenkins 가 되돌려 주므로 문제가 없습니다).
2. **Publish over SSH 는 `execCommand` 에 변수 치환을 합니다** — `$$` 가 `$` 로 줄어듭니다
   (로그에 `${DST}.new.$` 로 찍혔습니다). 임시 디렉터리 이름에 `$$` 를 쓰지 마세요.

그래서 정적 사이트 잡의 `execCommand` 는 **꺾쇠(`>`)·앰퍼샌드(`&`)·`$$` 없이** 쓰는 것을 규칙으로
합니다. 리다이렉션과 `&&`·`||` 대신 `if` 문을 쓰면 같은 일을 할 수 있습니다
(`sj-lab-estate-web-pipeline.groovy` 가 그 형태입니다).

### 두 번째 실패 — Verify 의 표식이 틀렸다

고친 뒤 배포는 성공했는데 **Verify 에서 떨어졌습니다.** 찾던 문자열이 `index.html` 에 없었기 때문입니다.

- 화면 제목은 `<title>SJ-LAB 부동산 실거래</title>` 입니다.
- 제가 넣었던 `SJ 부동산 실거래` 는 **헤더 로고 문구**이고, 그것은 `bundle.js` 안에 있습니다.
- 그래서 **표식은 반드시 `index.html` 안에 있는 문자열**(보통 `<title>`)로 잡습니다.
  빌드 결과를 직접 열어 확인하는 게 가장 빠릅니다: `grep -o '<title>[^<]*' build/index.html`

| 사이트 | 표식 |
|---|---|
| 허브 | `<title>SJ-LAB</title>` |
| 지도 | `js/auth-gate.js` |
| API 활용 페이지 | `SJ-LAB OpenAPI` |
| 부동산 | `SJ-LAB 부동산 실거래` |

### 그때 생긴 뒷정리

스크립트가 `mkdir -p` 까지 실행한 뒤 죽어서 **빈 `html/estate` 디렉터리가 남았습니다.**
그 상태에서 `/estate/` 는 404 가 아니라 **403**(디렉터리는 있는데 index 파일이 없음)이 됩니다.
배포가 한 번 성공하면 해결되므로 따로 지울 필요는 없습니다. 증상으로 외워 두면 편합니다.

| `/estate/` 응답 | 뜻 |
|---|---|
| 404 | 디렉터리도 없음 = 한 번도 배포 안 됨(nginx `location /estate/` 가 반영된 상태) |
| 403 | 디렉터리는 있고 파일이 없음 = 배포가 중간에 실패 |
| 200 + 허브 화면 | 파일이 없고 nginx `location /estate/` 도 아직 반영 전(SPA 폴백) |
| 200 + 부동산 화면 | 정상 |

## 주의

- **하위 정적 사이트를 추가하면 허브 잡의 제외 목록(`--exclude`, `find ! -name`)에 그 폴더를 넣을 것.**
  빠뜨리면 허브 배포가 그 사이트를 지웁니다(지도에서 반복 발생 → `docs/deploy-static-sites.md`).
- 여러 서비스 잡이 동시에 매니페스트를 push 하면 한 잡이 `cannot lock ref` 로 실패할 수 있습니다.
  이미지는 이미 올라가 있으니 **그 잡만 재실행**하면 됩니다.
- `image.tag` 는 Jenkins 가 관리하는 값입니다. 사람이 임의로 낮추지 마세요.
