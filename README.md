#NCP VPC 기반 Kubernetes 인프라 구축 포트폴리오( SJ-LAB )

이 프로젝트는 Naver Cloud Platform의 VPC 환경에 직접 구성한 Kubernetes 기반 DevOps 시스템입니다.  
CI/CD, GitOps, 서비스 디스커버리, API 게이트웨이 등을 통합하여 실무에서 활용 가능한 인프라를 설계하였습니다.

## 🔧 주요 기술 스택
- Kubernetes (kubeadm)
- Jenkins (CI/CD)
- ArgoCD (GitOps)
- Spring Eureka / API Gateway
- Ingress-NGINX + Local NGINX + certbot
- NCP VPC + IaaS

## 🧱 시스템 구조
- Reverse Proxy: Local NGINX
- Git Push → Jenkins Webhook → Docker Build/Push
- ArgoCD → GitOps 방식 자동 배포
- 각 서비스는 Ingress + Subdomain으로 구성

## 📁 디렉토리 설명
- `kuber-yaml/`: Kubernetes 배포 리소스
- `jenkins/`: Jenkinsfile 및 빌드 설정
- `argoCD/`: ArgoCD 애플리케이션 정의
- `nginx/`: 리버스 프록시 설정 파일
