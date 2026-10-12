-- ============================================================================
-- estate 스키마 — 아파트 실거래가(매매) · 전월세 (2026-10-06)
--
-- 왜 새 스키마인가
--   아파트 데이터는 전에 `ai` 스키마에 있었다. `ai` 는 앞으로 AI/RAG 관련 표만 두기로 했으므로
--   (2026-10-06 결정) 부동산 원천 데이터는 `estate` 로 분리한다.
--
-- 적재 주체: sj-lab-scheduler (공공데이터포털 국토교통부 실거래가 API)
--   매매   RTMSDataSvcAptTradeDev/getRTMSDataSvcAptTradeDev  — 매일 06:00
--   전월세 RTMSDataSvcAptRent/getRTMSDataSvcAptRent          — 매일 07:00
--   백필   POST/GET /scheduler/apis/housing/aptTrades?from=202601&to=202610 (수동)
--
-- 읽기 주체: fast-api-ai (부동산 분석 화면이 호출)
--
-- 실행은 에이전트가 하지 않는다(프로젝트 규칙). DB 권한이 있는 담당자가 돌린다.
-- 재실행해도 안전하다(IF NOT EXISTS / OR REPLACE).
--
-- 이 스크립트를 실행하기 전에는 수집·화면이 모두 동작하지 않는다(표가 없으므로).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS estate;

COMMENT ON SCHEMA estate IS '부동산 실거래 데이터(아파트 매매·전월세). 적재 sj-lab-scheduler, 조회 fast-api-ai';

-- ----------------------------------------------------------------------------
-- 1) 아파트 매매 실거래
--    컬럼은 종전 ai.apt_trades 와 같다(수집 코드를 그대로 쓰기 위해).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS estate.apt_trade (
    id                  bigserial PRIMARY KEY,

    -- 지역
    sgg_cd              varchar(10),        -- 법정동시군구코드(LAWD_CD)
    umd_cd              varchar(10),
    land_cd             varchar(10),
    bonbun              varchar(10),
    bubun               varchar(10),
    jibun               varchar(50),
    umd_nm              varchar(100),

    -- 도로명
    road_nm             varchar(200),
    road_nm_sgg_cd      varchar(10),
    road_nm_cd          varchar(20),
    road_nm_seq         varchar(10),
    road_nmb_cd         varchar(10),
    road_nm_bonbun      varchar(10),
    road_nm_bubun       varchar(10),

    -- 단지
    apt_nm              varchar(200),
    apt_dong            varchar(100),
    apt_seq             varchar(50),
    build_year          integer,
    exclu_use_ar        numeric(10,4),      -- 전용면적(㎡)
    floor               integer,

    -- 거래
    deal_year           integer,
    deal_month          integer,
    deal_day            integer,
    deal_amount         bigint,             -- 거래금액(만원)
    dealing_gbn         varchar(20),        -- 거래유형(중개/직거래)
    cdeal_type          varchar(10),        -- 해제여부
    cdeal_day           varchar(20),        -- 해제사유발생일
    estate_agent_sgg_nm varchar(100),       -- 중개사 소재지
    sler_gbn            varchar(50),        -- 매도자 구분
    buyer_gbn           varchar(50),        -- 매수자 구분
    rgst_date           varchar(20),        -- 등기일자
    land_leasehold_gbn  varchar(20),        -- 토지임대부 여부

    created_at          timestamp DEFAULT now()
);

COMMENT ON TABLE estate.apt_trade IS '아파트 매매 실거래가(국토교통부 공개데이터). 금액 단위는 만원';

-- ----------------------------------------------------------------------------
-- 2) 아파트 전월세
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS estate.apt_rent (
    id                  bigserial PRIMARY KEY,

    sgg_cd              varchar(10),
    umd_nm              varchar(100),
    jibun               varchar(50),

    apt_nm              varchar(200),
    apt_seq             varchar(50),
    build_year          integer,
    exclu_use_ar        numeric(10,4),
    floor               integer,

    deal_year           integer,
    deal_month          integer,
    deal_day            integer,

    deposit             bigint,             -- 보증금(만원)
    monthly_rent        bigint,             -- 월세(만원). 0 이면 전세
    contract_term       varchar(50),        -- 계약기간
    contract_type       varchar(20),        -- 신규/갱신
    use_rr_right        varchar(20),        -- 갱신요구권 사용
    pre_deposit         bigint,             -- 종전 보증금
    pre_monthly_rent    bigint,             -- 종전 월세

    road_nm             varchar(200),
    road_nm_sgg_cd      varchar(10),
    road_nm_cd          varchar(20),
    road_nm_seq         varchar(10),
    road_nmb_cd         varchar(10),
    road_nm_bonbun      varchar(10),
    road_nm_bubun       varchar(10),

    created_at          timestamp DEFAULT now()
);

