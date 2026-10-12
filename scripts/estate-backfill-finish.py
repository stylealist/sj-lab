"""백필이 끝나면 스케줄러를 내리고 최종 결과를 파일로 남긴다.

사람이 지켜보지 않는 동안(퇴근 등) 혼자 돌아야 하므로, 다음을 모두 스스로 처리한다.
  1) 백필이 끝났는지 감시 — 멈춤 규칙 도달(doneTrades·doneRents) 또는 드라이버 프로세스 종료
  2) 끝나면 스케줄러(8120) 정지 — 켜 둔 채 두면 밤에 cron 배치가 DB에 적재한다
  3) DB 를 조회해 최종 결과를 .local-stack/estate-backfill-final.md 에 기록

DB 조회가 실패해도 진행 상황 파일 기준으로는 기록을 남긴다(결과가 아예 없는 것보다 낫다).

사용: python scripts/estate-backfill-finish.py
"""

from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import time
from datetime import datetime

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCAL = os.path.join(REPO, ".local-stack")
STATE = os.path.join(LOCAL, "estate-backfill.json")
BACKFILL_PID = os.path.join(LOCAL, "estate-backfill.pid")
SCHEDULER_PID = os.path.join(LOCAL, "scheduler.pid")
REPORT = os.path.join(LOCAL, "estate-backfill-final.md")
SETTINGS = os.path.join(REPO, ".claude", "settings.local.json")
# fast-api-ai 가상환경에 psycopg 가 이미 깔려 있다(조회 API 용). 그걸 그대로 쓴다.
VENV_PY = r"C:\developer\workspace\fast-api-ai\.venv\Scripts\python.exe"

POLL_SEC = 30


def read_json(path):
    try:
        with io.open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except Exception:
        return None


def read_pid(path):
    try:
        with io.open(path, encoding="utf-8-sig") as f:
            return int(f.read().strip())
    except Exception:
        return None


def alive(pid):
    if pid is None:
        return False
    try:
        import ctypes

        handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            return False
        code = ctypes.c_ulong()
        ok = ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(code))
        ctypes.windll.kernel32.CloseHandle(handle)
        return bool(ok) and code.value == 259
    except Exception:
        return True


def stop(pid, label):
    if pid is None:
        return f"{label}: pid 파일 없음"
    if not alive(pid):
        return f"{label}: 이미 정지됨 (pid {pid})"
    subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True)
    return f"{label}: 정지 (pid {pid})"


def query_db():
    """최종 통계를 조회한다. 실패하면 None 을 돌려준다."""
    settings = read_json(SETTINGS) or {}
    dsn = (settings.get("env") or {}).get("ESTATE_DB_DSN", "")
    if not dsn or not os.path.exists(VENV_PY):
        return None

    script = r'''
import json, sys
import psycopg
from psycopg.rows import dict_row
dsn = sys.argv[1]
out = {}
with psycopg.connect(dsn, connect_timeout=20) as conn:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute("""
            select
              (select count(*) from estate.apt_trade) as trade_rows,
              (select count(*) from estate.apt_rent)  as rent_rows,
              (select min(deal_year*100+deal_month) from estate.apt_trade) as trade_from,
              (select max(deal_year*100+deal_month) from estate.apt_trade) as trade_to,
              (select min(deal_year*100+deal_month) from estate.apt_rent)  as rent_from,
              (select max(deal_year*100+deal_month) from estate.apt_rent)  as rent_to,
              (select count(distinct sgg_cd) from estate.apt_trade) as sgg_count,
              pg_size_pretty(pg_total_relation_size('estate.apt_trade')) as trade_size,
              pg_size_pretty(pg_total_relation_size('estate.apt_rent'))  as rent_size,
              pg_size_pretty(pg_total_relation_size('estate.apt_trade')
                           + pg_total_relation_size('estate.apt_rent'))  as total_size
        """)
        out["summary"] = cur.fetchone()
        cur.execute("""
            select deal_year,
                   count(*) as trades,
                   (select count(*) from estate.apt_rent r where r.deal_year = t.deal_year) as rents
            from estate.apt_trade t
            group by deal_year order by deal_year
        """)
        out["by_year"] = cur.fetchall()
print(json.dumps(out, default=str, ensure_ascii=False))
'''
    try:
        proc = subprocess.run(
            [VENV_PY, "-c", script, dsn], capture_output=True, text=True, timeout=600
        )
        if proc.returncode != 0:
            return {"error": (proc.stderr or "")[-400:]}
        return json.loads(proc.stdout)
    except Exception as e:
        return {"error": type(e).__name__}


