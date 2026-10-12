"""백필을 지정한 구간 수에서 깔끔하게 멈춘다.

구간이 끝날 때마다 진행 상황 파일이 갱신되므로, 그 숫자가 목표에 닿는 순간 드라이버를 정지한다.
구간 중간에 끊으면 그 달을 다시 받아야 하므로(중복은 안 쌓이지만 시간 낭비) 경계에서 멈추는 쪽이 낫다.

사용: python scripts/estate-backfill-stop-at.py <목표_구간_수>
"""

import io
import json
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(REPO, ".local-stack", "estate-backfill.json")
PIDFILE = os.path.join(REPO, ".local-stack", "estate-backfill.pid")

target = int(sys.argv[1]) if len(sys.argv) > 1 else 0
if target <= 0:
    print("목표 구간 수를 숫자로 주세요.", flush=True)
    sys.exit(2)


def read_state():
    try:
        with io.open(STATE, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return None


print("구간 %d개가 끝나면 백필을 멈춥니다." % target, flush=True)

while True:
    state = read_state()
    if state is None:
        time.sleep(10)
        continue

    done = len(state.get("chunks") or [])
    if done >= target:
        try:
            with io.open(PIDFILE, encoding="utf-8-sig") as f:
                pid = f.read().strip()
            subprocess.run(["taskkill", "/PID", pid, "/F"], capture_output=True)
        except Exception as e:
            print("드라이버 정지 실패: %s" % type(e).__name__, flush=True)
            sys.exit(1)

        print(
            "백필 정지 — 구간 %d개 완료 · 커서 %s · 누적 매매 %s건 / 전월세 %s건"
            % (
                done,
                state.get("cursor"),
                format(int(state.get("insertedTrades", 0)), ","),
                format(int(state.get("insertedRents", 0)), ","),
            ),
            flush=True,
        )
        sys.exit(0)

    time.sleep(10)
