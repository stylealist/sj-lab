// sj-lab-estate (부동산 실거래 조회 API) 배포 파이프라인 — Jenkins 잡의 [Pipeline script] 에 붙여 넣는 내용
// sj-lab-openapi 잡과 같은 구조다(도구·스테이지 구성·자격 증명 동일).
//
// ── 흐름 ────────────────────────────────────────────────────────────────────
//     jar 빌드 → 이미지 빌드·push(NCP 레지스트리)
//   → sj-lab-k8s-manifests 의 sj-lab-estate/values.yaml 에서 image.tag 를 빌드번호로 커밋
//   → ArgoCD 가 동기화(selfHeal·prune) → 롤아웃
//
// ── 자격 증명 (docs/k8s-secrets.md, 값은 Jenkins 에만 있다) ──────────────────
//     github_login : 저장소 checkout
//     ncp-api-key  : NCP 레지스트리 docker login (Access Key / Secret Key)
//     GitHub_token : 매니페스트 저장소에 image.tag 커밋·push
//
// ── 주의할 점 ───────────────────────────────────────────────────────────────
// 1) Dockerfile 이 **미리 빌드된 jar 를 복사**하므로 Build 단계가 먼저 끝나야 한다.
// 2) 여러 서비스 잡이 동시에 매니페스트를 push 하면 한 잡이 `cannot lock ref` 로 실패할 수 있다.
//    이미지는 이미 올라가 있으므로 그 잡만 재실행하면 된다(2026-09-16 실제 발생).
// 3) image.tag 는 이 잡이 관리하는 값이다. 사람이 임의로 낮추거나 되돌리지 말 것.
// 4) **Verify 는 /estate/status 로 한다.** 이 서비스는 DB 접속 정보가 없어도 뜨고 그때는
//    조회만 503 이므로, 데이터 조회로 확인하면 "배포는 됐는데 Secret 이 없는 상태"와
//    "배포 실패"를 구분할 수 없다. status 는 두 경우 모두 200 이고 ready 로 구분된다.

