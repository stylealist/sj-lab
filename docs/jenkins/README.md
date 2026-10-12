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
| `sj-lab-estate-web-pipeline.groovy` | `PROD-SJ-LAB-ESTATE-WEB`(생성 예정) | 부동산 화면 |
| `sj-lab-openapi-pipeline.groovy` | `PROD-SJ-LAB-OPENAPI` | 공개 API 서비스(이미지) |
| `sj-lab-estate-pipeline.groovy` | `PROD-SJ-LAB-ESTATE`(생성 예정) | 부동산 조회 서버(이미지) |
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
| 이미지 잡(서비스) | `sj-lab-k8s-manifests` 의 차트, **ArgoCD Application 등록**(없으면 태그만 올라감) |
| 공통 자격 증명 | `github_login` · `ncp-api-key` · `GitHub_token` (용도는 `docs/k8s-secrets.md`) |

## 주의

- **하위 정적 사이트를 추가하면 허브 잡의 제외 목록(`--exclude`, `find ! -name`)에 그 폴더를 넣을 것.**
  빠뜨리면 허브 배포가 그 사이트를 지웁니다(지도에서 반복 발생 → `docs/deploy-static-sites.md`).
- 여러 서비스 잡이 동시에 매니페스트를 push 하면 한 잡이 `cannot lock ref` 로 실패할 수 있습니다.
  이미지는 이미 올라가 있으니 **그 잡만 재실행**하면 됩니다.
- `image.tag` 는 Jenkins 가 관리하는 값입니다. 사람이 임의로 낮추지 마세요.
