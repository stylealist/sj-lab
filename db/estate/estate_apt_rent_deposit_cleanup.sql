-- ============================================================================
-- estate.apt_rent — 보증금이 빈 "쌍둥이 행" 정리
--
--   대상 DB   : sjlab  (개발 = 운영 동일 인스턴스)
--   실행 계정 : stylealist (estate.apt_rent 소유자 — DELETE 권한 필요)
--   작성      : 2026-11-12
--   성격      : **DML(DELETE)**. 에이전트가 실행하지 않는다. 담당자가 아래 순서대로 실행한다.
--
-- ----------------------------------------------------------------------------
-- 왜 필요한가 (원인)
-- ----------------------------------------------------------------------------
-- 수집기가 금액을 숫자로 바꿀 때 **천 단위 쉼표를 떼지 않아** 1,000만원 이상 보증금이
-- 모두 조용히 null 이 됐다. 원천은 `"48,000"` 처럼 쉼표를 넣어 준다.
--   → 과거 데이터에서 보증금이 들어간 행은 예외 없이 **999 이하**다(실측: 2015·2020·2024·2025년
--     최댓값 전부 999). 쉼표가 없는 값만 변환에 성공한 것이다.
--   → 전체 11,889,562 행 중 보증금이 빈 행 **11,044,773 행(93%)**.
-- 쉼표를 떼는 처리는 `DataTypeUtil.numeric()` 에 들어가 고쳐졌다(2026-10-12). 2026-10 수집분은
-- 보증금 97.8% · 11월분은 100% 로 정상이다. 그래서 **다시 받으면 과거도 채워진다**
-- (원천 확인: 2015-06 · 2020-06 · 2024-06 · 2025-12 모두 보증금 정상 응답).
--
-- ----------------------------------------------------------------------------
-- 왜 재수집만으로는 끝나지 않는가 (이 스크립트의 존재 이유)
-- ----------------------------------------------------------------------------
-- 중복 방지 유니크 인덱스 `ux_apt_rent_natural` 의 키에 **deposit 이 들어 있다.**
-- 같은 계약이
--     ① 보증금 null 로 한 번 (버그 시절)
--     ② 보증금 48000 으로 한 번 (고친 뒤 재수집)
-- 들어오면 **서로 다른 키**라서 `ON CONFLICT DO NOTHING` 이 막지 못하고 두 행이 공존한다.
-- 그 결과 **화면의 전월세 거래 건수가 실제보다 많게 보인다.**
--
-- 그래서 순서가 중요하다.
--
--     ❶ 먼저 재수집한다(없어지는 것이 없다. 쌍둥이만 늘어난다)
--     ❷ 그 다음에 이 스크립트로 "보증금이 빈 쪽"만 지운다
--
-- **지우기를 먼저 하지 말 것.** 재수집이 실패하면 데이터가 비어 버린다. 이 순서면 지우는 시점에
-- 이미 대체 행이 손에 있으므로 잃는 것이 없다.
--
-- ----------------------------------------------------------------------------
-- 무엇을 지우는가
-- ----------------------------------------------------------------------------
-- 자연키에서 **금액(deposit)만 뺀 나머지가 똑같은 행 묶음** 안에서,
--   · 보증금이 들어간 행이 하나라도 있고
--   · 보증금이 빈 행이 있으면
-- 그 **빈 행만** 지운다. 짝이 없는 빈 행(= 아직 재수집 안 된 기간)은 **건드리지 않는다**
-- — 금액은 없어도 "그 달에 거래가 있었다"는 사실은 맞기 때문이다.
--
-- 묶음 기준(= 유니크 인덱스의 키에서 deposit 만 뺀 것):
--   sgg_cd, umd_nm, jibun, apt_nm, exclu_use_ar, floor,
--   deal_year, deal_month, deal_day, monthly_rent, contract_term, contract_type
--
-- 빈 행은 한 묶음에 최대 1개다(유니크 인덱스가 `NULLS NOT DISTINCT` 라 같은 null 행이 둘일 수 없다).
-- 실측으로도 2026년 쌍둥이 묶음 198,638개 = 지울 행 198,638개로 1:1 이었다.
--
-- ----------------------------------------------------------------------------
-- 되돌리기
-- ----------------------------------------------------------------------------
-- DELETE 는 되돌릴 수 없다. 다만 **지우는 행은 금액이 빈 쌍둥이뿐이고, 같은 계약의 온전한 행이
-- 바로 옆에 남는다.** 그래도 불안하면 ❶ 번 블록(측정)으로 건수를 먼저 확인하고,
-- `BEGIN; ... ROLLBACK;` 으로 한 달만 시험해 본 뒤 `COMMIT` 할 것.
-- ============================================================================


