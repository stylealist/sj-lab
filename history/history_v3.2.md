# history v3.2 — API 센터 색을 보라에서 파랑 계열로 통일

- **날짜**: 2026-09-30
- **영향 저장소**: `sj-lab-hub`(OpenAPI 카드), `sj-lab-openapi-web`(API 센터 화면 전체)
- **이전 버전**: [history_v3.1.md](history_v3.1.md)

## 접속 URL

| 대상 | URL | 비고 |
|---|---|---|
| 공유 웹사이트(발행, 링크 공유 가능) | https://claude.ai/artifact/HhEYu2UmxSko5h8uef7hB9 | 작업 로그 |
| 허브 첫 화면 | https://sj-lab.co.kr | OpenAPI 카드 |
| API 센터 | https://sj-lab.co.kr/openapi/ | 색이 바뀐 화면 |
| 지도 서비스 | https://sj-lab.co.kr/map/ | 색을 맞춘 기준 |

## 실행한 프롬프트

```
sj-lab-hub하고 sj-lab-openapi-web 페이지를 수정하려고 하는데
api 센터 색을 sj-lab-hub와 sj-lab-mapservice과 비슷한 계열의 색상으로 변경해줘
```

## 무엇이 문제였나

허브 첫 화면과 지도 서비스는 **파랑·남색** 계열입니다. 그런데 API 센터만 **보라색**이라
같은 플랫폼인데 다른 서비스처럼 보였습니다.

## 어떻게 바꿨나

API 센터를 **딥 네이비 블루**(짙은 남색이 섞인 파랑)로 바꿨습니다.
지도 서비스의 대표 파랑을 그대로 가져오면서, 허브에 이미 있는 "시설물 관리" 카드(밝은 파랑)와는
명도를 달리해 **네 카드가 여전히 한눈에 구분**되게 했습니다.

| 쓰인 곳 | 전 (보라) | 후 (딥 네이비 블루) |
|---|---|---|
| 허브 OpenAPI 카드 · API 센터 헤더 · 버튼 | 보라 그라데이션 | 파랑 → 짙은 남색 그라데이션 |
| 선택한 API 테두리 · 강조 글자 | 보라 | 파랑 |
| 배지(GET 표시) · 연한 배경 | 연보라 | 연파랑 |
| 탭 아이콘(favicon) 2곳 | 보라 | 파랑 계열 |
| 안내 문구 상자 | 남보라 | 회색 계열(파랑 배지와 겹치지 않게) |

## 바뀐 파일

| 저장소 | 파일 | 내용 |
|---|---|---|
| `sj-lab-hub` | `src/App.js` | OpenAPI 카드 색 1줄 |
| | `public/favicon.svg` | 탭 아이콘 4칸 중 OpenAPI 칸 색 |
| | `CLAUDE.md` | 아이콘 설명의 색 이름 |
| `sj-lab-openapi-web` | `src/App.js` | 헤더 · 목록 선택 · 배지 · 안내 상자 |
| | `src/components/ApiDetail.js` | 실행 버튼 · 배지 · 키 안내 |
| | `src/components/CodeSamples.js` | 샘플 코드 탭 |
| | `src/components/KeyPanel.js` | 키 발급 버튼 · 발급 결과 상자 |
| | `public/favicon.svg` | 탭 아이콘 그라데이션 |
| | `CLAUDE.md` | 아이콘 설명의 색 이름 |

색만 바꿨고 기능·문구·화면 배치는 그대로입니다.

## 어떻게 확인했나

- 두 저장소에 **보라 계열 색 코드가 한 건도 남지 않은 것** 확인
- 허브의 나머지 세 카드 색(파랑·초록·주황)이 그대로인 것 확인
- 두 저장소 모두 **빌드 성공**(오류 없음)

## 작업 방식

프론트엔드 작업이라 두 저장소를 **동시에 두 대의 AI(antigravity)** 에게 나눠 맡기고,
결과는 Claude가 직접 다시 확인했습니다. 커밋·배포는 하지 않았습니다.
