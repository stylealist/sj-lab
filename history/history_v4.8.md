# history v4.8 — 부동산 화면 운영 배포 완료(표식·인코딩 두 버그 수정)

- **날짜**: 2026-10-12
- **영향 저장소**: `sj-lab`, `sj-lab-estate-web`
- **이전 버전**: [history_v4.7.md](history_v4.7.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| **부동산 실거래 (운영)** | https://sj-lab.co.kr/estate/ | **배포됨** |
| 허브 (운영) | https://sj-lab.co.kr | 카드 → 부동산 |
| 부동산 조회 API (운영) | https://api.sj-lab.co.kr/estate/status | 503 (조회 서버 미배포) |

## 실행한 프롬프트

```
(openapi 잡 원문 + 두 번째 빌드 로그) estate-web은 현재도 동일하게 에러가 나
```

## 1. 화면은 이미 올라갔습니다

두 번째 빌드 로그를 보면 **배포는 성공**했습니다 — 파일 4개가 웹서버에 들어갔습니다.
실패한 것은 마지막 **확인(Verify) 단계**뿐이었습니다.

```
rsync 실행됨 → index.html · bundle.js · favicon.svg 전송 완료
Verify: curl 은 성공했는데 찾는 문구가 없어 실패
```

## 2. 찾던 문구가 틀렸습니다 (제 실수)

| | 값 |
|---|---|
| 화면 제목(`index.html`) | `SJ-LAB 부동산 실거래` |
| 제가 넣었던 표식 | `SJ 부동산 실거래` ← **헤더 로고 문구** |

헤더 로고 문구는 `bundle.js` 안에 있어서 `index.html` 에는 없습니다. 그래서 정상 배포인데도
"부동산 화면이 아니다"로 떨어졌습니다. 세 곳(부동산 잡 · 허브 잡 · 점검 스크립트)을 제목으로 고쳤고,
**표식은 `index.html` 안의 문자열로 잡는다**는 규칙과 사이트별 표식 표를 문서에 남겼습니다.

## 3. 점검 스크립트에도 같은 종류의 버그가 있었습니다

표식을 고치고 점검 스크립트를 돌렸더니 **여전히 "표식 없음"** 이 나왔습니다. 이유는 다릅니다.

- Windows PowerShell 은 응답 헤더에 문자 인코딩이 없으면 본문을 **ISO-8859-1 로 읽습니다.**
  그래서 한글 표식이 깨진 글자와 비교돼 영원히 틀립니다.
- 다른 사이트 표식은 모두 영문(`SJ-LAB OpenAPI` 등)이라 이 문제가 드러나지 않았습니다.
- 본문을 **UTF-8 로 직접 디코딩**하도록 고쳤습니다.

고친 뒤 네 사이트 모두 정상입니다.

```
[정상] 허브    https://sj-lab.co.kr/
[정상] 지도    https://sj-lab.co.kr/map/
[정상] API     https://sj-lab.co.kr/openapi/
[정상] 부동산  https://sj-lab.co.kr/estate/
```

## 4. 운영에서 지금 어디까지 됐나

| 조각 | 상태 |
|---|---|
| 부동산 화면 | **배포 완료** |
| 게이트웨이 `/estate/**` 경로 | **반영됨**(게이트웨이가 자동 재배포됨) |
| 조회 서버(`sj-lab-estate`) | **미배포** → `/estate/status` 가 503 |
| 옛 경로(`/fast-api-ai/estate/...`) | 404 (의도대로 제거됨) |

조회 서버가 없으니 화면에 데이터가 비어 보입니다. 그 상태에서 **빨간 오류만 뜨면 "고장난 사이트"로
보이므로**, 503·404 일 때는 서버가 "준비되지 않았다"고 답한 것과 같은 **안내 배너**를 띄우게
고쳤습니다(화면 구성은 그대로 보입니다).

## 5. 바뀐 파일

| 저장소 | 파일 | 내용 |
|---|---|---|
| `sj-lab` | `docs/jenkins/sj-lab-estate-web-pipeline.groovy` | Verify 표식을 제목으로 + 이유 주석 |
| | `docs/jenkins/sj-lab-hub-pipeline.groovy` | 부동산 확인 표식 수정 |
| | `docs/jenkins/sj-lab-estate-web-job-config.xml` | 재생성 |
| | `docs/jenkins/README.md` | "표식은 index.html 안에서 잡는다" + 사이트별 표식 표 |
| | `scripts/check-prod-sites.ps1` | 표식 수정 + **본문 UTF-8 디코딩** |
| `sj-lab-estate-web` | `src/App.js` | 조회 서버 미배포(503·404)면 안내 배너로 |

## 다음 할 일

1. **부동산 화면 잡 재실행** → 이제 Verify 까지 통과합니다(이미 배포된 내용과 같아도 한 번 돌려 두면 깔끔)
2. **조회 서버 배포** — Jenkins 잡 생성 + ArgoCD Application 등록 + 운영 DB 표·Secret.
   그때까지 화면은 안내 배너를 띄웁니다
3. 전월세 보증금 재수집(v4.4 버그) — 시점 결정 필요
