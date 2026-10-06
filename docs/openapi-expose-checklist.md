# 새 백엔드 기능을 공개 API에 함께 여는 규칙

**백엔드에 새 조회 기능을 만들면, 같은 작업에서 공개 API(`sj-lab-openapi`)에도 함께 추가한다.**
나중에 몰아서 하지 않는다 — 미루면 "백엔드에는 있는데 공개 API에는 없는" 상태가 쌓이고,
어느 것이 공개 범위인지 아무도 모르게 된다.

관련 문서: 전체 구조·API 계약 표는 `docs/system-architecture.md`, 공개 API 코드 규칙은
`sj-lab-openapi/CLAUDE.md`.

## 1. 먼저 판단: 이 기능은 열어도 되는가

아래 **네 가지를 모두** 만족하면 "열 수 있는 기능"이다.

| 조건 | 왜 |
|---|---|
| `GET`(조회)이다 | 공개 API는 조회만 연다. 테스트가 `method: GET`을 검사한다 |
| 로그인·외부 계정이 필요 없다 | 공개 API 키 하나로 부를 수 있어야 한다 |
| 응답이 과하게 크지 않다(또는 범위 파라미터로 줄일 수 있다) | 전국 전체를 조립하면 수십 MB가 되고 원천 호출이 타임아웃된다 |
| 개인정보·내부 운영정보가 아니다 | 아무나 부를 수 있는 경로가 된다 |

**열지 않는 것** (확정된 제외 목록)
- 쓰기·수정·삭제 전부 — 내업 기록 등록/수정/삭제, 사진 업로드/삭제
- 첨부 파일 중계(`/map/qfield/.../media`) — QFieldCloud 계정이 필요하다
- 키 관리(`/open-api/keys/**`) — 공개 API가 아니라 본인 전용 관리 API다

**판단이 애매하면 열지 말고 사용자에게 먼저 물어본다.** 한 번 열면 외부에서 쓰기 시작하므로
닫는 것이 어렵다.

## 2. 열 수 있으면: 추가 절차

### 2-1. 카탈로그에 항목 한 개 추가 (이게 전부다)

`sj-lab-openapi/src/main/resources/catalog/api-catalog.json` **한 파일만** 고친다.
컨트롤러·서비스를 새로 만들지 않는다 — 이 파일이 공개 범위이고, 활용 페이지 화면도 이 파일로 그려진다.

```json
{
  "id": "convenience-store",
  "title": "편의점",
  "method": "GET",
  "path": "/v1/convenience-store",
  "upstream": "/map/convenience-store",
  "summary": "편의점 위치를 GeoJSON FeatureCollection 으로 내려줍니다.",
  "responseType": "application/json",
  "params": [
    {
      "name": "bbox",
      "type": "string",
      "required": true,
      "description": "화면 범위(EPSG:3857) minX,minY,maxX,maxY. 필수입니다 — 없으면 …",
      "example": "14120000,4500000,14160000,4530000"
    }
  ]
}
```

| 필드 | 규칙 |
|---|---|
| `id` | 중복 불가. 영문 소문자·하이픈 |
| `path` | **반드시 `/v1/` 로 시작**. 경로 변수는 `{totalId}` 형태 |
| `upstream` | **반드시 `/map/` 로 시작**. mapservice-rest 컨트롤러 매핑을 **그대로** 적는다(표기가 제각각이다: `/map/busStop-info`, `/map/governmentOffice-info`) |
| `method` | `GET` 만 |
| `summary` | 한 문장. 활용 페이지에 그대로 보인다 |
| `params[].in` | 경로 변수면 `"path"`, 쿼리면 생략 |
| `params[].example` | 넣어 두면 활용 페이지가 자동으로 채워 "실행해 보기"가 바로 된다. 경로 변수는 빈 문자열이어도 된다 |
| `params[].required` | 범위를 좁히는 파라미터는 **`true`**(아래 참고) |

**`apiKey` 는 카탈로그에 넣지 않는다.** 서버가 쿼리에서 먼저 떼어내고, 활용 페이지가 화면에만 더해 보여 준다.
넣으면 "모르는 파라미터" 검사와 충돌한다.

### 2-2. 큰 응답이면 범위 파라미터를 필수로

전국 단위 데이터는 `bbox` 같은 범위 파라미터를 `required: true` 로 둔다(공공데이터 6종이 그렇다).
외부에 열린 API라 호출자 한 명이 서비스를 흔들 수 있다. 검증은 `ApiProxyService` 가 하고
없으면 `400 MISSING_PARAMETER` 다.

### 2-3. 같은 작업에서 함께 고칠 것

1. **카탈로그 버전** — `version` 을 올리고 `updatedAt` 을 그날 날짜로
2. **`docs/system-architecture.md` API 계약 표** — `GET /open-api/v1/...` 줄 추가, 개수(현재 "12개") 갱신
3. **`sj-lab-openapi/CLAUDE.md`** — 새 제약(필수 파라미터 등)이 생겼으면 그 이유까지
4. **history 문서** — 무엇이 늘었는지, 외부에서 어떻게 부르는지

**활용 페이지(`sj-lab-openapi-web`)는 고치지 않는다.** 카탈로그를 읽어 화면을 그리므로 항목이 자동으로 늘어난다.

### 2-4. 확인

```
mvnw.cmd test            # 카탈로그 형식·중복·GET 검사
```

띄워서 실제로 불러 본다(키가 필요하다 — 활용 페이지의 "내 API 키" 값을 쓴다).

```
curl -G "http://localhost:8100/open-api/v1/<새 경로>" \
  --data-urlencode "bbox=14120000,4500000,14160000,4530000" \
  --data-urlencode "apiKey=내_키"
```

| 확인할 것 | 기대 |
|---|---|
| 정상 호출 | 200 + 원천과 같은 본문 |
| 필수 파라미터 빼고 | 400 `MISSING_PARAMETER` |
| 키 빼고 | 401 `API_KEY_REQUIRED` |
| 카탈로그에 없는 파라미터 추가 | 400 `UNKNOWN_PARAMETER` |
| `GET /open-api/catalog` | 새 항목이 보임 |
| 활용 페이지(4100) | 왼쪽 목록에 새 항목이 생기고 "실행해 보기"가 됨 |

## 3. 자주 틀리는 것

- **`upstream` 오타** — mapservice-rest 매핑 표기가 제각각이라(`busStop-info`, `governmentOffice-info`)
  추측하지 말고 컨트롤러를 열어 복사한다. 틀리면 404가 원천에서 그대로 전달된다.
- **DB를 직접 읽으려는 시도** — 공개 API는 DB에 붙지 않는다. 같은 SQL이 두 저장소에 생기면
  뷰가 바뀔 때 한쪽만 고쳐져 답이 달라진다. 항상 mapservice-rest 를 불러 중계한다.
- **원천 경로를 바꿨는데 카탈로그를 안 고침** — mapservice-rest 의 매핑을 바꾸면 카탈로그 `upstream` 도
  같은 작업에서 고친다. 안 고치면 공개 API만 조용히 404가 된다.
- **응답 본문을 가공** — 상태코드·본문·`Content-Type` 을 그대로 전달한다. 가공하면 원천과 공개 API의
  형식이 갈라진다.

## 4. 한 줄 요약

> 백엔드에 조회 API를 추가했는가? → 열 수 있는 기능인지 4가지로 판단 → 맞으면
> `api-catalog.json` 에 항목 1개 추가 + 버전·계약 표·history 갱신 → `mvnw test` 와 실제 호출로 확인.
