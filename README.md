# 🧪 SJ-LAB: Kubernetes 기반 DevOps & MSA 실무형 포트폴리오

> Naver Cloud VPC 환경 위에 직접 Kubernetes 인프라를 구성하고,  
> MSA 구조의 웹 서비스를 구축한 **DevOps 기반 실무형 프로젝트**입니다.  
> 2D/3D 지도 플랫폼, 실시간 예측, 시뮬레이션 등 다양한 서비스를 모듈화하여 실험 가능한 구조로 구현하였습니다.

---

## 1. 📌 프로젝트 개요

| 항목 | 내용 |
|------|------|
| **프로젝트명** | SJ-LAB (Smart Joint-LAB) |
| **개발 기간** | 2025년 05월 ~ 현재 |
| **참여 인원** | 1인 (단독 개발) |
| **역할** | Full-Stack 개발, 인프라 설계, CI/CD 구축, K8s 운영, 웹 서비스 개발 등 100% 구현 |

---

## 2. 🧩 개요

> **DevOps와 MSA 아키텍처를 실제 클라우드 인프라에 적용한 웹 플랫폼입니다.**  
> 다양한 지도 기반 서비스, 실시간 실험(LAB), 예측 모델 등을 MSA로 분리하여 구성하고,  
> GitOps 기반의 자동 배포 시스템으로 확장성과 운영 편의성을 확보하였습니다.

---

## 3. 🏗️ 시스템 아키텍처

### 3-1. 🚀 배포 흐름 (CI + GitOps)

이 프로젝트는 CI/CD 및 GitOps 기반으로 다음과 같은 배포 구조를 따릅니다:

1. **개발자**가 GitHub에 소스 코드를 Push하면,
2. GitHub의 **Webhook**이 Jenkins를 트리거합니다.
3. **Jenkins**는 소스 코드를 기반으로 Docker 이미지를 빌드하여,
4. **NCP Container Registry**에 이미지를 저장합니다.
5. 이후 Jenkins는 Kubernetes 배포 설정이 포함된 Git 저장소(`Helm values.yaml`)를 수정합니다.
6. **ArgoCD**는 해당 Git 저장소를 감시하다가 변경이 감지되면,
7. Helm을 통해 **Kubernetes 클러스터**에 자동으로 새로운 버전을 배포합니다.

```mermaid
graph TD
  Dev[개발자 GitHub Push]
  GitHub[GitHub - 앱 코드 저장소]
  Webhook[Webhook 트리거]
  Jenkins[Jenkins - CI 파이프라인]
  DockerBuild[Docker 이미지 빌드]
  Registry["NCP Container Registry - 이미지 저장"]
  ManifestRepo["K8s Manifest 저장소 - 이미지 버전명 Push"]
  ArgoCD[ArgoCD - GitOps Sync]
  K8s[Kubernetes 클러스터 - 컨테이너 배포]

  Dev --> GitHub --> Webhook --> Jenkins
  Jenkins --> DockerBuild --> Registry
  Jenkins --> ManifestRepo
  ManifestRepo --> ArgoCD --> K8s
```

### 3-2. 🌐 서비스 흐름 (사용자 요청 → 서비스 응답)

본 시스템은 **서브도메인 기반 Reverse Proxy 구조**로 구성되어 있으며,  
사용자의 HTTPS 요청은 Local NGINX를 통해 각 Kubernetes 서비스로 분기됩니다.

1. 사용자가 브라우저에서 각 서브도메인에 접속합니다.
2. **Local NGINX**는 요청된 도메인을 기준으로 Kubernetes 클러스터 내부 서비스로 Reverse Proxy 합니다.
3. 도메인에 따른 역할은 다음과 같습니다:

| 도메인 | 설명 |
|--------|------|
| `sj-lab.co.kr` | Kubernetes NGINX에서 서빙하는 웹 프론트 (정적 HTML 페이지) |
| `api.sj-lab.co.kr` | Spring Cloud Gateway → 각 마이크로서비스 API로 라우팅 |
| `eureka.sj-lab.co.kr` | Eureka Dashboard (MSA 서비스 등록 확인) |
| `jenkins.sj-lab.co.kr` | Jenkins CI 서비스 |
| `argo.sj-lab.co.kr` | Argo CD GitOps 배포 관리 UI |
| `dashboard.sj-lab.co.kr` | Kubernetes Dashboard |

