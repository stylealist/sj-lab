-- ============================================================================
-- estate.apt_complex — 아파트 단지 마스터 (지도용 좌표를 담는 표)
--
-- 왜 필요한가
--   국토교통부 실거래 공개 API 는 **좌표를 주지 않는다**. 지도에 핀을 찍으려면 주소를 좌표로
--   바꿔(지오코딩) 어딘가에 저장해야 한다. 거래는 2,100만 건이지만 **단지는 44,581개**이고
--   (매매 41,512 + 전월세 전용 3,069), 단지마다 한 번만 구하면 `apt_seq` 로 모든 거래에 붙는다.
--   그래서 거래 표에 좌표 컬럼을 더하지 않고 **단지 표를 따로** 둔다.
--
-- 실행
--   **에이전트가 실행하지 않는다.** DB 권한이 있는 담당자가 psql 로 실행한다.
--   대상 DB: sjlab (개발·운영 같은 인스턴스)
--
-- 실행 전에는?
--   지도 기능만 막힌다. 지금 화면(지역·단지·평형)은 그대로 동작한다.
--
-- 채우는 순서 (자세한 절차는 sj-lab/docs/estate-geocode-workflow.md)
--   1) 이 스크립트로 표를 만든다
--   2) scheduler 의 `/scheduler/estate/complex/sync` 로 거래 표에서 단지를 긁어 넣는다(좌표 없음)
--   3) scheduler 의 `/scheduler/estate/complex/geocode` 로 좌표를 채운다(행안부 → VWorld)
--
-- 2026-10-14 작성.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS estate;

CREATE TABLE IF NOT EXISTS estate.apt_complex (
    -- 단지 키. 실거래 API 가 주는 값이고 앞 5자리가 시군구 코드다(예: 11680-218).
    apt_seq             varchar(20)   PRIMARY KEY,

    -- ── 주소 조각 (거래 표에서 그대로 옮긴다. 지오코딩 입력이 된다) ──────────
    sgg_cd              varchar(5)    NOT NULL,
    umd_cd              varchar(5),          -- 매매에만 있다(전월세 표에는 없음)
    umd_nm              varchar(40),
    land_cd             varchar(1),          -- 지번 구분(산 여부)
    bonbun              varchar(10),
    bubun               varchar(10),
    jibun               varchar(20),
    road_nm             varchar(80),
    road_nm_sgg_cd      varchar(5),
    road_nm_cd          varchar(7),
    road_nmb_cd         varchar(1),          -- 지하 여부(0/1)
    road_nm_bonbun      varchar(10),
    road_nm_bubun       varchar(10),

    apt_nm              varchar(100),
    build_year          integer,

    -- ── 좌표 ────────────────────────────────────────────────────────────────
    -- lon/lat 은 사람이 눈으로 확인하기 쉬우라고 함께 둔다(지도는 geom 을 쓴다).
    lon                 double precision,
    lat                 double precision,
    geom                geometry(Point, 3857),   -- 지도 뷰와 같은 좌표계(다른 레이어와 맞춤)

    -- ── 지오코딩 상태 ───────────────────────────────────────────────────────
    -- PENDING  아직 시도 안 함        OK      좌표를 받음
    -- FAILED   시도했으나 못 받음      SKIPPED 주소 조각이 모자라 시도 자체가 불가
    geocode_status      varchar(10)   NOT NULL DEFAULT 'PENDING',
    geocode_source      varchar(10),         -- JUSO / VWORLD / MANUAL
    geocode_accuracy    varchar(20),         -- 원 API 가 알려 주는 정확도(있으면)
    geocode_tried       integer       NOT NULL DEFAULT 0,
    geocode_error       varchar(200),        -- 마지막 실패 사유(키·본문은 남기지 말 것)
    geocoded_at         timestamp,

    -- ── 참고 ────────────────────────────────────────────────────────────────
    trade_count         integer       NOT NULL DEFAULT 0,
    rent_count          integer       NOT NULL DEFAULT 0,
    reg_date            timestamp     NOT NULL DEFAULT now(),
    update_at           timestamp     NOT NULL DEFAULT now(),

    CONSTRAINT ck_apt_complex_status
        CHECK (geocode_status IN ('PENDING', 'OK', 'FAILED', 'SKIPPED'))
);

