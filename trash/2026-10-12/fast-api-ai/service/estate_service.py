"""부동산 실거래 조회 로직.

SQL 은 전부 여기에 모은다 — 라우터는 입력 검증과 응답 형태만 맡는다.
금액 단위는 모두 **만원**이다(원천 공개데이터 그대로). 화면에서 억/만원으로 바꿔 보여 준다.
"""

from __future__ import annotations

from db import estate_db

# 한 번에 내려주는 거래 목록의 상한. 화면이 표로 그리는 양이고, 더 필요하면 기간을 좁히게 한다.
LIST_LIMIT_DEFAULT = 100
LIST_LIMIT_MAX = 1000


def _period_bounds(table: str) -> tuple[int | None, int | None]:
    """그 표의 가장 이른·늦은 거래 월(yyyyMM).

    `min(deal_year * 100 + deal_month)` 처럼 식으로 쓰면 인덱스를 못 타 전건을 훑는다.
    컬럼 순서대로 정렬해 한 행만 꺼내면 ix_*_period 인덱스를 그대로 쓴다.
    """
    first = estate_db.fetch_one(
        f"select deal_year, deal_month from {table} "
        "where deal_year is not null order by deal_year, deal_month limit 1"
    )
    last = estate_db.fetch_one(
        f"select deal_year, deal_month from {table} "
        "where deal_year is not null order by deal_year desc, deal_month desc limit 1"
    )
    to_ym = lambda row: (row["deal_year"] * 100 + row["deal_month"]) if row else None
    return to_ym(first), to_ym(last)


