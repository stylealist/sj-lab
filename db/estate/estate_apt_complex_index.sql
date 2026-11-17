-- ============================================================================
-- 단지(apt_seq) 조회용 인덱스 — **2026-11-17 실행 완료**
--
-- 제안 2026-11-11 · 재측정 2026-11-17 · CONCURRENTLY 없이 실행 2026-11-17
--
-- 실행 결과 (사용자가 DB 툴에서 CONCURRENTLY 없이 실행)
--
--   ix_apt_trade_complex  189MB  valid
--   ix_apt_rent_complex   188MB  valid      → 둘 합쳐 377MB (추정 550~650MB 보다 적었다)
--
--   같은 쿼리(수원시 영통구 단지 한 곳 전월세)
--     전              1,870ms · 118,800행 읽고 버림 · 4,994블록
--     후(첫 조회)        33ms · 121블록      ← Index Scan using ix_apt_rent_complex
--     후(두 번째)       0.4ms · 디스크 읽기 없음
--   매매 쪽도 같다 — 청주 흥덕구 단지 500건 0.9ms(정렬도 필요 없다, 인덱스 순서 그대로)
--
--   운영 화면 기준 "처음 누르는 지역의 단지 상세"
--     전   약 2초
--     후   160~190ms (두 번째 70ms) · 전월세만 있는 단지도 96ms
--
-- 대상 DB : sjlab (개발 = 운영 같은 인스턴스)
-- 실행 계정: 표 소유자 — **에이전트는 실행하지 않는다**(프로젝트 규칙)
-- 실행 도구: DB 툴(DBeaver 등) 그대로. 아래 1단계는 트랜잭션 안에서도 된다.
--
-- ============================================================================
-- 1. 실행 — 이 두 줄을 "하나씩" 실행한다
-- ============================================================================
--
-- 각 1~3분 예상. 끝나면 **반드시 Commit**(이유는 4절).
-- 정렬 메모리를 올리면 빨라진다(이 세션에만 적용되고 서버 설정은 바뀌지 않는다).

SET maintenance_work_mem = '1GB';

-- 매매 (약 985만 행)
CREATE INDEX IF NOT EXISTS ix_apt_trade_complex
    ON estate.apt_trade (sgg_cd, apt_seq, deal_year DESC, deal_month DESC);

-- 전월세 (약 1,170만 행)
CREATE INDEX IF NOT EXISTS ix_apt_rent_complex
    ON estate.apt_rent (sgg_cd, apt_seq, deal_year DESC, deal_month DESC);

-- ★ 여기서 Commit ★


-- ============================================================================
-- 2. 확인
-- ============================================================================

-- 2-1) 만들어졌는지 · 크기 (예상: 둘 합쳐 550~650MB)
SELECT indexrelname AS 인덱스, pg_size_pretty(pg_relation_size(indexrelid)) AS 크기
  FROM pg_stat_user_indexes
 WHERE indexrelname IN ('ix_apt_trade_complex', 'ix_apt_rent_complex');

-- 2-2) 계획이 바뀌었는지 — "Index Scan using ix_apt_rent_complex" 가 보여야 한다.
--      종전에는 "Parallel Bitmap Heap Scan ... Filter: (apt_seq = ...)" 였다.
EXPLAIN ANALYZE
SELECT t.deal_year, t.deal_month, t.deal_day, t.exclu_use_ar, t.floor, t.deposit, t.monthly_rent
  FROM estate.apt_rent t
 WHERE t.sgg_cd = '41117' AND t.apt_seq = '41117-1'
 ORDER BY t.deal_year DESC, t.deal_month DESC, t.deal_day DESC
 LIMIT 500;
-- 2026-11-17 실행 전 실측: 1,870ms · 118,800행을 읽고 버려 122건을 돌려줬다.

-- 2-3) 만드는 동안 막힌 것이 있는지(진행 중에 다른 창에서 본다)
SELECT pid, state, wait_event_type, left(query, 60) AS query
  FROM pg_stat_activity
 WHERE datname = 'sjlab' AND state <> 'idle'
 ORDER BY xact_start;


-- ============================================================================
-- 3. 되돌리기 — 지워도 화면은 그대로 동작한다(첫 조회가 다시 2초로 돌아갈 뿐)
-- ============================================================================

-- DROP INDEX IF EXISTS estate.ix_apt_trade_complex;
-- DROP INDEX IF EXISTS estate.ix_apt_rent_complex;