-- 지도 조회(화면 영역 안의 단지)용. 좌표가 있는 행만 담아 인덱스를 작게 유지한다.
CREATE INDEX IF NOT EXISTS ix_apt_complex_geom
    ON estate.apt_complex USING gist (geom)
    WHERE geom IS NOT NULL;

-- 지역으로 좁혀 보거나, 수집 배치가 "그 지역부터" 처리할 때 쓴다.
CREATE INDEX IF NOT EXISTS ix_apt_complex_sgg
    ON estate.apt_complex (sgg_cd);

-- 배치가 "아직 안 받은 것"만 빠르게 집는다.
CREATE INDEX IF NOT EXISTS ix_apt_complex_status
    ON estate.apt_complex (geocode_status, sgg_cd);

-- 단지명 검색(지도에서 찾기)
CREATE INDEX IF NOT EXISTS ix_apt_complex_apt_nm
    ON estate.apt_complex (apt_nm);

COMMENT ON TABLE  estate.apt_complex IS '아파트 단지 마스터. 실거래에는 없는 좌표를 지오코딩해 보관한다(apt_seq 로 거래에 붙는다)';
COMMENT ON COLUMN estate.apt_complex.apt_seq          IS '단지 키(실거래 API 제공). 앞 5자리가 시군구 코드';
COMMENT ON COLUMN estate.apt_complex.umd_cd           IS '법정동 코드 뒤 5자리. sgg_cd 와 합치면 10자리 법정동코드(행안부 API 의 admCd)';
COMMENT ON COLUMN estate.apt_complex.road_nm_cd       IS '도로명 코드 7자리. road_nm_sgg_cd 와 합치면 12자리(행안부 API 의 rnMgtSn)';
COMMENT ON COLUMN estate.apt_complex.road_nmb_cd      IS '지하 여부(행안부 API 의 udrtYn). 0=지상 1=지하';
COMMENT ON COLUMN estate.apt_complex.geom             IS '지도용 좌표(EPSG:3857). 원 API 응답이 5179/4326 이면 변환해 넣는다';
COMMENT ON COLUMN estate.apt_complex.geocode_status   IS 'PENDING 미시도 / OK 성공 / FAILED 실패 / SKIPPED 주소 조각 부족';
COMMENT ON COLUMN estate.apt_complex.geocode_source   IS '좌표 출처: JUSO(행안부) / VWORLD / MANUAL';
COMMENT ON COLUMN estate.apt_complex.geocode_error    IS '마지막 실패 사유(짧게). **키·요청 본문을 남기지 말 것**';

-- ----------------------------------------------------------------------------
-- 권한 — 조회 서비스(sj-lab-estate)가 읽고, 수집 배치(scheduler)가 쓴다.
--   조회 계정은 지금 openapi_svc 를 공유한다(db/estate/estate_grant_openapi_svc.sql 참고).
--
--   그 스크립트의 ALTER DEFAULT PRIVILEGES 가 이 표에도 적용되지만, 그것은 **같은 계정이 표를
--   만들 때만** 걸린다(기본 권한은 만든 사람 기준이다). 그래서 아래 한 줄을 그대로 둔다 —
--   이미 적용돼 있으면 아무 일도 일어나지 않는다.
-- ----------------------------------------------------------------------------
GRANT SELECT ON estate.apt_complex TO openapi_svc;

-- 적재 계정(scheduler)이 전용 계정으로 분리돼 있다면:
-- GRANT SELECT, INSERT, UPDATE ON estate.apt_complex TO estate_svc;

-- ----------------------------------------------------------------------------
-- 확인
-- ----------------------------------------------------------------------------
-- SELECT geocode_status, count(*) FROM estate.apt_complex GROUP BY geocode_status;
-- SELECT count(*) FILTER (WHERE geom IS NOT NULL) AS 좌표있음, count(*) AS 전체 FROM estate.apt_complex;

-- ----------------------------------------------------------------------------
-- 되돌리기
-- ----------------------------------------------------------------------------
-- DROP TABLE IF EXISTS estate.apt_complex;
