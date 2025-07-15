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

```mermaid
graph TD
  GitHub[GitHub - 코드 저장소]
  Jenkins[Jenkins - CI 빌드]
  NCP Container Registry[(Docker 이미지 저장)]
  ArgoCD[ArgoCD - GitOps 배포]
  K8s[Kubernetes - 클러스터 운영]
  kubernetesNGINX[웹페이지 운영]
  localNGINX[로컬 NGINX - Reverse Proxy + HTTPS - 서비스 라우팅]
  Eureka[Spring Eureka]
  Gateway[Spring Cloud Gateway]
  map[2D 지도 서비스]
  미정[3D 시뮬레이션]
  미정[LAB 실험 기능]

  GitHub --> Jenkins --> DockerHub
  GitHub --> ArgoCD --> K8s
  K8s --> Ingress --> Gateway --> Eureka
  Gateway --> map
  Gateway --> 미정
  Gateway --> 미정
  LocalNGINX --> kubernetesNGINX
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