COMMENT ON TABLE estate.apt_rent IS '아파트 전월세 실거래(국토교통부 공개데이터). monthly_rent = 0 이면 전세';

-- ----------------------------------------------------------------------------
-- 2-1) 컬럼 주석
--      원천 API 의 응답 필드명이 영문 약어라 컬럼만 보면 뜻을 알 수 없다.
--      화면·분석 쿼리를 쓰는 사람이 DB 도구에서 바로 읽을 수 있게 전 컬럼에 남긴다.
--      COMMENT 는 몇 번 실행해도 덮어쓰기만 하므로 재실행이 안전하다.
-- ----------------------------------------------------------------------------

-- 아파트 매매
COMMENT ON COLUMN estate.apt_trade.id                  IS '자동 증가 PK';
COMMENT ON COLUMN estate.apt_trade.sgg_cd              IS '법정동 시군구 코드 5자리(원천 LAWD_CD). 지역 필터의 기준 컬럼';
COMMENT ON COLUMN estate.apt_trade.umd_cd              IS '법정동 읍면동 코드';
COMMENT ON COLUMN estate.apt_trade.land_cd             IS '법정동 지번 코드(대지·산 구분)';
COMMENT ON COLUMN estate.apt_trade.bonbun              IS '지번 본번';
COMMENT ON COLUMN estate.apt_trade.bubun               IS '지번 부번';
COMMENT ON COLUMN estate.apt_trade.jibun               IS '지번(본번-부번 형태의 표시용 값)';
COMMENT ON COLUMN estate.apt_trade.umd_nm              IS '법정동명(예: 역삼동)';
COMMENT ON COLUMN estate.apt_trade.road_nm             IS '도로명';
COMMENT ON COLUMN estate.apt_trade.road_nm_sgg_cd      IS '도로명 시군구 코드';
COMMENT ON COLUMN estate.apt_trade.road_nm_cd          IS '도로명 코드';
COMMENT ON COLUMN estate.apt_trade.road_nm_seq         IS '도로명 일련번호 코드';
COMMENT ON COLUMN estate.apt_trade.road_nmb_cd         IS '도로명 지상·지하 코드';
COMMENT ON COLUMN estate.apt_trade.road_nm_bonbun      IS '도로명 건물 본번호';
COMMENT ON COLUMN estate.apt_trade.road_nm_bubun       IS '도로명 건물 부번호';
COMMENT ON COLUMN estate.apt_trade.apt_nm              IS '아파트 단지명';
COMMENT ON COLUMN estate.apt_trade.apt_dong            IS '동(棟). 공개되지 않는 거래는 비어 있다';
COMMENT ON COLUMN estate.apt_trade.apt_seq             IS '단지 일련번호(원천이 부여한 단지 식별값)';
COMMENT ON COLUMN estate.apt_trade.build_year          IS '건축연도(준공 연도)';
COMMENT ON COLUMN estate.apt_trade.exclu_use_ar        IS '전용면적(㎡). 평으로 보려면 3.3058 로 나눈다';
COMMENT ON COLUMN estate.apt_trade.floor               IS '층. 지하는 음수로 올 수 있다';
COMMENT ON COLUMN estate.apt_trade.deal_year           IS '계약 연도';
COMMENT ON COLUMN estate.apt_trade.deal_month          IS '계약 월(1~12)';
COMMENT ON COLUMN estate.apt_trade.deal_day            IS '계약 일';
COMMENT ON COLUMN estate.apt_trade.deal_amount         IS '거래금액. 단위는 만원(예: 85000 = 8억 5천만원)';
COMMENT ON COLUMN estate.apt_trade.dealing_gbn         IS '거래유형(중개거래 / 직거래)';
COMMENT ON COLUMN estate.apt_trade.cdeal_type          IS '해제 여부. O 면 계약이 해제된 거래이므로 집계에서 빼는 것을 검토할 것';
COMMENT ON COLUMN estate.apt_trade.cdeal_day           IS '해제사유 발생일';
COMMENT ON COLUMN estate.apt_trade.estate_agent_sgg_nm IS '중개사 소재지(시군구). 중개업소 상호가 아니라 지역명이다';
COMMENT ON COLUMN estate.apt_trade.sler_gbn            IS '매도자 구분(개인 / 법인 / 공공기관 / 기타)';
COMMENT ON COLUMN estate.apt_trade.buyer_gbn           IS '매수자 구분(개인 / 법인 / 공공기관 / 기타)';
COMMENT ON COLUMN estate.apt_trade.rgst_date           IS '등기일자';
COMMENT ON COLUMN estate.apt_trade.land_leasehold_gbn  IS '토지임대부 아파트 여부';
COMMENT ON COLUMN estate.apt_trade.created_at          IS '이 행을 적재한 일시(거래일이 아니다)';

