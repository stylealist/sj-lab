-- ============================================================================
-- 부동산 회원 데이터 (즐겨찾기 · 최근 본 단지 · 메모)
--
--   대상 DB : sjlab  (개발 = 운영 같은 인스턴스)
--   실행    : DB 담당자. 에이전트는 실행하지 않는다.
--   쓰는 곳 : sj-lab-estate 의 /estate/member/**
--   상태    : 미실행 (2026-11-24 작성)
--
-- ── 왜 `member` 스키마인가 ───────────────────────────────────────────────────
-- 실거래 표(`estate.apt_trade`·`apt_rent`·`apt_complex`)는 **수집기가 채우는 원천
-- 데이터**이고, 여기 있는 것은 **사람이 화면에서 만드는 데이터**다. 성격이 달라
-- 섞지 않는다(공개 API 표를 `api` 스키마에 따로 둔 것과 같은 이유다).
--
-- ── 왜 조회 전용 서비스가 이 표에 쓰는가 ─────────────────────────────────────
-- `sj-lab-estate` 는 실거래를 **읽기 전용**으로 연다. 회원 데이터는 그 규칙의 예외이며
-- **커넥션을 따로 연다**(`estate-member-pool`, 읽기 전용 아님). 실거래 커넥션은 종전대로
-- 읽기 전용이라 실수로 수집 데이터를 건드릴 수 없다.
-- 같은 구조가 이미 있다 — `mapservice-rest` 도 조회 서비스지만 내업 기록
-- (`map.facility_office_work`)은 직접 쓴다.
--
-- ── 이 스크립트를 실행하지 않으면 ───────────────────────────────────────────
-- **오류가 아니라 기능만 꺼진다.** 서비스가 표 유무를 확인해 없으면
-- `GET /estate/member/status` 가 `ready:false` 로 답하고, 화면은 즐겨찾기 단추를
-- 숨긴다. 지도·단지 조회는 전혀 영향이 없다.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS member;

COMMENT ON SCHEMA member IS '로그인한 사용자가 화면에서 만드는 데이터(수집 원천과 분리)';

-- ----------------------------------------------------------------------------
-- 1) 즐겨찾기 (관심 단지)
-- ----------------------------------------------------------------------------
-- 단지 이름·지역을 함께 둔다. 목록을 그릴 때마다 단지 표를 조인하지 않기 위한 것이고,
-- 단지가 사라져도 "무엇을 담아 뒀는지"는 남는다.
CREATE TABLE IF NOT EXISTS member.estate_favorite (
    username        varchar(120)  NOT NULL,   -- 로그인 계정(authserver 가 확인해 준 값)
    apt_seq         varchar(20)   NOT NULL,   -- 단지 키(앞 5자리가 시군구 코드)
    property_type   varchar(10)   NOT NULL DEFAULT 'apt',

    sgg_cd          varchar(5),
    umd_nm          varchar(40),
    apt_nm          varchar(100),

    -- **새 거래 알림의 기준점.** 마지막으로 이 단지를 본 시점의 "가장 최근 계약일"
    -- (YYYYMMDD 정수)이다. 이보다 뒤의 거래를 새 거래로 센다. 0 이면 아직 기준이 없는
    -- 것이라 서비스가 처음 셀 때 현재 값으로 채운다(담자마자 "새 거래 N건"이 뜨지 않게).
    seen_deal_ymd   integer       NOT NULL DEFAULT 0,
    seen_at         timestamp,

    reg_date        timestamp     NOT NULL DEFAULT now(),

    CONSTRAINT pk_estate_favorite PRIMARY KEY (username, apt_seq)
);

-- 내 즐겨찾기를 담은 순서로 본다
CREATE INDEX IF NOT EXISTS ix_estate_favorite_user
    ON member.estate_favorite (username, reg_date DESC);

COMMENT ON TABLE member.estate_favorite IS '관심 단지. (username, apt_seq) 가 키라 같은 단지를 두 번 담을 수 없다';
COMMENT ON COLUMN member.estate_favorite.seen_deal_ymd IS '마지막으로 본 시점의 최근 계약일(YYYYMMDD). 이보다 뒤의 거래가 새 거래';

-- ----------------------------------------------------------------------------
-- 2) 최근 본 단지
-- ----------------------------------------------------------------------------
-- 같은 단지를 다시 보면 **행을 늘리지 않고 시각만 갱신**한다(upsert). 방문 기록을
-- 쌓는 표가 아니라 "마지막으로 언제 봤나"를 담는 표다.
CREATE TABLE IF NOT EXISTS member.estate_recent (
    username        varchar(120)  NOT NULL,
    apt_seq         varchar(20)   NOT NULL,
    property_type   varchar(10)   NOT NULL DEFAULT 'apt',

    sgg_cd          varchar(5),
    umd_nm          varchar(40),
    apt_nm          varchar(100),

    viewed_at       timestamp     NOT NULL DEFAULT now(),

    CONSTRAINT pk_estate_recent PRIMARY KEY (username, apt_seq)
);

-- 최근 본 순서로 N개만 보여 준다 — 이 인덱스가 그 정렬을 맡는다
CREATE INDEX IF NOT EXISTS ix_estate_recent_user
    ON member.estate_recent (username, viewed_at DESC);

COMMENT ON TABLE member.estate_recent IS '최근 본 단지. 다시 보면 행이 늘지 않고 viewed_at 만 갱신된다';

-- ----------------------------------------------------------------------------
-- 3) 단지 메모
-- ----------------------------------------------------------------------------
-- 단지 하나에 메모 하나다. 여러 개를 쌓으면 화면에 목록이 또 생기고, 사람들이 실제로
-- 원하는 것은 "이 단지에 대한 내 한마디"다.
CREATE TABLE IF NOT EXISTS member.estate_note (
    username        varchar(120)  NOT NULL,
    apt_seq         varchar(20)   NOT NULL,
    property_type   varchar(10)   NOT NULL DEFAULT 'apt',

    note            varchar(1000) NOT NULL,

    reg_date        timestamp     NOT NULL DEFAULT now(),
    update_at       timestamp     NOT NULL DEFAULT now(),

    CONSTRAINT pk_estate_note PRIMARY KEY (username, apt_seq),
    CONSTRAINT ck_estate_note_not_blank CHECK (btrim(note) <> '')
);

COMMENT ON TABLE member.estate_note IS '단지별 내 메모. 단지 하나에 하나(빈 메모는 저장하지 않고 삭제한다)';

-- ----------------------------------------------------------------------------
-- 4) 권한
-- ----------------------------------------------------------------------------
-- `sj-lab-estate` 가 쓰는 계정(공개 API 와 공유하는 `openapi_svc`)에만 쓰기를 준다.
-- **실거래 스키마(`estate`)에는 조회 권한만 있는 상태를 그대로 둔다** — 그래서 회원
-- 커넥션이 읽기 전용이 아니어도 수집 데이터를 건드릴 수 없다.
GRANT USAGE ON SCHEMA member TO openapi_svc;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON member.estate_favorite, member.estate_recent, member.estate_note
    TO openapi_svc;

-- 앞으로 이 스키마에 표가 늘어도 같은 권한이 따라가게 한다
ALTER DEFAULT PRIVILEGES IN SCHEMA member
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO openapi_svc;

-- 조회 전용 계정(MCP·분석용)도 읽을 수 있게
GRANT USAGE ON SCHEMA member TO mcp_readonly;

-- ----------------------------------------------------------------------------
-- 5) 확인
-- ----------------------------------------------------------------------------
-- 표 3개가 보이면 끝이다. 서비스는 60초마다 다시 확인하므로 재기동이 필요 없다.
--
--   SELECT table_name FROM information_schema.tables
--    WHERE table_schema = 'member' ORDER BY table_name;
--
--   -- 서비스가 보는 상태(로컬)
--   -- curl http://localhost:8100/estate/member/status

-- ----------------------------------------------------------------------------
-- 6) 되돌리기
-- ----------------------------------------------------------------------------
-- 회원 데이터가 통째로 사라진다. 실거래 데이터와는 무관하다.
--
--   DROP TABLE IF EXISTS member.estate_note;
--   DROP TABLE IF EXISTS member.estate_recent;
--   DROP TABLE IF EXISTS member.estate_favorite;
--   -- DROP SCHEMA IF EXISTS member;   -- 다른 서비스가 쓰기 시작했다면 지우지 말 것
