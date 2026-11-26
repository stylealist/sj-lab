-- ============================================================================
-- 관심 단지 "목표가 알림" — member.estate_favorite 에 컬럼 6개 추가
--
--   대상 DB : sjlab  (개발 = 운영 같은 인스턴스)
--   실행    : DB 담당자. 에이전트는 실행하지 않는다.
--   쓰는 곳 : sj-lab-estate 의 /estate/member/favorites/**
--   선행    : db/estate/estate_member.sql (표 3개) — 그게 없으면 이 스크립트도 의미가 없다
--   상태    : 미실행 (2026-11-25 작성)
--
-- ── 무엇을 하는 기능인가 ────────────────────────────────────────────────────
-- 관심 단지마다 **"얼마가 되면 알려 줘"** 를 적어 두고, 그 뒤에 올라온 거래 중 조건을
-- 만족하는 것이 있으면 화면에 배지로 알린다.
--
--     래미안○○ · 34평 · 매매 15억 이하   →   🔔 14.9억 거래 (2026-11-20)
--
-- **밀어 주는 알림(푸시·메일)이 아니다.** 화면에 들어왔을 때 보여 준다 — 이미 있는
-- "새 거래 N건" 배지와 **같은 방식**이고, 그래서 보낼 통로(메일 서버·푸시 키)가 필요 없다.
--
-- ── 왜 새 표가 아니라 컬럼인가 ──────────────────────────────────────────────
-- 목표가는 **관심 단지 하나에 하나**다. 별도 표로 두면 (username, apt_seq) 로 1:1 조인이
-- 하나 더 붙을 뿐이고, 관심을 빼면 같이 지워야 하는 것도 그대로다. 관심 단지의 속성으로
-- 보는 쪽이 맞다 — `seen_deal_ymd`(새 거래 기준점)를 여기 둔 것과 같은 이유다.
--
-- ── 실행하지 않으면 ─────────────────────────────────────────────────────────
-- **오류가 아니라 이 기능만 꺼진다.** 서비스가 컬럼 유무를 확인해서 없으면
-- `GET /estate/member/status` 가 `target_ready:false` 로 답하고, 화면은 목표가 단추를
-- 숨긴다. 관심 담기·메모·지도는 전혀 영향이 없다. 60초마다 다시 확인하므로 이 스크립트를
-- 실행하면 **재기동 없이** 켜진다.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) 컬럼 추가
-- ----------------------------------------------------------------------------
-- 모두 nullable 이고 기본값이 있어 **기존 행을 건드리지 않는다**(목표가를 정하지 않은
-- 관심 단지는 `target_amount IS NULL` 이고 알림도 없다). 990만 행짜리 실거래 표가 아니라
-- 사람이 담은 수십 행짜리 표라 ALTER 가 즉시 끝난다.
ALTER TABLE member.estate_favorite
    ADD COLUMN IF NOT EXISTS target_amount   integer,
    ADD COLUMN IF NOT EXISTS target_kind     varchar(10),
    ADD COLUMN IF NOT EXISTS target_dir      varchar(5),
    ADD COLUMN IF NOT EXISTS target_pyeong   integer,
    ADD COLUMN IF NOT EXISTS target_base_ymd integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS target_at       timestamp;

COMMENT ON COLUMN member.estate_favorite.target_amount IS
    '목표 금액(만원). NULL 이면 목표가를 정하지 않은 것이고 알림도 없다';
COMMENT ON COLUMN member.estate_favorite.target_kind IS
    '무엇의 값인가 — trade(매매가) | jeonse(전세 보증금). 전세는 monthly_rent = 0 인 거래만 본다';
COMMENT ON COLUMN member.estate_favorite.target_dir IS
    '어느 쪽일 때 알리나 — below(이하로 내려오면, 사는 쪽) | above(이상이면, 파는 쪽)';
COMMENT ON COLUMN member.estate_favorite.target_pyeong IS
    '평형(분양 평형, round(전용㎡/3.3058/0.75)). NULL 이면 단지의 모든 평형을 본다';
COMMENT ON COLUMN member.estate_favorite.target_base_ymd IS
    '목표가를 정한 시점의 최근 계약일(YYYYMMDD). 이보다 뒤의 거래만 알림 대상이다';
COMMENT ON COLUMN member.estate_favorite.target_at IS '목표가를 정하거나 고친 시각';

-- ----------------------------------------------------------------------------
-- 2) 값 검사
-- ----------------------------------------------------------------------------
-- 서비스도 같은 값만 받지만, DB 에도 둬서 **다른 경로로 들어온 값이 화면을 깨지 않게** 한다
-- (`target_kind` 가 엉뚱하면 알림이 조용히 영영 안 뜬다 — 오류보다 찾기 어렵다).
-- 세 컬럼 모두 NULL 을 허용하므로 목표가를 정하지 않은 기존 행은 그대로 통과한다.
ALTER TABLE member.estate_favorite
    DROP CONSTRAINT IF EXISTS ck_estate_favorite_target;

ALTER TABLE member.estate_favorite
    ADD CONSTRAINT ck_estate_favorite_target CHECK (
        (target_kind   IS NULL OR target_kind IN ('trade', 'jeonse'))
    AND (target_dir    IS NULL OR target_dir  IN ('below', 'above'))
    AND (target_amount IS NULL OR target_amount > 0)
    AND (target_pyeong IS NULL OR target_pyeong > 0)
    );

-- ----------------------------------------------------------------------------
-- 3) 권한
-- ----------------------------------------------------------------------------
-- 표 단위 권한이라 컬럼이 늘어도 따라온다(estate_member.sql 의 GRANT 가 그대로 유효).
-- 확인만 해 두면 된다:
--
--   SELECT privilege_type FROM information_schema.table_privileges
--    WHERE table_schema = 'member' AND table_name = 'estate_favorite'
--      AND grantee = 'openapi_svc';

-- ----------------------------------------------------------------------------
-- 4) 확인
-- ----------------------------------------------------------------------------
--   SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_schema = 'member' AND table_name = 'estate_favorite'
--      AND column_name LIKE 'target%' ORDER BY ordinal_position;
--
--   -- 서비스가 보는 상태(로컬) — target_ready 가 true 가 되면 끝이다
--   -- curl http://localhost:8100/estate/member/status

-- ----------------------------------------------------------------------------
-- 5) 되돌리기
-- ----------------------------------------------------------------------------
-- 목표가만 사라지고 관심 단지 자체는 남는다.
--
--   ALTER TABLE member.estate_favorite DROP CONSTRAINT IF EXISTS ck_estate_favorite_target;
--   ALTER TABLE member.estate_favorite
--       DROP COLUMN IF EXISTS target_amount,
--       DROP COLUMN IF EXISTS target_kind,
--       DROP COLUMN IF EXISTS target_dir,
--       DROP COLUMN IF EXISTS target_pyeong,
--       DROP COLUMN IF EXISTS target_base_ymd,
--       DROP COLUMN IF EXISTS target_at;
