"""Jenkins 파이프라인 잡의 config.xml 을 만든다.

파이프라인 원본(`docs/jenkins/<서비스>-pipeline.groovy`)을 그대로 읽어 XML 안에 넣으므로
**원본이 단일 소스**가 된다 — groovy 를 고치면 이 스크립트를 다시 돌려 XML 을 갱신한다.

Jenkins 웹 UI 에서 [Pipeline script] 칸에 붙여 넣어도 결과는 같다. XML 이 필요한 이유는
① 잡 설정(트리거·GitHub 주소)까지 함께 기록해 두고 ② API 로 한 번에 만들 수 있기 때문이다.

사용법
    python scripts/make-jenkins-job-config.py docs/jenkins/sj-lab-estate-web-pipeline.groovy \
        --repo https://github.com/stylealist/sj-lab-estate-web \
        --description "부동산 실거래 화면(React) 빌드 → 웹서버 html/estate 배포"

    (출력 경로를 주지 않으면 같은 폴더에 <이름>-job-config.xml 로 쓴다)

만든 XML 로 잡 생성 (Jenkins API 토큰 필요 — 토큰을 저장소·문서에 적지 말 것)
    curl -X POST "https://jenkins.sj-lab.co.kr/createItem?name=PROD-SJ-LAB-ESTATE-WEB" \
         -u "<계정>:<API 토큰>" -H "Content-Type: text/xml" \
         --data-binary @docs/jenkins/sj-lab-estate-web-job-config.xml

이미 있는 잡을 갱신할 때는 `.../job/<잡이름>/config.xml` 로 POST 한다.
"""

from __future__ import annotations

import argparse
import io
import os
from xml.sax.saxutils import escape

TEMPLATE = """<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <actions/>
  <description>{description}</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <com.coravy.hudson.plugins.github.GithubProjectProperty plugin="github">
      <projectUrl>{repo}/</projectUrl>
      <displayName></displayName>
    </com.coravy.hudson.plugins.github.GithubProjectProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>{script}</script>
    <sandbox>true</sandbox>
  </definition>
  <triggers>
{triggers}  </triggers>
  <disabled>false</disabled>
</flow-definition>
"""

GITHUB_PUSH_TRIGGER = (
    "    <com.cloudbees.jenkins.GitHubPushTrigger plugin=\"github\">\n"
    "      <spec></spec>\n"
    "    </com.cloudbees.jenkins.GitHubPushTrigger>\n"
)


def build(pipeline_path: str, repo: str, description: str, with_trigger: bool) -> str:
    script = io.open(pipeline_path, encoding="utf-8").read()
    return TEMPLATE.format(
        description=escape(description),
        repo=escape(repo.rstrip("/")),
        script=escape(script),
        triggers=GITHUB_PUSH_TRIGGER if with_trigger else "",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Jenkins 파이프라인 잡 config.xml 생성")
    parser.add_argument("pipeline", help="docs/jenkins/<서비스>-pipeline.groovy")
    parser.add_argument("--repo", required=True, help="GitHub 저장소 주소")
    parser.add_argument("--description", default="", help="잡 설명")
    parser.add_argument("--out", help="출력 XML 경로(기본: <파이프라인>-job-config.xml)")
    parser.add_argument(
        "--no-trigger",
        action="store_true",
        help="GitHub push 트리거를 넣지 않는다(수동 실행만 할 잡)",
    )
    args = parser.parse_args()

    out = args.out
    if not out:
        base = args.pipeline
        if base.endswith("-pipeline.groovy"):
            base = base[: -len("-pipeline.groovy")]
        out = base + "-job-config.xml"

    xml = build(args.pipeline, args.repo, args.description, not args.no_trigger)
    io.open(out, "w", encoding="utf-8", newline="\n").write(xml)
    print("작성: %s (%d bytes)" % (out, os.path.getsize(out)))


if __name__ == "__main__":
    main()
