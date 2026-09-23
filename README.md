# 🧪 SJ-LAB: Kubernetes & MSA 기반 공간정보(GIS) 및 시설물 관리 통합 플랫폼

> **SJ-LAB**은 모바일 현장 시설물 점검부터 공간정보(GIS) 시각화, MSA 분산 백엔드, 통합 인증(SSO), Kubernetes GitOps 자동 배포까지 전 주기를 아우르는 엔드투엔드(End-to-End) 클라우드 네이티브 웹 플랫폼입니다.

---

## 🌐 1. 서비스 접속 및 실서비스 체험 안내 (Live Demo)

플랫폼의 모든 웹 서비스, API 게이트웨이 및 클라우드 DevOps 도구는 서브도메인 기반 HTTPS 환경으로 구성되어 실서비스 운영 중입니다.

| 구분 | 서비스 명칭 | 접속 URL | 주요 역할 및 확인 포인트 |
|---|---|---|---|
| **웹 서비스** | **통합 랜딩 허브 (sj-lab-hub)** | [https://sj-lab.co.kr](https://sj-lab.co.kr) | 플랫폼 전체 런치패드, 기능 카드 및 첫 진입 SSO 게이트웨이 |
| **웹 서비스** | **시설물 관리 지도 (sj-lab-mapservice)** | [https://sj-lab.co.kr/map/](https://sj-lab.co.kr/map/) | 2,500건 시설물 GIS 시각화, 내업(사무실 조치) 관리, 실시간 CCTV 재생 |
| **인증** | **중앙 인증 서버 (sj-lab-authserver)** | [https://api.sj-lab.co.kr/auth/login.html](https://api.sj-lab.co.kr/auth/login.html) | QFieldCloud 위임 로그인, sj-lab 전용 JWT 발급, 데모 계정 지원 |
| **API** | **API 게이트웨이 (연결 테스트)** | [https://api.sj-lab.co.kr/map/check](https://api.sj-lab.co.kr/map/check) | **클릭 시 API 연결 성공 메시지 반환 (`HTTP 200`)**<br>※ 기본 루트(`/`)는 라우트가 없어 404가 발생하므로 테스트 URL로 연결 검증 |
| **DevOps** | **Jenkins (CI 파이프라인)** | [https://jenkins.sj-lab.co.kr](https://jenkins.sj-lab.co.kr) | 소스코드 감지, 컨테이너 빌드 및 NCP Registry 푸시 자동화 파이프라인 |
| **DevOps** | **Kubernetes Dashboard** | [https://dashboard.sj-lab.co.kr](https://dashboard.sj-lab.co.kr) | 클러스터 노드, 파드(Pod), 서비스 등 K8s 워크로드 리소스 시각화 모니터링 |
| **DevOps** | **ArgoCD (GitOps 배포)** | [https://argo.sj-lab.co.kr](https://argo.sj-lab.co.kr) | Helm 차트 Git 저장소 기반 클러스터 선언적 자동 배포 및 동기화 UI |
| **인프라** | **Eureka 서비스 레지스트리** | [https://eureka.sj-lab.co.kr](https://eureka.sj-lab.co.kr) | Spring Cloud 마이크로서비스 인스턴스 등록 및 헬스 상태 실시간 조회 |
| **모바일** | **QFieldCloud 관리** | [https://qfield.sj-lab.co.kr](https://qfield.sj-lab.co.kr) | 현장조사 모바일 앱 프로젝트 관리, 델타 변경 이력 및 원격 동기화 서버 |

> ### 💡 [체험 방법] 1초 만에 바로 확인하기
> 1. [https://sj-lab.co.kr](https://sj-lab.co.kr) 또는 [https://sj-lab.co.kr/map/](https://sj-lab.co.kr/map/)에 접속합니다.
> 2. 로그인 화면이 나타나면 폼 하단의 **`[체험용 계정으로 로그인]` 버튼**을 클릭합니다.
> 3. 별도의 회원가입이나 계정 입력 없이 **자동으로 데모 토큰이 발급되어 즉시 대시보드 및 지도 화면으로 입장**합니다.
> 4. 백엔드 API 게이트웨이 연결 상태는 **[https://api.sj-lab.co.kr/map/check](https://api.sj-lab.co.kr/map/check)** 링크를 클릭하여 `HTTP 200` 정상 응답(`"Hi, there. This is a message from First Service on PORT ..."`)을 즉시 확인하실 수 있습니다.

---

## 🖥️ 2. 핵심 웹 서비스 상세 안내

### 2-1. `sj-lab-hub` — 플랫폼 통합 랜딩 허브
> **URL**: [https://sj-lab.co.kr](https://sj-lab.co.kr) (React 18 · Webpack 5)

플랫폼의 단일 대문(Landing Page)이자 모든 분산 서비스로 이어지는 중앙 게이트웨이입니다.
- **서비스 런치패드 인터페이스**: 2D 지도 시설물 관리, 3D 공간 시뮬레이션, 예측 모델 실험실(Lab), OpenAPI 명세 카드를 반응형 카드 뷰로 제공합니다.
- **선제적 SSO 인증 게이트 (Zero-FOUC)**: React 컴포넌트가 파싱되기 전 `<head>` 단계에서 인라인 스크립트로 토큰 유효성을 판별하여, 미인증 사용자에게 미완성 화면이 일절 노출되지 않고 즉각 로그인으로 전환됩니다.
- **동적 환경 분기 라우팅**: 클라이언트의 접속 주소를 감지하여 로컬(포트 3000 -> 4000)과 운영(서브패스 `/` -> `/map/`) 간의 이동 경로를 자동 보정합니다.

### 2-2. `sj-lab-mapservice` — 시설물 관리 지도 웹 서비스
> **URL**: [https://sj-lab.co.kr/map/](https://sj-lab.co.kr/map/) (Vanilla JS ES Modules · OpenLayers 7 SPA)

모바일 현장조사 데이터와 전국 공공 공간정보를 결합하여 웹 지도에서 통합 모니터링하고, 사무실 조치(내업)를 등록·관리하는 핵심 업무 시스템입니다.
- **공간정보 다차원 연쇄 필터링**:
  - 시·도 → 시·군·구 → 읍·면·동 3단계 행정구역 연쇄 필터 및 경계 영역(BBOX) 자동 카메라 이동.
  - 시설물 상태(전체 / 보수 필요 / 보수 불필요) 및 내업 상태(처리 대기, 미완료, 접수, 처리중, 완료, 보류) 다중 조건 필터링.
- **클러스터링 & 스파이더링(Spidering)**:
  - 축척에 따른 지점 집약 및 수량 배지 표출.
  - 고배율(Zoom 18 이상) 확대 시 동일/초근접 건물에 묶여 있는 핀들을 원형으로 자동 펼쳐(Spidering) 개별 핀 선택성을 완벽히 보장.
  - 필터 통과 피처만 클러스터 계산에 참여시켜 **화면 배지 숫자와 좌측 목록 건수가 100% 일치**.
- **시설물 상세 팝업 & 현장 멀티미디어 재생**:
  - 현장 조사자가 녹음한 **음성 메모 오디오 플레이어**, **현장 점검 사진**, **점검 동영상**을 백엔드 중계를 통해 브라우저에서 즉시 스트리밍.
- **사무실 내업(Office Work) 처리 & 보고서 출력**:
  - 보수 대상 시설물에 대한 접수·처리중·완료 상태 변경, 일정 및 비용 입력.
  - 조치 전/후 증빙 사진 업로드 (브라우저 Canvas 기반 자동 리사이징 및 압축 전송).
  - 조치 이력을 공공 서식 규격의 **PDF 조치 보고서**로 원클릭 생성 및 다운로드.
- **전국 공공 지리정보 레이어 오버레이**:
  - 전국 고속도로/국도 **실시간 CCTV 영상 스트리밍(Hls.js)**.
  - 버스정류장, 병원, 약국, 편의점, 관공서 공간 레이어 On/Off.
  - BBOX 격자 표본화(Grid Sampling)를 통해 대용량 데이터 로딩 시 렉 없는 쾌적한 렌더링 유지.

---

## 🔄 3. 엔드투엔드(End-to-End) 업무 및 데이터 흐름 프로세스

SJ-LAB은 재난·공공시설물을 **현장에서 모바일로 점검하고(Field), 사무실에서 웹으로 조치(Office)하는 전체 업무 라이프사이클**을 유기적인 데이터 파이프라인으로 연결합니다.

### 3-1. 전체 아키텍처 흐름도 (End-to-End Pipeline)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. 현장 모바일 수집 및 실시간 증분 ETL                                      │
│                                                                             │
│ [현장 점검자]                                                               │
│       │                                                                     │
│       ▼ infra-manage-app (C++/QML 모바일 현장조사 앱)                       │
│  점검 속성 입력 (시설상태, 보수필요여부, 사진 5장, 음성메모, 동영상)        │
│       │                                                                     │
│       ▼ OGC GeoPackage 패키징 업로드                                        │
│ [QFieldCloud] (qfield.sj-lab.co.kr)                                         │
│       │                                                                     │
│       ▼ 30초 주기 변경 감지 (delta_apply 타임스탬프 대조)                   │
│ [sj-qfieldsync] (Python 동기화 워커)                                        │
│  - ALTER TABLE 스키마 진화 자동 반영                                        │
│  - 영구 불변 식별자(FACIL_T{idx}_{id}) 및 삭제 아카이브 관리                │
│  - 부분 유니크 인덱스(use_yn='y') 기반 멱등 UPSERT                          │
│  - 음성 메모 STT(Speech-to-Text) 텍스트 전사                                │
│       │                                                                     │
│       ▼ 동적 통합 뷰 생성 (CREATE OR REPLACE VIEW)                          │
│ [PostgreSQL 17 / PostGIS 3.4] (qfield.facility_total_view)                  │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│ 2. 공공 지리정보 배치 파이프라인                                            │
│                                                                             │
│ [공공데이터포털 / ITS / 생활안전지도 API]                                   │
│       │ 정기 크론 수집 (CCTV, 버스정류장, 병원, 약국, 편의점, 관공서)       │
│       ▼                                                                     │
│ [sj-lab-scheduler] (Spring Boot 데이터 배치)                                │
│  - EPSG:3857 웹 메르카토르 좌표 투영                                        │
│  - 대용량 청크(500~5000건) 분할 및 DataTypeUtil 정규화                      │
│       │                                                                     │
│       ▼ CREATE OR REPLACE VIEW map.v_*_geojson                              │
│ [PostgreSQL 17 / PostGIS 3.4] (지도 서빙용 공간 뷰)                         │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│ 3. 분산 마이크로서비스 백엔드 및 통합 인증                                  │
│                                                                             │
│ [sj-lab-discoveryServer] (:8761) ── 서비스 레지스트리 (Netflix Eureka)      │
│       ▲                    ▲                     ▲                          │
│       │ 인스턴스 동적 등록 │ 인스턴스 동적 등록  │ 인스턴스 동적 등록       │
│ [mapservice-rest]    [sj-lab-authserver]   [fast-api-ai]                    │
│ (지도/시설물 API)    (통합 인증/SSO)       (AI/RAG 서비스)                  │
│  - PostGIS GeoJSON    - QFieldCloud 위임    - Eureka 연동 Python            │
│    Zero-Serialization   인증 (회원DB 無)    - 음성 STT 분석 및              │
│  - BBOX 격자 표본화   - sj-lab 전용 JWT 발급  유사 사례 추천                │
│  - 내업/사진 트랜잭션 - 세션쿠키+해시 SSO                                   │
│  - 원격 미디어 중계   - 서버 격리 데모인증                                  │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│ 4. 단일 진입점 API 게이트웨이 및 프론트엔드 포털                            │
│                                                                             │
│ [sj-lab-apigateway] (:8100 / api.sj-lab.co.kr)                             │
│  ├── /map/**         ──> lb://MAPSERVICE-REST                               │
│  ├── /auth/**        ──> lb://SJ-LAB-AUTHSERVER                             │
│  ├── /scheduler/**   ──> lb://SJ-LAB-SCHEDULER                              │
│  └── /fast-api-ai/** ──> lb://FAST-API-AI                                   │
│       ▲                                                                     │
│       │ HTTPS REST 통신 (중앙 집중식 CORS 및 DedupeResponseHeader)          │
│       │                                                                     │
│ [사용자 브라우저]                                                           │
│  ├── sj-lab.co.kr       ──> [sj-lab-hub] (React 런치패드, SSO 게이트)       │
│  └── sj-lab.co.kr/map/  ──> [sj-lab-mapservice] (OpenLayers GIS SPA)        │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│ 5. CI/CD 및 GitOps 클라우드 배포 인프라                                     │
│                                                                             │
│ 개발자 Push ──> [Jenkins CI] ──> NCP Container Registry (Docker Image Push) │
│                      │                                                      │
│                      ▼ values.yaml 의 image.tag 자동 수정 및 커밋           │
│                 [sj-lab-k8s-manifests] (GitOps Helm 저장소)                 │
│                      │                                                      │
│                      ▼ Auto-Sync 감지 (Self-Heal, Prune)                    │
│                 [ArgoCD] ──> [Kubernetes Cluster] (무중단 롤링 업데이트)    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3-2. 5단계 상세 업무 시나리오

1. **1단계: 현장 모바일 점검 (`infra-manage-app`)**
   - 조사자가 현장에서 모바일 앱을 실행하여 GNSS 좌표 기반으로 시설물을 터치합니다.
   - 시설명, 관리상태, 보수필요여부('Y'/'N')를 입력하고 현장 사진 최대 5장, 음성 메모, 동영상을 첨부하여 로컬 GeoPackage에 저장합니다.
   - 통신 연결 시 QFieldCloud로 자동 업로드됩니다.
2. **2단계: 30초 주기 실시간 동기화 (`sj-qfieldsync`)**
   - 백그라운드 워커가 QFieldCloud 메타 DB의 `delta_apply` 이력을 30초마다 확인하여 변경된 프로젝트만 선별 다운로드합니다.
   - 신규 속성이 발견되면 `ALTER TABLE ADD COLUMN`으로 물리 테이블을 즉시 확장하고, `use_yn='y'` 부분 유니크 인덱스를 통해 멱등하게 적재합니다.
   - 음성 메모는 STT 엔진을 거쳐 텍스트로 자동 전사되며, 전체 테이블의 컬럼 합집합으로 `qfield.facility_total_view`가 자동 갱신됩니다.
3. **3단계: 공간 데이터 가공 및 공공데이터 결합 (`mapservice-rest`, `sj-lab-scheduler`)**
   - 스케줄러가 수집한 CCTV, 버스정류장, 병원 등의 공공데이터와 현장 시설물 데이터를 PostGIS 공간 데이터베이스로 통합합니다.
   - 백엔드는 클라이언트의 DTO 변환 병목을 없애기 위해 PostGIS SQL 내부에서 `json_build_object`와 `ST_AsGeoJSON`을 통해 완성된 GeoJSON 텍스트를 직접 스트리밍합니다.
4. **4단계: 단일 게이트웨이 경유 및 웹 지도 표출 (`sj-lab-mapservice`, `sj-lab-apigateway`)**
   - 사용자가 웹 브라우저로 접속하면 게이트웨이를 경유하여 뷰포트 영역(BBOX) 기반 시설물 데이터를 호출합니다.
   - 수십만 건의 대용량 레이어는 가상 격자 표본화(Grid Sampling)로 화면에 균등 분산 반환되고, 프론트엔드는 OpenLayers 클러스터링과 Zoom 18 Spidering을 통해 겹치는 핀들을 쾌적하게 렌더링합니다.
5. **5단계: 사무실 조치(내업) 등록 및 증빙 피드백**
   - 보수가 필요한 시설물을 클릭하여 현장 사진 및 음성/동영상을 재생 검토합니다.
   - 내업 관리 탭에서 처리 상태(접수 → 처리중 → 완료)와 조치 내용을 입력하고, 브라우저에서 자동 압축된 조치 전/후 증빙 사진을 업로드합니다.
   - 최종 조치 내역은 규격화된 PDF 조치 보고서로 출력되어 인쇄 및 전자 문서로 보관됩니다.

---

## 📦 4. 11개 서브 프로젝트 구성 및 역할 총괄 표

| 분류 | 저장소 | 주요 기술 | 핵심 역할 및 책임 | 서비스 경로 / 노출 포트 |
|---|---|---|---|---|
| **백엔드 (총괄)** | [mapservice-rest](https://github.com/stylealist/mapservice-rest) | Java 17, Spring Boot 3.3.2, PostGIS, MyBatis | 공간정보 GeoJSON API, BBOX 격자 표본화, 내업 기록/사진 관리, 총괄 아키텍처 기준 저장소 | `api.sj-lab.co.kr/map/**`<br>(로컬 랜덤) |
| **게이트웨이** | [sj-lab-apigateway](https://github.com/stylealist/sj-lab-apigateway) | Spring Cloud Gateway, WebFlux, Netty | 마이크로서비스 단일 진입점, Eureka 기반 클라이언트 로드밸런싱, 중앙 집중식 CORS 제어 | `api.sj-lab.co.kr`<br>(로컬 8100) |
| **디스커버리** | [sj-lab-discoveryServer](https://github.com/stylealist/sj-lab-discoveryServer) | Spring Cloud Netflix Eureka Server | 서비스 동적 등록/위치 추적, 헬스체크 및 라이프사이클 관리 | `eureka.sj-lab.co.kr`<br>(로컬 8761) |
| **데이터 배치** | [sj-lab-scheduler](https://github.com/stylealist/sj-lab-scheduler) | Spring Boot, PostGIS, `@Scheduled` | 공공 API(CCTV, 버스, 병원, 약국 등) 정기 수집, 공간 투영(3857) 및 GeoJSON 뷰 생성 | `api.sj-lab.co.kr/scheduler/**`<br>(로컬 랜덤) |
| **인증 서버** | [sj-lab-authserver](https://github.com/stylealist/sj-lab-authserver) | Spring Security 6, JJWT (HS256) | QFieldCloud 계정 위임 인증, sj-lab 전용 JWT 발급, 세션 쿠키/해시 기반 무DB SSO | `api.sj-lab.co.kr/auth/**`<br>(로컬 랜덤) |
| **AI 마이크로서비스**| [fast-api-ai](https://github.com/stylealist/fast-api-ai) | Python 3.12, FastAPI, Uvicorn | Spring Cloud 연동 Python 마이크로서비스, 음성 STT 요약 및 AI/RAG 엔진 기반 | `api.sj-lab.co.kr/fast-api-ai/**`<br>(로컬 8000) |
| **지도 프론트** | [sj-lab-mapservice](https://github.com/stylealist/sj-lab-mapservice) | Vanilla JS (ES Modules), OpenLayers 7, Hls.js | 무빌드 정적 SPA, 약 2,500건 시설물 공간 시각화, 클러스터링/스파이더링, 내업 관리 UI | `sj-lab.co.kr/map/`<br>(로컬 4000) |
| **랜딩 허브** | [sj-lab-hub](https://github.com/stylealist/sj-lab-hub) | React 18, Webpack 5, Babel | 플랫폼 단일 대문(Landing), 서비스 런치패드, React 구동 전 SSO 인증 게이트웨이 | `sj-lab.co.kr`<br>(로컬 3000) |
| **모바일 앱** | [infra-manage-app](https://github.com/stylealist/infra-manage-app) | C++17, Qt/QML, QGIS Core SDK, CMake | QField 기반 커스텀 포크 현장조사 앱, 3단계 점검 폼 및 사진/음성/영상 미디어 수집 | 모바일 (Android/Windows) |
| **동기화 워커** | [sj-qfieldsync](https://github.com/stylealist/sj-qfieldsync) | Python, GeoPandas, GDAL, psycopg2 | QFieldCloud ↔ PostGIS 30초 주기 증분 ETL, 스키마 진화 수용, 영구 불변 ID 보장 | 단독 백그라운드 워커 |
| **GitOps 배포** | [sj-lab-k8s-manifests](https://github.com/stylealist/sj-lab-k8s-manifests) | Kubernetes, Helm 3, ArgoCD | 전 서비스 Helm 차트 모음, GitOps 배포 SSOT, ConfigMap 체크섬 롤링 업데이트 | 클러스터 인프라 |

---

## ⚙️ 5. 핵심 엔지니어링 구현 및 아키텍처 원칙

### 5.1 공간정보(GIS) 성능 최적화 파이프라인
- **Zero-Serialization GeoJSON 조립**: 애플리케이션의 DTO 매핑 및 JSON 직렬화 오버헤드를 제거하기 위해 PostGIS SQL 레벨에서 `json_build_object`와 `ST_AsGeoJSON`을 사용하여 완성된 GeoJSON 문자열을 직접 반환합니다.
- **BBOX 격자 표본화(Spatial Grid Sampling)**: 수십만 건의 대용량 공간 레이어를 무분별하게 전송하지 않고, 뷰포트 영역을 가상 격자로 분할하여 `row_number() OVER (PARTITION BY grid_x, grid_y)`를 통해 화면에 균등 분산된 표본을 고속 서빙합니다.
- **프론트엔드 스파이더링(Spidering) & Declutter**: OpenLayers 렌더러의 Declutter 메커니즘을 분석하여 시설물 핀을 `declutterMode: "obstacle"`로 최우선 렌더링하고, 고배율(Zoom 18 이상)에서 겹치는 동일 좌표 객체를 원형으로 펼쳐 개별 선택성을 보장합니다.

### 5.2 무(無)데이터베이스 위임 SSO 아키텍처
- 별도의 회원 DB를 구축하여 계정 파편화를 일으키지 않고, 현장조사 플랫폼인 QFieldCloud의 인증 API를 위임 검증하여 내부 서비스 전용 JWT를 발급합니다.
- **분리형 세션-토큰 모델**: 인증 서버 오리진의 `HttpOnly; SameSite=Lax` 세션 쿠키와 각 정적 SPA의 `localStorage` 액세스 토큰을 URL Fragment(`#auth_token=...`)로 연계하여, 서드파티 쿠키 차단 문제 없이 단일 로그인 경험을 제공합니다.

### 5.3 복원력과 스키마 진화(Schema Evolution)
- **ETL 스키마 자동 보강**: 현장 점검 양식이 수시로 변경되는 환경에 대응하여, 새 필드 유입 시 `ALTER TABLE ADD COLUMN`을 통해 PostGIS 물리 테이블을 무중단으로 확장하고 전체 테이블 컬럼 합집합 기반의 `facility_total_view`를 동적으로 재생성합니다.
- **영구 불변 식별자(Immutable ID)**: QFieldCloud 프로젝트 삭제 시 물리 행을 아카이브 테이블(`facility_deleted_archive`)로 이동하여 원본 고유 ID를 보존함으로써, 상위 웹 서비스의 내업 조치 기록이 영구히 단절되지 않도록 무결성을 유지합니다.
- **Graceful Degradation**: 신규 기능 테이블(내업 테이블 등)이 DB에 즉시 반영되지 않은 과도기 배포 환경에서도 `to_regclass` 시스템 카탈로그 조회를 통해 기본 지도 표출이 중단되지 않도록 단계적 폴백(Fallback)을 적용했습니다.

### 5.4 GitOps 기반 배포 자동화
- 개발자가 서비스 저장소에 코드를 푸시하면 Jenkins가 Docker 이미지를 빌드하여 NCP Container Registry에 푸시하고, 매니페스트 저장소(`sj-lab-k8s-manifests`)의 `values.yaml` 내 `image.tag`를 자동 갱신합니다.
- ArgoCD가 매니페스트 저장소의 변경을 감지하여 실시간 Auto-Sync 및 Self-Heal을 수행하며 클러스터 무중단 롤아웃을 완성합니다.

---

## 💻 6. 로컬 통합 개발 환경 구동

총괄 저장소(`mapservice-rest`)의 파워셸 스크립트를 통해 전체 마이크로서비스 스택을 원클릭으로 기동하고 관리할 수 있습니다:

```powershell
# Eureka → mapservice-rest → sj-lab-authserver → apigateway → 프론트 순차 기동
powershell -ExecutionPolicy Bypass -File scripts\local-stack.ps1 start

# 무빌드 빠른 재기동
powershell -ExecutionPolicy Bypass -File scripts\local-stack.ps1 start -NoBuild

# 프로세스 상태 확인
powershell -ExecutionPolicy Bypass -File scripts\local-stack.ps1 status

# 로컬 스택 정상 종료
powershell -ExecutionPolicy Bypass -File scripts\local-stack.ps1 stop
```
