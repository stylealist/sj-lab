"""백필 구간이 끝날 때마다 한 줄 출력한다(채팅 알림용).

estate-backfill.ps1 이 구간을 마칠 때마다 .local-stack/estate-backfill.json 을 다시 쓴다.
그 파일의 chunks 개수가 늘어나면 그 구간 결과를 한 줄로 찍는다.
백필이 멈추거나(정상 종료) 드라이버가 죽으면 그것도 알린다 — 조용히 끝나면 안 되므로.

사용: python scripts/estate-backfill-notify.py
"""

import json
import os
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(REPO, ".local-stack", "estate-backfill.json")
PIDFILE = os.path.join(REPO, ".local-stack", "estate-backfill.pid")
OLDEST = 200601


def emit(message):
    print(message, flush=True)


def read_state():
    try:
        with open(STATE, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return None


def months_left(cursor):
    try:
        year, month = int(str(cursor)[:4]), int(str(cursor)[4:6])
        return max(0, (year * 12 + month) - (OLDEST // 100 * 12 + OLDEST % 100))
    except Exception:
        return -1


def driver_alive():
    """드라이버 프로세스가 살아 있는지.

    전에는 tasklist 를 os.system 으로 불러 판단했는데, 셸 환경에 따라 그 명령이
    실패해 "죽었다"고 잘못 알리는 일이 있었다(2026-10-06 오경보). 그래서
    psutil 없이도 맞게 동작하는 방법만 쓰고, 판단이 안 되면 살아 있다고 본다.
    진행이 멈춘 것은 아래 "10분 넘게 진행 없음" 쪽이 잡아 준다.
    """
    try:
        with open(PIDFILE, encoding="utf-8-sig") as f:
            pid = int(f.read().strip())
    except Exception:
        return True

    if os.name != "nt":
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False

    try:
        import ctypes

        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        handle = ctypes.windll.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return False
        exit_code = ctypes.c_ulong()
        ok = ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code))
        ctypes.windll.kernel32.CloseHandle(handle)
        if not ok:
            return True  # 판단 불가 — 살아 있다고 본다
        return exit_code.value == 259  # STILL_ACTIVE
    except Exception:
        return True


# 알림 묶음 크기 — 이만큼 구간이 쌓일 때마다 한 줄로 묶어 알린다.
# 인자로 받고 기본은 3이다(1로 주면 한 달마다 알린다).
# 커밋·조회 반영은 어느 쪽이든 1개월 단위다 — 알림 빈도만 바뀐다.
#   python scripts/estate-backfill-notify.py 1
NOTIFY_EVERY = int(sys.argv[1]) if len(sys.argv) > 1 else 3

seen = -1
idle_rounds = 0
pending = []  # 아직 알리지 않은 완료 구간

while True:
    state = read_state()
    if state is None:
        time.sleep(10)
        continue

    chunks = state.get("chunks") or []
    if seen < 0:
        seen = len(chunks)  # 처음 한 바퀴는 기준만 잡고 넘어간다
    elif len(chunks) > seen:
        pending.extend(chunks[seen:])
        seen = len(chunks)
        idle_rounds = 0
    else:
        idle_rounds += 1

    # 3개월씩 묶어서 한 줄로 알린다
    while len(pending) >= NOTIFY_EVERY:
        batch, pending[:] = pending[:NOTIFY_EVERY], pending[NOTIFY_EVERY:]
        newest = batch[0].split("~")[-1]
        oldest = batch[-1].split("~")[0]
        emit(
            "%s ~ %s 적재 완료(%d개월) · 누적 매매 %s건 / 전월세 %s건 · 남은 개월 %d"
            % (
                oldest,
                newest,
                len(batch),
                format(int(state.get("insertedTrades", 0)), ","),
                format(int(state.get("insertedRents", 0)), ","),
                months_left(state.get("cursor")),
            )
        )

    if state.get("doneTrades") and state.get("doneRents"):
        # 끝났으면 묶이지 않고 남은 구간도 함께 알린다
        if pending:
            emit("마지막 %d개월(%s) 적재 완료" % (len(pending), ", ".join(pending)))
        emit(
            "백필 종료 — 매매·전월세 모두 12개월 연속 0건에 도달했습니다. 누적 매매 %s건 / 전월세 %s건"
            % (
                format(int(state.get("insertedTrades", 0)), ","),
                format(int(state.get("insertedRents", 0)), ","),
            )
        )
        sys.exit(0)

    if not driver_alive():
        emit(
            "백필 드라이버가 멈췄습니다(프로세스 없음). 커서 %s, 누적 매매 %s / 전월세 %s"
            % (
                state.get("cursor"),
                format(int(state.get("insertedTrades", 0)), ","),
                format(int(state.get("insertedRents", 0)), ","),
            )
        )
        sys.exit(1)

    # 진행이 오래 없으면 알린다.
    # 호출 한도(429)에 걸리면 드라이버가 20분씩 기다렸다 같은 구간을 다시 받으므로,
    # 10분 기준으로는 정상 대기에도 경보가 울렸다(2026-10-07). 그래서 대기 시간보다 길게 잡고
    # 문구도 "한도 대기일 수 있다"로 바꿨다.
    if idle_rounds >= 120:  # 30분
        emit(
            "30분 넘게 구간이 늘지 않았습니다. 커서 %s — 호출 한도 대기 중이거나 scheduler(8120)가 멈췄을 수 있습니다."
            % state.get("cursor")
        )
        idle_rounds = 0

    time.sleep(15)