4. `api.sj-lab.co.kr`으로 들어온 요청은 **Spring Cloud Gateway**가 처리하며,
5. Gateway는 **Spring Eureka**로부터 각 마이크로서비스 위치를 동적으로 조회하고,
6. 요청을 적절한 서비스로 전달합니다:

   - 🗺️ **2D 지도 서비스**
   - 🧊 **3D 시뮬레이션**
   - 🧪 **LAB 실험 기능**

```mermaid
graph TD
  subgraph LocalNGINX[Local NGINX (HTTPS + Reverse Proxy)]
    jenkins[jenkins.sj-lab.co.kr]
    argo[argo.sj-lab.co.kr]
    eureka[eureka.sj-lab.co.kr]
    dashboard[dashboard.sj-lab.co.kr]
    web[sj-lab.co.kr (웹 프론트)]
    api[api.sj-lab.co.kr]
  end

  User[사용자 브라우저 접속 (HTTPS)]
  Gateway[Spring Cloud Gateway]
  Registry[Spring Eureka]
  Service1[2D 지도 서비스]
  Service2[3D 시뮬레이션]
  Service3[LAB 실험 기능]

  User --> jenkins
  User --> argo
  User --> eureka
  User --> dashboard
  User --> web
  User --> api

  api --> Gateway --> Registry
  Gateway --> Service1
  Gateway --> Service2
  Gateway --> Service3
```
---

## 4. ⚙️ 기술 스택

| 구분             | 기술 |
|------------------|------|
| **인프라**       | NCP VPC, Ubuntu 24.04, kubeadm |
| **컨테이너**     | Docker |
| **오케스트레이션** | Kubernetes, NGINX proxy |
| **CI/CD**        | Jenkins, NCP Container Registry |
| **GitOps**       | ArgoCD |
| **MSA**          | Spring Eureka, Spring Cloud Gateway |
| **웹 서버**      | Kubernetes NGINX, Local NGINX, certbot |
| **백엔드**       | Spring Boot, Flask |
| **프론트엔드**   | HTML/CSS, JavaScript, React, OpenLayers, Three.js, Fabric.js |
| **DB/스토리지**  | PostgreSQL, JSON, GeoJSON |
| **기타**         | Helm(도입 예정), Prometheus/Grafana(예정), Socket.IO |

---

## 5. 🔄 CI/CD & GitOps 구조

- GitHub 코드 푸시 → Jenkins Webhook → Docker 이미지 빌드 → NCP Container Registry 푸시  
- Git 저장소(YAML) 변경 → ArgoCD 감지 → Kubernetes 자동 배포  
- nginx proxy 기반으로 각 서비스 라우팅

```bash
[Git Push] → [Jenkins 빌드] → [NCP Container Registry 푸시] → [ArgoCD 감지] → [K8s 자동 배포]

---

## 6. 📡 주요 서비스 구조

| 서비스 이름              | 설명 |
|--------------------------|------|
| **2D 지도 서비스**         | OpenLayers 기반 재난 시각화, CCTV, 시설물 편집, 신고 기능 등 |
| **3D 시뮬레이션**           | Three.js 기반 산불·연무 확산, 교량 붕괴 등 재난 시뮬레이션 |
| **LAB 실험실**             | LSTM 예측, 바람 벡터 시각화, 도형 편집 툴 등 실험 기능 |
| **API Gateway**           | 서브도메인·경로 기반 라우팅, CORS·필터 처리 (Spring Cloud Gateway) |
| **Service Discovery**     | Spring Eureka 기반 마이크로서비스 자동 등록·탐색 |
| **Jenkins (CI/CD)**       | GitHub Webhook → Docker 빌드·푸시 자동화 |
| **Argo CD (GitOps)**      | Git 상태 감지 → Kubernetes 자동 배포, 실시간 Sync·Rollback |
| **Kubernetes Dashboard**  | 클러스터 자원 모니터링 및 웹 UI 관리 |

---