-- ============================================================================
-- 4. 실행 전에 알고 있을 것 (위험 3가지)
-- ============================================================================
--
-- 4-1) **끝난 뒤 Commit 을 잊는 것이 가장 큰 위험이다.**
--      CREATE INDEX 가 끝나도 트랜잭션이 열려 있으면 **SHARE 락이 커밋할 때까지 유지**된다.
--      이 DB 는 `idle_in_transaction_session_timeout = 0` 이라 **무한정 유지**되고,
--      `lock_timeout = 0` 이라 막힌 쓰기는 오류 없이 **끝없이 기다린다.**
--      게다가 커밋하지 않고 세션을 닫으면 **롤백되어 몇 분 걸린 작업이 날아간다.**
--
-- 4-2) 만드는 동안 그 표에 **SHARE 락**이 걸린다.
--        * 조회(SELECT)는 **그대로 된다** — 화면·API 는 멈추지 않는다(ACCESS SHARE 와 충돌 없음).
--        * 쓰기(INSERT/UPDATE/DELETE)만 기다린다 → 실질적으로 **수집(scheduler)만** 막힌다.
--        * 실거래 수집 cron 은 **매매 06:00 · 전월세 07:00**(각 이번 달 + 지난달, 20~30분)이다.
--          그 시간대만 피하면 막힐 쓰기가 없다. 막혀도 실패가 아니라 대기이고 끝나면 이어진다.
--        * 백필(대량 적재)을 돌리는 중이라면 끝난 뒤에 할 것.
--
-- 4-3) 디스크·WAL 을 쓴다 — 인덱스 550~650MB + 정렬 임시 파일 + WAL(압축 on·max_wal_size 3GB).
--
-- 반대로 이 방법의 장점:
--   * 중간에 끊기면 **깔끔히 롤백**된다 — `CONCURRENTLY` 가 겪는 "못 쓰는 인덱스가 남는 문제"
--     (`indisvalid = false`)가 **없다.**
--   * **더 빠르다** — 표를 한 번만 읽고 병렬 워커도 쓴다(`max_parallel_maintenance_workers = 2`).
--     `CONCURRENTLY` 는 표를 두 번 읽고 병렬 빌드를 쓰지 못한다.
--
--
-- ============================================================================
-- 5. 왜 필요한가 (2026-11-17 실측)
-- ============================================================================
--
-- 지도에서 아파트를 누르면 그 단지의 평형·추세·월별·거래 내역을 조회한다. 그런데 단지 키에
-- 인덱스가 없어, 지금은 `(sgg_cd, deal_year, deal_month)` 인덱스로 **시군구 전체**를 고른 뒤
-- `apt_seq` 를 필터로 걸러낸다.
--
--   Parallel Bitmap Heap Scan on apt_rent
--     Recheck Cond: sgg_cd = '41117'          ← 시군구로만 좁힌다
--     Filter: apt_seq = '41117-1'
--     Rows Removed by Filter: 118,800         ← 읽고 버린 행
--   Buffers: read 4,994 블록 (약 39MB)
--   Execution Time: 1,870 ms                  ← 돌려준 행은 122건뿐
--
-- 즉 **122건을 주려고 12만 행을 읽고 버린다.** 그래서 **새 지역에서 단지를 처음 누를 때마다
-- 약 2초**가 걸린다(같은 지역 두 번째부터는 디스크 캐시 덕에 0.05~0.15초).
--
--   * 2026-11-16 에 만든 **전국 단지 검색** 때문에 다른 지역 단지를 바로 고르는 일이 많아져
--     이 2초를 더 자주 만난다.
--   * 2026-11-17 에 단지 상세가 **매매가 없으면 전월세 표에서** 기본 정보·평형을 만들도록
--     바뀌었다(`selectComplexRentSummary`·`selectComplexRentAreas`, 전월세만 있는 단지 3,053개).
--     그 두 조회도 `(sgg_cd, apt_seq)` 로 찾으므로 **수혜 대상이 늘었다.**
--
-- 크기 추정 근거: 같은 표의 `(sgg_cd, deal_year, deal_month)` 인덱스가 전월세 213MB · 매매
-- 119MB 이고, 여기에 `apt_seq`(11자) 한 칸이 붙는 정도다. 지금 인덱스 합계는 전월세 3,634MB ·
-- 매매 1,867MB, 표 자체는 전월세 3,083MB · 매매 2,183MB.
--
-- 수집 쪽 영향: 적재 행마다 인덱스 기록이 하나 늘어난다. 백필처럼 대량으로 받을 때는 떼고
-- 시작해 끝난 뒤 다시 만드는 편이 빠르다(`docs/backfill-workflow.md` 5절).
--
--
-- ============================================================================
-- 6. 다른 방법 — 쓰기도 막지 않으려면 CONCURRENTLY (권장 아님: 지금은 1절이 낫다)
-- ============================================================================
--
-- 수집이 도는 시간대(06:00~08:00)에 꼭 해야 하거나 쓰기를 1초도 막을 수 없을 때만 쓴다.
--
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_apt_trade_complex
--       ON estate.apt_trade (sgg_cd, apt_seq, deal_year DESC, deal_month DESC);
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_apt_rent_complex
--       ON estate.apt_rent (sgg_cd, apt_seq, deal_year DESC, deal_month DESC);
--
-- 함정 — DB 툴에서 그냥 실행하면 실패한다 (2026-11-17 실제 발생)
--
--   SQL Error [25001]: ERROR: CREATE INDEX CONCURRENTLY cannot run inside a
--                             transaction block
--
-- 툴이 기본으로 **수동 커밋**이라 문장을 트랜잭션으로 감싸기 때문이다. 스크립트가 틀린 것이
-- 아니라 **실행 모드**가 문제다. 넷 중 하나로 푼다.
--
--   ① DBeaver — 툴바의 커밋 모드를 **Auto-Commit** 으로 바꾼 뒤 문장 하나만 실행(Ctrl+Enter).
--      여러 문장을 묶어 보내는 "Execute script"(Alt+X)는 쓰지 말 것.
--   ② DataGrip — 툴바의 Tx 모드를 **Auto** 로 바꾼 뒤 문장 하나만 실행.
--   ③ pgAdmin — 쿼리 도구가 기본 auto-commit 이라 그대로 된다.
--   ④ psql — 기본이 auto-commit 이다(`-c` 한 줄에 하나씩, BEGIN 금지).
--      작업 PC 에 psql 이 없으면 **DB 파드 안의 psql** 을 쓴다 — `docs/k8s-runbook.md` 5-1 절.
--
-- 끊기면 못 쓰는 인덱스가 남는다. 그때는 지우고 다시 만든다.
--
--   SELECT c.relname AS 인덱스, i.indisvalid AS 사용가능
--     FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
--    WHERE c.relname IN ('ix_apt_trade_complex', 'ix_apt_rent_complex');
--   -- DROP INDEX CONCURRENTLY IF EXISTS estate.ix_apt_rent_complex;