-- ============================================================================
-- ❶ 실행 전 측정 — 얼마나 지워지는지 먼저 본다 (SELECT 만, 안전)
-- ============================================================================
-- 연도별 요약. `dup_rows` 가 이 스크립트로 지워질 행이고,
-- `null_only_rows` 는 아직 재수집이 안 된(= 짝이 없는) 빈 행이다.
WITH g AS (
    SELECT deal_year,
           count(*) FILTER (WHERE deposit IS NULL)     AS n_null,
           count(*) FILTER (WHERE deposit IS NOT NULL) AS n_real
    FROM estate.apt_rent
    GROUP BY sgg_cd, umd_nm, jibun, apt_nm, exclu_use_ar, floor,
             deal_year, deal_month, deal_day, monthly_rent, contract_term, contract_type
)
SELECT deal_year,
       coalesce(sum(n_null) FILTER (WHERE n_null > 0 AND n_real > 0), 0)  AS dup_rows,
       coalesce(sum(n_null) FILTER (WHERE n_null > 0 AND n_real = 0), 0)  AS null_only_rows
FROM g
GROUP BY deal_year
ORDER BY deal_year;


-- ============================================================================
-- ❷ 정리 — 한 달씩 (권장)
-- ============================================================================
-- 한 번에 전체를 지우면 잠금과 WAL 이 크다. **재수집한 달마다 바로 한 번씩** 돌리는 쪽이 좋다.
-- 아래 두 숫자만 바꿔 쓴다.
DELETE FROM estate.apt_rent
WHERE id IN (
    SELECT id
    FROM (
        SELECT id, deposit,
               count(deposit) OVER (
                   PARTITION BY sgg_cd, umd_nm, jibun, apt_nm, exclu_use_ar, floor,
                                deal_year, deal_month, deal_day,
                                monthly_rent, contract_term, contract_type
               ) AS real_cnt
        FROM estate.apt_rent
        WHERE deal_year  = 2026     -- ← 바꿀 값
          AND deal_month = 1        -- ← 바꿀 값
    ) x
    WHERE x.deposit IS NULL
      AND x.real_cnt > 0
);


-- ============================================================================
-- ❸ 정리 — 한 해씩
-- ============================================================================
-- 월 단위가 번거로울 때. 한 해(약 100만 행)를 한 번에 훑는다.
DELETE FROM estate.apt_rent
WHERE id IN (
    SELECT id
    FROM (
        SELECT id, deposit,
               count(deposit) OVER (
                   PARTITION BY sgg_cd, umd_nm, jibun, apt_nm, exclu_use_ar, floor,
                                deal_year, deal_month, deal_day,
                                monthly_rent, contract_term, contract_type
               ) AS real_cnt
        FROM estate.apt_rent
        WHERE deal_year = 2026      -- ← 바꿀 값
    ) x
    WHERE x.deposit IS NULL
      AND x.real_cnt > 0
);