def _last_load(table: str, latest_ym: int | None):
    """마지막으로 적재된 시각.

    `created_at` 에는 인덱스가 없어 `max(created_at)` 을 그냥 부르면 전건을 훑는다
    (실측 23.4초, Parallel Seq Scan). 가장 최근 거래 월로 범위를 좁히면
    ix_*_period 인덱스로 그 달만 읽어 금방 끝난다. 수집은 최근 달을 다시 받는 구조라
    마지막 적재 시각은 늘 최근 달 안에 있다.
    """
    if not latest_ym:
        return None
    row = estate_db.fetch_one(
        f"select max(created_at) as last_load from {table} "
        "where deal_year = %s and deal_month = %s",
        (latest_ym // 100, latest_ym % 100),
    )
    return row["last_load"] if row else None


def get_meta() -> dict:
    """데이터가 어디부터 어디까지 있는지. 화면 상단 요약과 기간 선택의 기본값으로 쓴다.

    **건수는 `count(*)` 가 아니라 통계(`reltuples`) 추정치다.** 두 표가 2,100만 행이라
    정확히 세면 한 번에 **32초**가 걸려(실측) 화면이 열릴 때마다 그만큼 기다려야 했다.
    요약 카드에 쓰는 값이라 추정으로 충분하고, 응답에 `rows_estimated: true` 로 밝힌다.
    정확한 건수가 필요하면 DB에서 직접 세면 된다.

    추정치는 ANALYZE 기준이라 적재 직후 잠시 어긋날 수 있다. 수집은 하루 한 번이라
    실제로는 거의 차이가 없고, 그래도 `trade_last_load` 로 언제 기준인지 알 수 있다.
    """
    row = estate_db.fetch_one(
        """
        select
            greatest(0, (select reltuples::bigint from pg_class
                          where oid = 'estate.apt_trade'::regclass))  as trade_rows,
            greatest(0, (select reltuples::bigint from pg_class
                          where oid = 'estate.apt_rent'::regclass))   as rent_rows
        """
    )
    meta = dict(row or {})

    trade_from, trade_to = _period_bounds("estate.apt_trade")
    rent_from, rent_to = _period_bounds("estate.apt_rent")
    meta["trade_last_load"] = _last_load("estate.apt_trade", trade_to)
    meta.update(
        {
            "trade_from_ym": trade_from,
            "trade_to_ym": trade_to,
            "rent_from_ym": rent_from,
            "rent_to_ym": rent_to,
            # 지역 수는 regions 목록 길이로 알 수 있어 따로 세지 않는다
            # (count(distinct sgg_cd) 도 전건 훑기라 느리다)
            "trade_sgg_count": None,
            "rows_estimated": True,
        }
    )
    return meta


def get_regions() -> list[dict]:
    """데이터가 실제로 있는 시군구만 돌려준다(빈 지역을 고르게 하지 않으려고).

    이름은 public.g_sgg 에서 가져온다 — 코드(5자리)가 그대로 맞는다.
    """
    return estate_db.fetch_all(
        """
        select t.sgg_cd,
               coalesce(g.sgg_nm, t.sgg_cd) as sgg_nm,
               count(*)                     as deal_count
        from estate.apt_trade t
        left join public.g_sgg g on g.sgg_cd = t.sgg_cd
        group by t.sgg_cd, g.sgg_nm
        order by coalesce(g.sgg_nm, t.sgg_cd)
        """
    )


def _ym_filter(from_ym: int | None, to_ym: int | None, params: list, prefix: str = "") -> str:
    """거래 월 범위 조건을 만든다.

    **`deal_year * 100 + deal_month` 처럼 식으로 비교하지 말 것.** 식에는 인덱스가 걸리지
    않아 전건을 훑는다 — 실측으로 지역 순위 조회가 23.5초였다. 연도를 그냥 비교(`between`)해
    인덱스로 범위를 좁힌 뒤 경계 연도에서만 월을 따진다.

    prefix 는 g_sgg 와 조인하는 쿼리에서 테이블 별칭을 붙이기 위한 것이다("t.").
    조인하면 sgg_cd 가 양쪽에 있어 별칭 없이 쓰면 "column reference is ambiguous" 가 난다.
    """
    y = f"{prefix}deal_year"
    m = f"{prefix}deal_month"
    clauses = []

    if from_ym is not None and to_ym is not None:
        clauses.append(f"{y} between %s and %s")
        params.extend([from_ym // 100, to_ym // 100])
    elif from_ym is not None:
        clauses.append(f"{y} >= %s")
        params.append(from_ym // 100)
    elif to_ym is not None:
        clauses.append(f"{y} <= %s")
        params.append(to_ym // 100)

    # 경계 연도에서만 월을 본다(그 안쪽 연도는 위 조건으로 이미 걸러졌다)
    if from_ym is not None:
        clauses.append(f"({y} > %s or {m} >= %s)")
        params.extend([from_ym // 100, from_ym % 100])
    if to_ym is not None:
        clauses.append(f"({y} < %s or {m} <= %s)")
        params.extend([to_ym // 100, to_ym % 100])

    return (" and " + " and ".join(clauses)) if clauses else ""


def get_trade_monthly(sgg_cd: str | None, from_ym: int | None, to_ym: int | None) -> list[dict]:
    """매매 월별 추세. 집계 뷰(estate.v_apt_trade_monthly)를 쓴다.

    sgg_cd 를 주면 그 지역만, 안 주면 전국을 월별로 다시 합친다
    (뷰가 지역별이라 전국은 건수 가중으로 합쳐야 평균이 맞다).
    """
    params: list = []
    if sgg_cd:
        params.append(sgg_cd)
        where = "where sgg_cd = %s"
        where += _ym_filter(from_ym, to_ym, params)
        return estate_db.fetch_all(
            f"""
            select deal_year, deal_month,
                   deal_year * 100 + deal_month as ym,
                   deal_count, avg_amount, median_amount,
                   min_amount, max_amount, avg_area, avg_amount_per_m2
            from estate.v_apt_trade_monthly
            {where}
            order by ym
            """,
            params,
        )

    where = "where deal_amount is not null"
    where += _ym_filter(from_ym, to_ym, params)
    return estate_db.fetch_all(
        f"""
        select deal_year, deal_month,
               deal_year * 100 + deal_month as ym,
               count(*)                                                 as deal_count,
               round(avg(deal_amount))                                  as avg_amount,
               percentile_cont(0.5) within group (order by deal_amount)  as median_amount,
               min(deal_amount)                                         as min_amount,
               max(deal_amount)                                         as max_amount,
               round(avg(exclu_use_ar), 2)                              as avg_area,
               round(avg(deal_amount / nullif(exclu_use_ar, 0)), 1)      as avg_amount_per_m2
        from estate.apt_trade
        {where}
        group by deal_year, deal_month
        order by ym
        """,
        params,
    )


def get_rent_monthly(sgg_cd: str | None, from_ym: int | None, to_ym: int | None) -> list[dict]:
    """전월세 월별 추세. monthly_rent = 0 을 전세로 센다."""
    params: list = []
    if sgg_cd:
        params.append(sgg_cd)
        where = "where sgg_cd = %s"
        where += _ym_filter(from_ym, to_ym, params)
        return estate_db.fetch_all(
            f"""
            select deal_year, deal_month,
                   deal_year * 100 + deal_month as ym,
                   deal_count, jeonse_count, wolse_count,
                   avg_jeonse_deposit, avg_wolse_deposit, avg_monthly_rent, avg_area
            from estate.v_apt_rent_monthly
            {where}
            order by ym
            """,
            params,
        )

    where = "where 1 = 1"
    where += _ym_filter(from_ym, to_ym, params)
    return estate_db.fetch_all(
        f"""
        select deal_year, deal_month,
               deal_year * 100 + deal_month as ym,
               count(*)                                                        as deal_count,
               count(*) filter (where coalesce(monthly_rent, 0) = 0)            as jeonse_count,
               count(*) filter (where coalesce(monthly_rent, 0) > 0)            as wolse_count,
               round(avg(deposit) filter (where coalesce(monthly_rent, 0) = 0)) as avg_jeonse_deposit,
               round(avg(deposit) filter (where coalesce(monthly_rent, 0) > 0)) as avg_wolse_deposit,
               round(avg(monthly_rent) filter (where coalesce(monthly_rent, 0) > 0)) as avg_monthly_rent,
               round(avg(exclu_use_ar), 2)                                     as avg_area
        from estate.apt_rent
        {where}
        group by deal_year, deal_month
        order by ym
        """,
        params,
    )


def get_trades(
    sgg_cd: str | None,
    from_ym: int | None,
    to_ym: int | None,
    apt_nm: str | None,
    limit: int,
) -> list[dict]:
    """매매 거래 목록(표). 비싼 순이 아니라 최근 계약일 순으로 준다."""
    params: list = []
    where = "where 1 = 1"
    if sgg_cd:
        where += " and t.sgg_cd = %s"
        params.append(sgg_cd)
    where += _ym_filter(from_ym, to_ym, params, prefix="t.")
    if apt_nm:
        where += " and t.apt_nm ilike %s"
        params.append(f"%{apt_nm}%")
    params.append(limit)

    return estate_db.fetch_all(
        f"""
        select t.sgg_cd,
               coalesce(g.sgg_nm, t.sgg_cd) as sgg_nm,
               t.umd_nm, t.apt_nm, t.apt_dong, t.jibun,
               t.exclu_use_ar, t.floor, t.build_year,
               t.deal_year, t.deal_month, t.deal_day,
               t.deal_amount, t.dealing_gbn, t.cdeal_type,
               round(t.deal_amount / nullif(t.exclu_use_ar, 0), 1) as amount_per_m2
        from estate.apt_trade t
        left join public.g_sgg g on g.sgg_cd = t.sgg_cd
        {where}
        order by t.deal_year desc, t.deal_month desc, t.deal_day desc, t.deal_amount desc
        limit %s
        """,
        params,
    )


def get_trade_ranking(from_ym: int | None, to_ym: int | None, limit: int) -> list[dict]:
    """지역별 평균 거래가 순위. 거래가 너무 적은 지역은 평균이 튀므로 10건 이상만 센다."""
    params: list = []
    where = "where t.deal_amount is not null"
    where += _ym_filter(from_ym, to_ym, params, prefix="t.")
    params.append(limit)

    return estate_db.fetch_all(
        f"""
        select t.sgg_cd,
               coalesce(g.sgg_nm, t.sgg_cd) as sgg_nm,
               count(*)                     as deal_count,
               round(avg(t.deal_amount))    as avg_amount,
               round(avg(t.deal_amount / nullif(t.exclu_use_ar, 0)), 1) as avg_amount_per_m2
        from estate.apt_trade t
        left join public.g_sgg g on g.sgg_cd = t.sgg_cd
        {where}
        group by t.sgg_cd, g.sgg_nm
        having count(*) >= 10
        order by avg_amount desc
        limit %s
        """,
        params,
    )
