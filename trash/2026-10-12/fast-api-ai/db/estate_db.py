"""부동산(estate 스키마) 조회용 DB 접근.

조회만 한다 — 적재는 sj-lab-scheduler 가 맡는다. 여기서 INSERT/UPDATE 를 하지 말 것
(같은 표에 두 곳이 쓰면 중복·충돌을 추적할 수 없다).

접속 문자열이 없으면 예외를 던지고, 라우터가 그걸 503 으로 바꾼다.
설정이 없어도 앱 자체는 떠야 하므로 풀은 처음 쓸 때 만든다(지연 생성).
"""

from __future__ import annotations

import threading
from typing import Any, Sequence

from core.config import settings

_pool = None
_pool_lock = threading.Lock()


class EstateDbNotConfigured(RuntimeError):
    """ESTATE_DB_DSN 이 비어 있어 조회할 수 없는 상태."""


def _create_pool():
    # import 를 함수 안에서 한다 — psycopg 가 없는 환경에서도 앱이 뜨게 하려고.
    from psycopg_pool import ConnectionPool

    return ConnectionPool(
        conninfo=settings.ESTATE_DB_DSN,
        min_size=settings.ESTATE_DB_POOL_MIN,
        max_size=settings.ESTATE_DB_POOL_MAX,
        open=True,
        kwargs={"options": "-c default_transaction_read_only=on"},
    )


def get_pool():
    global _pool
    if not settings.ESTATE_DB_DSN:
        raise EstateDbNotConfigured(
            "ESTATE_DB_DSN 이 설정되지 않았습니다. 환경변수로 접속 문자열을 넣어 주세요."
        )
    if _pool is None:
        with _pool_lock:
            if _pool is None:
                _pool = _create_pool()
    return _pool


def is_ready() -> bool:
    """부동산 API 를 쓸 수 있는 상태인지. 화면이 안내 문구를 고를 때 쓴다."""
    if not settings.ESTATE_DB_DSN:
        return False
    try:
        fetch_all("select 1")
        return True
    except Exception:
        return False


def fetch_all(sql: str, params: Sequence[Any] | None = None) -> list[dict]:
    """SELECT 결과를 dict 목록으로 돌려준다.

    파라미터는 반드시 %s 바인딩으로 넘길 것 — 문자열을 SQL 에 이어 붙이지 말 것.
    """
    from psycopg.rows import dict_row

    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(sql, params or ())
            return list(cur.fetchall())


def fetch_one(sql: str, params: Sequence[Any] | None = None) -> dict | None:
    rows = fetch_all(sql, params)
    return rows[0] if rows else None
