# history v4.12 — "왜 준비되지 않았는지"를 서버가 말하게 (운영 원인 확정)

- **날짜**: 2026-10-13
- **영향 저장소**: `sj-lab-estate`, `sj-lab-estate-web`, `sj-lab`
- **이전 버전**: [history_v4.11.md](history_v4.11.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| 부동산 실거래 (운영) | https://sj-lab.co.kr/estate/ | 화면·서버 배포됨, 데이터는 Secret 적용 후 |
| 부동산 조회 API (운영) | https://api.sj-lab.co.kr/estate/status | `reason: NOT_CONFIGURED` |

## 실행한 프롬프트

```
부동산 조회 서버가 아직 준비되지 않았습니다. — ... 나오고 데이터가 안나와
커밋 푸시하고 나오도록 해줘
```

## 1. 로컬은 되고 운영만 안 됩니다

먼저 양쪽을 확인했습니다.

| 곳 | 결과 |
|---|---|
| 로컬(4200 → 8120) | `ready:true` — 데이터 나옴 |
| 운영(sj-lab.co.kr/estate/) | `ready:false` — **DB 접속 정보(Secret)가 아직 없음** |

즉 코드 문제가 아니라 **운영 클러스터에 접속 정보를 넣는 단계가 남은 것**입니다.
그 작업은 클러스터에 접근할 수 있는 자리에서만 할 수 있습니다(이 작업 환경에는 권한이 없습니다).

## 2. 그래서 "왜 안 되는지"를 서버가 말하게 했습니다

종전에는 화면에 "준비되지 않았습니다"만 떠서, **접속 정보가 없는 것인지 / 있는데 DB 에 못 붙는
것인지** 구분할 수 없었습니다. 상태 응답에 원인을 함께 담았습니다.

| 값 | 뜻 |
|---|---|
| `NOT_CONFIGURED` | 접속 정보가 아예 없음(지금 운영 상태) |
| `CONNECT_FAILED` | 정보는 있는데 DB 에 못 붙음(주소·계정·권한 확인) |
| `READY` | 정상 |

- **"된다"의 판정도 바꿨습니다** — 종전에는 "설정이 꽂혀 있나"만 봤는데, 이제 **가벼운 조회가 실제로
  되는지** 확인합니다. 설정만 있고 DB 에 못 붙는 상태를 정상으로 보고하던 빈틈을 막았습니다.
- **접속 주소·계정·비밀번호는 응답에 담지 않습니다.** 설정 여부(true/false)와 실패한 오류의 종류
  이름까지만 알려 주고, 자세한 내용은 서버 로그에 남깁니다.
- 화면 배너는 서버가 준 설명을 그대로 보여 줍니다 — 보는 사람이 무엇을 기다리면 되는지 알 수 있게.

## 3. 배포까지 자동으로 돌았습니다

푸시하자 **Jenkins 가 자동으로 두 잡을 실행**했고(푸시 트리거) 둘 다 성공했습니다.

```
PROD-SJ-LAB-ESTATE      #3  SUCCESS
PROD-SJ-LAB-ESTATE-WEB  #7  SUCCESS
```

그리고 운영 응답이 바뀐 것을 확인했습니다 — 이제 원인이 한눈에 보입니다.

```
{"ready":false, "reason":"NOT_CONFIGURED", "configured":false,
 "detail":"DB 접속 정보가 없습니다(ESTATE_DB_URL). 운영은 k8s Secret estate-db-credentials ..."}
```

## 4. 데이터가 나오게 하려면 (남은 한 단계)

클러스터에 접근할 수 있는 자리에서 **한 줄**입니다. 비밀번호가 화면·기록에 남지 않습니다.

```
powershell -ExecutionPolicy Bypass -File scripts\create-estate-db-secret.ps1
```

Secret 등록 → 파드 재시작 → 상태 확인까지 한 번에 하고, 끝나면 `ready:true` 가 되며 화면에
데이터가 채워집니다. 계정은 `mcp_readonly`(v4.11 결정).

## 5. 바뀐 파일

| 저장소 | 파일 | 내용 |
|---|---|---|
| `sj-lab-estate` | `service/EstateService.java` | `readiness()` 추가 — 설정 여부 + 실제 조회 확인, 원인 분류 |
| | `controller/EstateController.java` | `status` 응답에 `reason`·`configured`·`detail` |
| `sj-lab-estate-web` | `src/App.js` | 배너가 서버의 설명을 그대로 표시 |
| `sj-lab` | `history/history_v4.12.md` + 공유 페이지 2곳 | 이 기록 |

## 남은 이야기

- Secret 적용(위 한 줄) → 데이터 표시
- 전용 계정(`estate_read`)으로 좁히기 — 여유 있을 때
- 전월세 보증금 재수집(v4.4 버그) — 시점 결정 필요
