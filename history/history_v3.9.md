# history v3.9 — 샘플 코드를 파라미터 형태로, 주소에 키가 안 담기던 경우 안내

- **날짜**: 2026-10-01
- **영향 저장소**: `sj-lab-openapi-web`(화면), `sj-lab`(문서)
- **이전 버전**: [history_v3.8.md](history_v3.8.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| API 센터 (운영) | https://sj-lab.co.kr/openapi/ | 샘플 코드 |
| API 센터 (로컬) | http://localhost:4100/ | |

## 실행한 프롬프트

```
이제 수정된거 봤는데 요청 url에 apikey가 안담기고 샘플코드에 파라미터들을 넣어서 요청하는 예시로 변경해줘
```

## 1. 샘플 코드가 파라미터를 따로 모아 보여 줍니다

긴 주소 한 줄이던 것을 **값을 따로 적는 형태**로 바꿨습니다. 값을 고칠 때 주소 안에서 찾지 않아도 되고,
`apiKey` 가 다른 값들과 나란히 보여서 "이게 필요하다"는 게 드러납니다.

```
curl -G "https://api.sj-lab.co.kr/open-api/v1/convenience-store" \
  --data-urlencode "bbox=14120000,4500000,14160000,4530000" \
  --data-urlencode "limit=500" \
  --data-urlencode "apiKey=내_키"
```

```
const params = new URLSearchParams({
  bbox: "14120000,4500000,14160000,4530000",
  limit: "500",
  apiKey: "내_키",
});

const response = await fetch("https://api.sj-lab.co.kr/open-api/v1/convenience-store?" + params);
```

```
params = {
    "bbox": "14120000,4500000,14160000,4530000",
    "limit": "500",
    "apiKey": "내_키",
}
response = requests.get("https://api.sj-lab.co.kr/open-api/v1/convenience-store", params=params)
```

쉼표가 들어가는 `bbox` 같은 값은 각 언어가 알아서 인코딩합니다. 로컬 서버로 이 형태를 그대로 보내
동작을 확인했습니다(틀린 키 → 401 `INVALID_API_KEY`, 키 없음 → 401 `API_KEY_REQUIRED`).

## 2. 주소에 키가 안 담기던 이유

**키 값을 저장하기 시작한 것보다 먼저 만들어진 키**였습니다. 그 키는 저장된 값이 없어서
화면이 앞자리만 보여 주고, 주소·샘플 코드에도 넣을 값이 없습니다.

이제 그 상황을 숨기지 않고 알려 줍니다.

| 위치 | 안내 |
|---|---|
| 내 API 키 | "이 키는 값을 저장하기 전에 만들어졌습니다 — 새 키로 바꾸기를 누르면 값이 보이는 키로 교체됩니다" |
| 주소 아래 | "이 주소에 아직 키가 들어가 있지 않습니다 — `apiKey` 칸에 넣으면 주소와 샘플 코드에 함께 들어갑니다" |

새 키로 바꾸면 값이 보이고, 그다음부터는 주소·샘플 코드에 자동으로 들어갑니다.

## 바뀐 파일

| 파일 | 내용 |
|---|---|
| `src/components/CodeSamples.js` | 주소 한 줄 → 파라미터 모음 형태(curl `-G`, `URLSearchParams`, `params=`) |
| `src/components/ApiDetail.js` | 샘플 코드에 주소·파라미터를 따로 넘김, 키가 비었을 때의 안내 |
| `src/components/KeyPanel.js` | 저장된 값이 없는 키일 때의 안내 한 줄 |
| `sj-lab/docs/system-architecture.md` | 샘플 코드 규칙과 위 예외 상황 기록 |
