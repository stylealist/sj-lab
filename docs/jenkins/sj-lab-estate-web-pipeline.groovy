// sj-lab-estate-web (부동산 실거래 화면) 배포 파이프라인 — Jenkins 잡의 [Pipeline script] 에 붙여 넣는 내용
// sj-lab-openapi-web 잡과 같은 구조다(도구·빌드 명령·스테이징 바꿔치기 방식 동일).
//
// ── 무엇을 배포하나 ─────────────────────────────────────────────────────────
// 부동산 실거래 화면(React + Webpack)은 이미지·ArgoCD 를 거치지 않고,
// 웹서버 노드의 정적 디렉터리에 파일을 그대로 복사한다.
//
//     /home/kuber-volume/sj-lab-webserver/html/          ← 허브(sj-lab-hub)
//     /home/kuber-volume/sj-lab-webserver/html/map/      ← 지도(sj-lab-mapservice)
//     /home/kuber-volume/sj-lab-webserver/html/openapi/  ← API 활용 페이지
//     /home/kuber-volume/sj-lab-webserver/html/estate/   ← 이 잡(sj-lab-estate-web)
//
// ── 주의할 점 ───────────────────────────────────────────────────────────────
// 1) STAGING_DIR 는 다른 잡(지도 /respal/deploy, 허브 /respal/deploy-hub,
//    활용 페이지 /respal/deploy-openapi)과 **달라야** 한다. 같으면 동시에 돌 때 서로 덮어쓴다.
// 2) cleanRemote 는 **스테이징에만** 켠다. 최종 위치(html)에 켜면 옆 사이트가 통째로 지워진다
//    (허브 잡에서 실제로 겪은 사고 — docs/deploy-static-sites.md 참고).
// 3) 이 잡은 자기 폴더(html/estate)만 바꾸므로 허브·지도·활용 페이지에는 영향이 없다.
//
// 전제: SSH 서버(sj-lab-master)의 Jenkins 전역 "Remote Directory" 가 '/' 이다.
// 도구 이름: Jenkins 에 등록된 NodeJS 도구는 'node-18' 이다('node18' 로 적으면 잡이 시작도 못 한다).
// **잡에 넣을 때는 이 .groovy 파일을 그대로 붙여 넣을 것.** config.xml 안의 script 를
//       복사해 붙이면 &gt; 같은 escape 가 그대로 들어가 원격 bash 가 죽는다(아래 execCommand 주석 참고).