def write_report(state, stop_lines, db, reason):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        "# 아파트 실거래 백필 최종 결과",
        "",
        f"- 기록 시각: {now}",
        f"- 종료 사유: {reason}",
        "",
        "## 진행 상황 파일 기준",
        "",
        f"- 완료 구간: {len(state.get('chunks') or [])}개월",
        f"- 커서(다음 재개 지점): {state.get('cursor')}",
        f"- 이번 실행들에서 새로 적재: 매매 {int(state.get('insertedTrades', 0)):,}건 / "
        f"전월세 {int(state.get('insertedRents', 0)):,}건",
        f"- 멈춤 규칙 도달: 매매 {state.get('doneTrades')} / 전월세 {state.get('doneRents')}",
        "",
        "## 정지 결과",
        "",
    ]
    lines += [f"- {line}" for line in stop_lines]
    lines.append("")

    if db and "error" not in db:
        s = db["summary"]
        lines += [
            "## DB 최종 상태",
            "",
            "| 항목 | 매매 | 전월세 |",
            "|---|---|---|",
            f"| 행 수 | {int(s['trade_rows']):,} | {int(s['rent_rows']):,} |",
            f"| 기간 | {s['trade_from']} ~ {s['trade_to']} | {s['rent_from']} ~ {s['rent_to']} |",
            f"| 용량 | {s['trade_size']} | {s['rent_size']} |",
            "",
            f"- 수집 시군구: {s['sgg_count']}개",
            f"- estate 스키마 합계 용량: {s['total_size']}",
            "",
            "### 연도별 건수",
            "",
            "| 연도 | 매매 | 전월세 |",
            "|---|---|---|",
        ]
        for row in db.get("by_year", []):
            lines.append(
                f"| {row['deal_year']} | {int(row['trades']):,} | {int(row['rents']):,} |"
            )
        lines.append("")
    else:
        lines += [
            "## DB 최종 상태",
            "",
            "DB 조회에 실패해 진행 상황 파일 기준으로만 기록했습니다"
            + (f" (원인: {db.get('error')})" if db else ""),
            "",
        ]

    lines += [
        "## 다음에 할 일",
        "",
        "- 백필을 더 돌려야 하면: `scripts\\estate-backfill.ps1 -chunkMonths 1 "
        "-baseUrl http://localhost:8120/scheduler` (커서부터 이어서)",
        "- 조회 화면에서 보려면 스케줄러 대신 `fast-api-ai`(8000)와 `sj-lab-estate-web`(4200)을 띄울 것",
        "- 커밋 안 된 변경이 여러 저장소에 남아 있음(scheduler · fast-api-ai · estate-web · hub · sj-lab)",
        "",
    ]
    io.open(REPORT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))


print("백필 완료를 감시합니다. 끝나면 스케줄러를 내리고 결과를 기록합니다.", flush=True)

while True:
    state = read_json(STATE)
    if state is None:
        time.sleep(POLL_SEC)
        continue

    done_by_rule = bool(state.get("doneTrades")) and bool(state.get("doneRents"))
    driver_gone = not alive(read_pid(BACKFILL_PID))

    if done_by_rule or driver_gone:
        reason = (
            "멈춤 규칙 도달(매매·전월세 모두 12개월 연속 0건)"
            if done_by_rule
            else "백필 드라이버 종료(한도 대기 한계 또는 외부 종료)"
        )
        stop_lines = [
            stop(read_pid(BACKFILL_PID), "백필 드라이버"),
            stop(read_pid(SCHEDULER_PID), "스케줄러(8120)"),
        ]
        time.sleep(5)  # 커넥션이 정리될 틈을 준다
        db = query_db()
        write_report(state, stop_lines, db, reason)
        print("완료 — 결과를 %s 에 기록했습니다. (%s)" % (REPORT, reason), flush=True)
        sys.exit(0)

    time.sleep(POLL_SEC)
