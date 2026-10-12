-- ============================================================================
-- 월·지역 집계를 MATERIALIZED VIEW 로 전환 (2026-10-12)
--
-- 왜 필요한가
--   `estate_apt.sql` 의 집계 뷰(v_apt_trade_monthly·v_apt_rent_monthly)는 부를 때마다
--   원본을 집계한다. 데이터가 2,100만 행이 되면서 **전국 조회가 느려졌다**(실측).
--
--     지역 한 곳(강남구) 13개월    0.04 초
--     전국 13개월 (매매)            8.6 초
--     전국 13개월 (전월세)         28.7 초
--
--   건수만 세는 건 인덱스로 0.11초면 끝난다(index only scan). 느린 이유는 평균·중위를
--   내려고 deposit·exclu_use_ar·deal_amount 같은 **인덱스에 없는 컬럼을 실제로 읽어야** 해서,
--   전국이면 78만 행을 디스크에서 끌어오기 때문이다.
--
--   미리 집계해 두면 조회가 행 수와 무관해진다(결과는 월 × 지역 = 수만 행).
--
-- 실행은 에이전트가 하지 않는다(프로젝트 규칙). DB 권한이 있는 담당자가 돌린다.
-- 처음 만들 때 전건을 집계하므로 **몇 분 걸린다**(한 번만).
--
-- 이 스크립트를 실행하지 않아도 화면은 그대로 동작한다 — 전국 조회만 느리다.
-- 즉 급하지 않으면 미뤄도 되고, 되돌리려면 맨 아래 "되돌리기"를 쓴다.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) 기존 일반 뷰를 치우고 같은 이름의 MATERIALIZED VIEW 를 만든다
--    이름을 그대로 쓰므로 조회 코드(fast-api-ai)는 고치지 않아도 된다.
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS estate.v_apt_trade_monthly;
DROP VIEW IF EXISTS estate.v_apt_rent_monthly;

CREATE MATERIALIZED VIEW IF NOT EXISTS estate.v_apt_trade_monthly AS
SELECT
    sgg_cd,
    deal_year,
    deal_month,
    count(*)                                                 AS deal_count,
    round(avg(deal_amount))                                  AS avg_amount,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY deal_amount)  AS median_amount,
    min(deal_amount)                                         AS min_amount,
    max(deal_amount)                                         AS max_amount,
    round(avg(exclu_use_ar), 2)                              AS avg_area,
    round(avg(deal_amount / NULLIF(exclu_use_ar, 0)), 1)      AS avg_amount_per_m2
FROM estate.apt_trade
WHERE deal_amount IS NOT NULL
GROUP BY sgg_cd, deal_year, deal_month;

CREATE MATERIALIZED VIEW IF NOT EXISTS estate.v_apt_rent_monthly AS
SELECT
    sgg_cd,
    deal_year,
    deal_month,
    count(*)                                                       AS deal_count,
    count(*) FILTER (WHERE COALESCE(monthly_rent, 0) = 0)          AS jeonse_count,
    count(*) FILTER (WHERE COALESCE(monthly_rent, 0) > 0)          AS wolse_count,
    round(avg(deposit) FILTER (WHERE COALESCE(monthly_rent, 0) = 0)) AS avg_jeonse_deposit,
    round(avg(deposit) FILTER (WHERE COALESCE(monthly_rent, 0) > 0)) AS avg_wolse_deposit,
    round(avg(monthly_rent) FILTER (WHERE COALESCE(monthly_rent, 0) > 0)) AS avg_monthly_rent,
    round(avg(exclu_use_ar), 2)                                    AS avg_area
FROM estate.apt_rent
GROUP BY sgg_cd, deal_year, deal_month;

COMMENT ON MATERIALIZED VIEW estate.v_apt_trade_monthly IS
    '아파트 매매 월·시군구 집계(미리 계산). 수집 후 REFRESH 가 필요하다. 금액 단위 만원';
COMMENT ON MATERIALIZED VIEW estate.v_apt_rent_monthly IS
    '아파트 전월세 월·시군구 집계(미리 계산). 수집 후 REFRESH 가 필요하다. monthly_rent=0 을 전세로 센다';

-- ----------------------------------------------------------------------------
-- 2) 인덱스
--    UNIQUE 인덱스가 있으면 REFRESH ... CONCURRENTLY 를 쓸 수 있다
--    (갱신하는 동안에도 조회가 막히지 않는다 — 화면이 멈추지 않게 하려면 필요하다).
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_apt_trade_monthly
    ON estate.v_apt_trade_monthly (sgg_cd, deal_year, deal_month);
CREATE UNIQUE INDEX IF NOT EXISTS ux_apt_rent_monthly
    ON estate.v_apt_rent_monthly (sgg_cd, deal_year, deal_month);

-- 전국 조회(지역 구분 없이 기간으로만)용
CREATE INDEX IF NOT EXISTS ix_apt_trade_monthly_period
    ON estate.v_apt_trade_monthly (deal_year, deal_month);
CREATE INDEX IF NOT EXISTS ix_apt_rent_monthly_period
    ON estate.v_apt_rent_monthly (deal_year, deal_month);

ANALYZE estate.v_apt_trade_monthly;
ANALYZE estate.v_apt_rent_monthly;

-- ----------------------------------------------------------------------------
-- 3) 갱신
--    수집(매일 06·07시) 직후에 돌려야 화면 숫자가 최신이 된다.
--    sj-lab-scheduler 에 넣을 때는 **표가 없을 수도 있으니** to_regclass 로 존재를 확인하고
--    없으면 건너뛰게 할 것(이 스크립트를 실행하지 않은 환경에서 배치가 실패하지 않게).
-- ----------------------------------------------------------------------------
-- REFRESH MATERIALIZED VIEW CONCURRENTLY estate.v_apt_trade_monthly;
-- REFRESH MATERIALIZED VIEW CONCURRENTLY estate.v_apt_rent_monthly;

-- ----------------------------------------------------------------------------
-- 되돌리기 — 일반 뷰로 복구 (estate_apt.sql 의 정의와 같다)
-- ----------------------------------------------------------------------------
-- DROP MATERIALIZED VIEW IF EXISTS estate.v_apt_trade_monthly;
-- DROP MATERIALIZED VIEW IF EXISTS estate.v_apt_rent_monthly;
-- 그다음 db/estate/estate_apt.sql 을 다시 실행하면 일반 뷰가 돌아온다.