pipeline {
    agent any

    environment {
        IMAGE_TAG  = "${env.BUILD_NUMBER}"
        IMAGE_NAME = "sj-lab-estate"
        REGISTRY   = "sj-lab-registry.kr.ncr.ntruss.com"
        CHART_DIR  = "sj-lab-estate"          // sj-lab-k8s-manifests 안의 차트 디렉터리
    }

    tools {
        maven 'MAVEN_3.9.6'
    }

    triggers {
        githubPush() // GitHub Push 이벤트 트리거 설정
    }

    stages {
        stage('Workspace Cleanup') {
            steps {
                deleteDir() // Jenkins workspace 전체 삭제
            }
        }

        stage('Checkout') {
            steps {
                git branch: 'main',
                    credentialsId: 'github_login',
                    url: 'https://github.com/stylealist/sj-lab-estate.git'
            }
        }

        stage('Build') {
            steps {
                // Maven 빌드를 통해 Spring Boot jar 파일 생성 (Dockerfile 이 이 jar 를 복사한다)
                sh 'mvn clean package -DskipTests'
                sh 'test -f target/sj-lab-estate.jar'
            }
        }

        stage('Docker Build') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'ncp-api-key', usernameVariable: 'NCP_ACCESS_KEY', passwordVariable: 'NCP_SECRET_KEY')]) {
                    sh '''
                        echo "$NCP_SECRET_KEY" | docker login ${REGISTRY} -u "$NCP_ACCESS_KEY" --password-stdin
                        docker build -t ${IMAGE_NAME}:${IMAGE_TAG} -t ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} .
                        docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                    '''
                }
            }
        }

        stage('Update Kubernetes Manifest') {
            steps {
                withCredentials([string(credentialsId: 'GitHub_token', variable: 'GIT_TOKEN')]) {
                    sh '''
                        rm -rf sj-lab-k8s-manifests
                        git config --global user.email "stylealist@gmail.com"
                        git config --global user.name "stylealist"

                        git clone https://stylealist:${GIT_TOKEN}@github.com/stylealist/sj-lab-k8s-manifests.git
                        cd sj-lab-k8s-manifests

                        # image.tag 만 바꾼다. 따옴표가 있든(tag: "1") 없든(tag: 1) 같은 결과가 되게 한다.
                        sed -i "s|^\\( *tag: *\\).*|\\1${IMAGE_TAG}|" ${CHART_DIR}/values.yaml
                        grep -n "tag:" ${CHART_DIR}/values.yaml

                        git add ${CHART_DIR}/values.yaml
                        # 바뀐 게 없으면 커밋을 건너뛴다(빈 커밋으로 잡이 실패하지 않게)
                        if git diff --cached --quiet; then
                            echo "변경 없음 - 커밋 생략"
                        else
                            git commit -m "Update ${IMAGE_NAME} image tag to ${IMAGE_TAG} from Jenkins"
                            git push origin main
                        fi
                    '''
                }
            }
        }

        stage('Verify') {
            steps {
                // 짧게 자주 확인하고 되는 즉시 빠져나간다(최대 5분). 옛 파드가 내려가는 사이에는
                // 게이트웨이가 503 을 낼 수 있다.
                //
                // status 가 200 이면 "서비스는 떴다"까지 확인된 것이고, 그 응답의 ready 로
                // DB 접속 준비 여부를 함께 본다(false 면 Secret·표가 아직 없다는 뜻 — 배포 실패가 아니다).
                sh '''
                    set -eu
                    DEADLINE=$(( $(date +%s) + 300 ))
                    ATTEMPT=0
                    until curl -fsS --max-time 10 https://api.sj-lab.co.kr/estate/status -o status.json; do
                        ATTEMPT=$((ATTEMPT + 1))
                        if [ "$(date +%s)" -ge "$DEADLINE" ]; then
                            echo "❌ 배포 확인 실패(5분 초과): /estate/status 가 응답하지 않는다"
                            exit 1
                        fi
                        echo "대기 중... (${ATTEMPT}회)"
                        sleep 10
                    done
                    cat status.json
                    if grep -q '"ready":[ ]*true' status.json; then
                        echo "✅ 부동산 조회 서비스 배포 완료 (DB 접속 준비됨)"
                    else
                        echo "⚠️ 서비스는 떴지만 DB 접속이 준비되지 않았다(ready:false)."
                        echo "   estate-db-credentials Secret 과 estate 스키마 표를 확인할 것 — 조회만 503 이고 나머지는 정상이다."
                    fi
                '''
            }
        }
    }

    post {
        success {
            echo '✅ 부동산 실거래 조회 서비스가 배포되었습니다!'
        }
        failure {
            echo '❌ 빌드 또는 배포 실패! (매니페스트 push 충돌 cannot lock ref 이면 이 잡만 재실행)'
        }
    }
}

// ── 처음 배포할 때 ───────────────────────────────────────────────────────────
// 1) ArgoCD 에 sj-lab-estate Application 을 등록해야 한다(차트 경로 sj-lab-estate/).
//    등록 전에는 image.tag 만 올라가고 클러스터에는 아무 일도 일어나지 않는다.
// 2) 게이트웨이에 /estate 라우트가 배포돼 있어야 Verify 가 통과한다
//    (sj-lab-apigateway 잡을 먼저 한 번 돌릴 것).
// 3) 데이터까지 보이게 하려면 두 가지가 더 필요하다 — 둘 다 없어도 배포는 성공한다.
//    · estate 스키마 표: sj-lab 저장소 db/estate/estate_apt.sql (DB 담당자 실행)
//    · Secret: kubectl create secret generic estate-db-credentials -n sj-lab \
//        --from-literal=url='jdbc:postgresql://<호스트>:5432/sjlab' \
//        --from-literal=username='<조회 전용 계정>' --from-literal=password='<비밀번호>'