pipeline {
  agent any

  environment {
    BUILD_DIR   = "build"
    STAGING_DIR = "/respal/deploy-estate"                             // 이 잡 전용 스테이징 (신규)
    WEB_DIR     = "/home/kuber-volume/sj-lab-webserver/html/estate"   // 최종 위치
    SSH_SERVER  = "sj-lab-master"
  }

  tools {
    nodejs 'node-18'
  }

  stages {
    stage('Clone Repository') {
      steps {
        git branch: 'main', url: 'https://github.com/stylealist/sj-lab-estate-web.git'
      }
    }

    stage('Install Dependencies') {
      steps {
        sh 'npm install'
      }
    }

    stage('Build React App') {
      steps {
        sh 'npm run build'
        // 빈 산출물로 사이트를 덮어쓰는 사고 방지
        sh 'test -f build/index.html'
      }
    }

    stage('Deploy to Kubernetes Node') {
      steps {
        script {
          sshPublisher(
            publishers: [
              sshPublisherDesc(
                configName: "${env.SSH_SERVER}",
                transfers: [
                  sshTransfer(
                    sourceFiles: "${env.BUILD_DIR}/**",
                    removePrefix: "${env.BUILD_DIR}",
                    remoteDirectory: "${env.STAGING_DIR}",   // ← 최종 위치가 아니라 스테이징으로
                    cleanRemote: true,                        // ← 스테이징만 비운다 (여기는 비워도 안전)
                    flatten: false,

                    // ── 이 안에서는 꺾쇠(> <)·앰퍼샌드(&)·$$ 를 쓰지 않는다 ─────────────────
                    // 1) 잡을 XML(config.xml) 로 주고받으면 이 문자들은 &gt; &amp; 로 바뀐다.
                    //    API 로 POST 하면 Jenkins 가 되돌려 주지만, **XML 안의 내용을 사람이 복사해
                    //    UI 에 붙여 넣으면 &gt; 가 그대로 들어가** 원격 bash 가
                    //    `syntax error near unexpected token ';&'` 로 죽는다(2026-10-12 실제 발생).
                    // 2) Publish over SSH 는 execCommand 에 변수 치환을 하므로 **$$ 가 $ 로 줄어든다**
                    //    (같은 로그에서 ${DST}.new.$ 로 찍혔다). 임시 이름에 $$ 를 쓰지 말 것.
                    // 그래서 리다이렉션(>/dev/null, 2>&1)과 &&·|| 대신 if 문으로만 쓴다.
                    execCommand: '''
                        set -eu
                        SRC=/respal/deploy-estate
                        DST=/home/kuber-volume/sj-lab-webserver/html/estate

                        if [ ! -f "$SRC/index.html" ]; then
                            echo "index.html 없음 - 배포 중단"
                            exit 1
                        fi
                        mkdir -p "$DST"

                        if command -v rsync; then
                            # 이 잡의 폴더만 정리한다(상위 html 은 건드리지 않는다)
                            rsync -a --delete "$SRC"/ "$DST"/
                        else
                            # rsync 가 없으면: 새 폴더에 펼친 뒤 바꿔치기(복사 중 빈 화면 방지)
                            NEW="$DST.new"
                            OLD="$DST.old"
                            rm -rf "$NEW" "$OLD"
                            mkdir -p "$NEW"
                            tar -C "$SRC" -cf - . | tar -C "$NEW" -xf -
                            if [ -d "$DST" ]; then
                                mv "$DST" "$OLD"
                            fi
                            mv "$NEW" "$DST"
                            rm -rf "$OLD"
                        fi

                        echo "부동산 실거래 화면 배포 완료: $DST"
                        ls -al "$DST"
                    '''
                  )
                ],
                verbose: true
              )
            ]
          )
        }
      }
    }

    stage('Verify') {
      steps {
        // 파일이 없으면 nginx 의 location /estate/ 가 404 를 돌려준다(허브 폴백 방지).
        // 그 설정이 아직 반영되지 않아 허브 화면이 200 으로 오더라도 본문 표식으로 걸러낸다.
        sh '''
            set -eu
            # 표식은 index.html 의 <title> 이다. 헤더 로고 문구("SJ 부동산 실거래")는
            # bundle.js 안에 있어 index.html 에는 없다 — 그걸로 찾다가 첫 배포가 실패했다(2026-10-12).
            curl -fsS https://sj-lab.co.kr/estate/ | grep -q 'SJ-LAB 부동산 실거래' \
                || { echo "❌ /estate/ 가 부동산 화면이 아니다 - html/estate 와 nginx location 확인 필요"; exit 1; }
            curl -fsS https://sj-lab.co.kr/ | grep -q 'bundle' \
                || { echo "❌ 허브 확인 실패"; exit 1; }
            echo "✅ 부동산 화면·허브 모두 정상"
        '''
      }
    }
  }

  post {
    success {
      echo '✅ 부동산 실거래 화면이 Kubernetes 웹서버에 배포되었습니다!'
    }
    failure {
      echo '❌ 빌드 또는 배포 실패!'
    }
  }
}

// ── 처음 배포할 때 ───────────────────────────────────────────────────────────
// 1) 웹서버 노드에 스테이징 경로를 만들어 둔다: mkdir -p /respal/deploy-estate
// 2) nginx 의 location /estate/ 설정(sj-lab-k8s-manifests/sj-lab-webserver/files/nginx-set.conf)이
//    반영돼 있어야 한다. 아직이면 Verify 단계가 허브 화면을 잡아내 실패로 떨어진다.
// 3) 화면이 데이터를 받으려면 조회 서비스(sj-lab-estate)가 먼저 배포돼 있어야 한다
//    (게이트웨이 /estate 라우트 포함). 없으면 화면은 뜨지만 "준비되지 않았다"고 안내한다.
// 4) 허브의 "부동산 실거래" 카드는 이미 /estate 로 열려 있으므로, 배포만 되면 바로 들어갈 수 있다.
// 5) authserver 의 ALLOWED_REDIRECT_ORIGINS 는 운영 도메인(sj-lab.co.kr)이 이미 있어 수정 불필요.