-- ============================================================================
-- ❹ 정리 — 전체 (한 번에 끝내고 싶을 때만)
-- ============================================================================
-- 11,889,562 행을 한 번에 묶으므로 메모리·시간이 많이 든다. 되도록 ❷·❸ 를 쓸 것.
-- 돌릴 때는 작업 메모리를 올려 두면 빠르다(세션 한정, 서버 설정을 바꾸지 않는다).
--   SET work_mem = '512MB';
--
-- DELETE FROM estate.apt_rent
-- WHERE id IN (
--     SELECT id
--     FROM (
--         SELECT id, deposit,
--                count(deposit) OVER (
--                    PARTITION BY sgg_cd, umd_nm, jibun, apt_nm, exclu_use_ar, floor,
--                                 deal_year, deal_month, deal_day,
--                                 monthly_rent, contract_term, contract_type
--                ) AS real_cnt
--         FROM estate.apt_rent
--     ) x
--     WHERE x.deposit IS NULL
--       AND x.real_cnt > 0
-- );


-- ============================================================================
-- ❺ 실행 후 확인
-- ============================================================================
-- (1) 보증금 채워진 비율 — 재수집한 기간이 100% 에 가까워야 한다
SELECT deal_year,
       count(*)                                   AS rows_total,
       count(deposit)                             AS deposit_ok,
       round(100.0 * count(deposit) / count(*), 1) AS pct
FROM estate.apt_rent
GROUP BY deal_year
ORDER BY deal_year;

-- (2) 쌍둥이가 남았는지 — 정리한 기간은 0 이어야 한다
WITH g AS (
    SELECT deal_year,
           count(*) FILTER (WHERE deposit IS NULL)     AS n_null,
           count(*) FILTER (WHERE deposit IS NOT NULL) AS n_real
    FROM estate.apt_rent
    GROUP BY sgg_cd, umd_nm, jibun, apt_nm, exclu_use_ar, floor,
             deal_year, deal_month, deal_day, monthly_rent, contract_term, contract_type
)
SELECT deal_year, coalesce(sum(n_null) FILTER (WHERE n_null > 0 AND n_real > 0), 0) AS dup_rows_left
FROM g
GROUP BY deal_year
ORDER BY deal_year;

-- (3) 통계 갱신 — 대량 삭제 뒤에는 돌려 둘 것(조회 계획이 어긋나지 않게)
-- ANALYZE estate.apt_rent;

-- (4) 월별 집계 뷰는 자동으로 맞는다 — `estate.v_apt_rent_monthly` 는 일반 뷰라
--     지운 즉시 반영된다(MATERIALIZED VIEW 로 바꿨다면 REFRESH 할 것).


-- ============================================================================
-- ❻ 다시 생기지 않게 하려면 (지금은 필요 없다)
-- ============================================================================
-- 쌍둥이는 "보증금이 빈 행" 때문에 생겼고, 그 원인은 고쳐졌다. 정리 후에는 새로 생기지 않는다.
-- 다만 원천이 또 금액 형식을 바꾸면 같은 일이 반복될 수 있다. 그때를 막는 방법은 두 가지인데
-- **지금 적용하지 않는다** — 이유를 함께 적어 둔다.
--
--   (가) 유니크 키에서 deposit 을 뺀다 → 재수집이 `DO UPDATE` 로 금액만 고칠 수 있다.
--        **위험하다.** 전월세 표에는 `apt_dong`(동) 컬럼이 없어, 같은 날 · 같은 층 · 같은 면적 ·
--        같은 계약기간의 **다른 동 계약 두 건이 한 행으로 합쳐질 수 있다.** 큰 단지에서는 실제로
--        일어날 수 있는 조합이다.
--   (나) 수집기가 금액 변환에 실패한 행을 **적재하지 않고 경고를 남긴다**.
--        건수까지 사라지므로 "거래가 없는 달"로 보이게 된다 — 지금 방식(빈 금액이라도 넣기)이
--        화면에는 덜 해롭다.
--
-- 결론: 키는 그대로 두고, **금액 변환 실패율을 수집 로그로 감시**하는 쪽이 맞다.
