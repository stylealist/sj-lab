-- ============================================================================
-- 단지(apt_seq) 조회용 인덱스 — 제안 스크립트 (2026-11-11)
--
-- 대상 DB : sjlab (개발 = 운영 같은 인스턴스)
-- 실행 계정: 표 소유자(에이전트는 실행하지 않는다 — 프로젝트 규칙)
--
-- ──────────────────────────────────────────────────────────────────────────
-- 왜 필요한가
-- ──────────────────────────────────────────────────────────────────────────
-- 지도에서 아파트를 누르면 그 단지의 평형·추세·월별·거래 내역을 조회한다. 지금은
-- `(sgg_cd, deal_year, deal_month)` 인덱스로 **시군구 전체**를 고른 뒤 `apt_seq` 를
-- 필터로 걸러낸다. 그래서 단지 한 곳을 보려고 그 시군구의 수십만 행을 읽는다.
--
--   강남구 전월세            299,704 행
--   그 시군구 첫 조회            약 2초
--   같은 시군구 두 번째부터  0.05 ~ 0.15초   (디스크 캐시 효과)
--
-- 즉 **새 지역을 처음 누를 때마다 2초**씩 기다린다. 아래 인덱스를 만들면 단지 행만
-- 바로 찾아 그 대기가 없어진다.
--
-- ──────────────────────────────────────────────────────────────────────────
-- 비용(미리 알고 결정할 것)
-- ──────────────────────────────────────────────────────────────────────────
--  * 매매 약 1,000만 행 · 전월세 약 1,150만 행 → 인덱스 2개 합계 **대략 700MB~1GB**
--  * 만드는 동안 쓰기가 막히지 않게 `CONCURRENTLY` 를 쓴다(그래서 트랜잭션 밖에서
--    한 줄씩 실행해야 한다 — 한 번에 묶어 실행하면 오류가 난다).
--  * 수집(적재) 때 행마다 인덱스 기록이 하나 늘어난다. 백필처럼 대량 적재를 할 때는
--    떼고 시작해 끝난 뒤 다시 만드는 편이 빠르다(`docs/backfill-workflow.md` 5절).
--
-- ──────────────────────────────────────────────────────────────────────────
-- 실행 (한 줄씩, 트랜잭션 밖에서)
-- ──────────────────────────────────────────────────────────────────────────

-- 매매
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_apt_trade_complex
    ON estate.apt_trade (sgg_cd, apt_seq, deal_year DESC, deal_month DESC);

-- 전월세
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_apt_rent_complex
    ON estate.apt_rent (sgg_cd, apt_seq, deal_year DESC, deal_month DESC);

-- ──────────────────────────────────────────────────────────────────────────
-- 확인
-- ──────────────────────────────────────────────────────────────────────────

-- 1) 만들어졌는지 · 크기
SELECT indexrelname AS 인덱스, pg_size_pretty(pg_relation_size(indexrelid)) AS 크기
  FROM pg_stat_user_indexes
 WHERE indexrelname IN ('ix_apt_trade_complex', 'ix_apt_rent_complex');

-- 2) 계획이 바뀌었는지 — "Index Scan using ix_apt_rent_complex" 가 보여야 한다.
--    종전에는 "Bitmap Heap Scan ... Filter: (apt_seq = ...)" 였다.
EXPLAIN SELECT t.deal_year, t.deal_month, t.deal_day, t.deposit, t.monthly_rent
          FROM estate.apt_rent t
         WHERE t.sgg_cd = '11680' AND t.apt_seq = '11680-218'
         ORDER BY t.deal_year DESC, t.deal_month DESC, t.deal_day DESC
         LIMIT 500;

-- 3) 만들다 끊기면 쓸 수 없는 인덱스가 남는다(indisvalid = false). 그때는 지우고 다시 만든다.
SELECT c.relname AS 인덱스, i.indisvalid AS 사용가능
  FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
 WHERE c.relname IN ('ix_apt_trade_complex', 'ix_apt_rent_complex');
-- DROP INDEX CONCURRENTLY IF EXISTS estate.ix_apt_rent_complex;

-- ──────────────────────────────────────────────────────────────────────────
-- 되돌리기
-- ──────────────────────────────────────────────────────────────────────────
-- DROP INDEX CONCURRENTLY IF EXISTS estate.ix_apt_trade_complex;
-- DROP INDEX CONCURRENTLY IF EXISTS estate.ix_apt_rent_complex;
-- 지워도 화면은 그대로 동작한다 — 새 지역의 첫 조회가 다시 2초로 돌아갈 뿐이다.