-- 아파트 전월세
COMMENT ON COLUMN estate.apt_rent.id                   IS '자동 증가 PK';
COMMENT ON COLUMN estate.apt_rent.sgg_cd               IS '법정동 시군구 코드 5자리(원천 LAWD_CD). 지역 필터의 기준 컬럼';
COMMENT ON COLUMN estate.apt_rent.umd_nm               IS '법정동명';
COMMENT ON COLUMN estate.apt_rent.jibun                IS '지번';
COMMENT ON COLUMN estate.apt_rent.apt_nm               IS '아파트 단지명';
COMMENT ON COLUMN estate.apt_rent.apt_seq              IS '단지 일련번호';
COMMENT ON COLUMN estate.apt_rent.build_year           IS '건축연도';
COMMENT ON COLUMN estate.apt_rent.exclu_use_ar         IS '전용면적(㎡)';
COMMENT ON COLUMN estate.apt_rent.floor                IS '층';
COMMENT ON COLUMN estate.apt_rent.deal_year            IS '계약 연도';
COMMENT ON COLUMN estate.apt_rent.deal_month           IS '계약 월(1~12)';
COMMENT ON COLUMN estate.apt_rent.deal_day             IS '계약 일';
COMMENT ON COLUMN estate.apt_rent.deposit              IS '보증금. 단위는 만원. 전세면 전세금, 월세면 보증금';
COMMENT ON COLUMN estate.apt_rent.monthly_rent         IS '월세. 단위는 만원. 0 이면 전세다 — 전세·월세를 가르는 기준 컬럼';
COMMENT ON COLUMN estate.apt_rent.contract_term        IS '계약기간(예: 24.03~26.03)';
COMMENT ON COLUMN estate.apt_rent.contract_type        IS '계약구분(신규 / 갱신)';
COMMENT ON COLUMN estate.apt_rent.use_rr_right         IS '계약갱신요구권 사용 여부';
COMMENT ON COLUMN estate.apt_rent.pre_deposit          IS '종전 계약의 보증금(만원). 갱신 계약일 때만 값이 있다';
COMMENT ON COLUMN estate.apt_rent.pre_monthly_rent     IS '종전 계약의 월세(만원). 갱신 계약일 때만 값이 있다';
COMMENT ON COLUMN estate.apt_rent.road_nm              IS '도로명';
COMMENT ON COLUMN estate.apt_rent.road_nm_sgg_cd       IS '도로명 시군구 코드';
COMMENT ON COLUMN estate.apt_rent.road_nm_cd           IS '도로명 코드';
COMMENT ON COLUMN estate.apt_rent.road_nm_seq          IS '도로명 일련번호 코드';
COMMENT ON COLUMN estate.apt_rent.road_nmb_cd          IS '도로명 지상·지하 코드';
COMMENT ON COLUMN estate.apt_rent.road_nm_bonbun       IS '도로명 건물 본번호';
COMMENT ON COLUMN estate.apt_rent.road_nm_bubun        IS '도로명 건물 부번호';
COMMENT ON COLUMN estate.apt_rent.created_at           IS '이 행을 적재한 일시(계약일이 아니다)';

-- ----------------------------------------------------------------------------
-- 3) 중복 방지 — 이게 핵심이다
--
-- 종전 ai.apt_trades 는 유니크 키가 없고 수집 코드도 ON CONFLICT 없이 INSERT 해서,
-- 매일 "이번 달 + 지난 달"을 다시 넣으며 중복이 쌓였다(2025-11 매매 실측 2.6% 중복).
-- 같은 거래를 두 번 넣지 못하게 자연키에 유니크 인덱스를 둔다.
--
-- NULLS NOT DISTINCT 가 꼭 필요하다(PostgreSQL 15+). 기본값(NULLS DISTINCT)이면
-- 비어 있는 컬럼이 하나라도 있는 행은 중복으로 보지 않아 그대로 또 들어간다.
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS ux_apt_trade_natural
    ON estate.apt_trade (
        sgg_cd, umd_nm, jibun, apt_nm, apt_dong,
        exclu_use_ar, floor,
        deal_year, deal_month, deal_day, deal_amount
    ) NULLS NOT DISTINCT;

CREATE UNIQUE INDEX IF NOT EXISTS ux_apt_rent_natural
    ON estate.apt_rent (
        sgg_cd, umd_nm, jibun, apt_nm,
        exclu_use_ar, floor,
        deal_year, deal_month, deal_day,
        deposit, monthly_rent, contract_term, contract_type
    ) NULLS NOT DISTINCT;

-- ----------------------------------------------------------------------------
-- 4) 조회용 인덱스 (화면이 쓰는 필터 순서에 맞춤)
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_apt_trade_region_period
    ON estate.apt_trade (sgg_cd, deal_year, deal_month);
CREATE INDEX IF NOT EXISTS ix_apt_trade_period
    ON estate.apt_trade (deal_year, deal_month);
CREATE INDEX IF NOT EXISTS ix_apt_trade_apt_nm
    ON estate.apt_trade (apt_nm);

CREATE INDEX IF NOT EXISTS ix_apt_rent_region_period
    ON estate.apt_rent (sgg_cd, deal_year, deal_month);
CREATE INDEX IF NOT EXISTS ix_apt_rent_period
    ON estate.apt_rent (deal_year, deal_month);
CREATE INDEX IF NOT EXISTS ix_apt_rent_apt_nm
    ON estate.apt_rent (apt_nm);

-- ----------------------------------------------------------------------------
-- 5) 월·지역 집계 뷰 — 화면의 추세 차트가 이걸 쓴다.
--    원본을 매번 전건 집계하면 느려지므로, 데이터가 커지면 MATERIALIZED VIEW 로 바꾸고
--    수집 직후 REFRESH 하도록 scheduler 에 한 줄 추가할 것.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW estate.v_apt_trade_monthly AS
SELECT
    sgg_cd,
    deal_year,
    deal_month,
    count(*)                                          AS deal_count,
    round(avg(deal_amount))                           AS avg_amount,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY deal_amount) AS median_amount,
    min(deal_amount)                                  AS min_amount,
    max(deal_amount)                                  AS max_amount,
    round(avg(exclu_use_ar), 2)                       AS avg_area,
    round(avg(deal_amount / NULLIF(exclu_use_ar, 0)), 1) AS avg_amount_per_m2
FROM estate.apt_trade
WHERE deal_amount IS NOT NULL
GROUP BY sgg_cd, deal_year, deal_month;

COMMENT ON VIEW estate.v_apt_trade_monthly IS '아파트 매매 월·시군구 집계(건수·평균·중위·㎡당). 금액 단위 만원';

CREATE OR REPLACE VIEW estate.v_apt_rent_monthly AS
SELECT
    sgg_cd,
    deal_year,
    deal_month,
    count(*)                                               AS deal_count,
    count(*) FILTER (WHERE COALESCE(monthly_rent, 0) = 0)  AS jeonse_count,
    count(*) FILTER (WHERE COALESCE(monthly_rent, 0) > 0)  AS wolse_count,
    round(avg(deposit) FILTER (WHERE COALESCE(monthly_rent, 0) = 0)) AS avg_jeonse_deposit,
    round(avg(deposit) FILTER (WHERE COALESCE(monthly_rent, 0) > 0)) AS avg_wolse_deposit,
    round(avg(monthly_rent) FILTER (WHERE COALESCE(monthly_rent, 0) > 0)) AS avg_monthly_rent,
    round(avg(exclu_use_ar), 2)                            AS avg_area
FROM estate.apt_rent
GROUP BY sgg_cd, deal_year, deal_month;

COMMENT ON VIEW estate.v_apt_rent_monthly IS '아파트 전월세 월·시군구 집계. monthly_rent=0 을 전세로 센다';

-- ----------------------------------------------------------------------------
-- 6) 권한
--    계정 이름은 환경에 맞춰 바꿀 것. 지금 scheduler 는 개인 계정(superuser)으로 붙고 있어
--    권장은 openapi_svc 처럼 전용 최소권한 계정을 따로 만드는 것이다(sj-lab/docs/k8s-secrets.md).
-- ----------------------------------------------------------------------------
-- 적재(scheduler)용 — 전용 계정을 만들었다면 그 이름으로 바꿀 것
-- GRANT USAGE ON SCHEMA estate TO estate_svc;
-- GRANT SELECT, INSERT, UPDATE ON estate.apt_trade, estate.apt_rent TO estate_svc;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA estate TO estate_svc;

-- 조회(fast-api-ai)용 — 읽기만
-- GRANT USAGE ON SCHEMA estate TO estate_read;
-- GRANT SELECT ON ALL TABLES IN SCHEMA estate TO estate_read;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA estate GRANT SELECT ON TABLES TO estate_read;
