-- ============================================================================
-- estate 스키마 조회 전용 계정 (sj-lab-estate 서비스용)
--
-- 왜 필요한가
--   sj-lab-estate 는 부동산 실거래를 **읽기만** 한다(적재는 sj-lab-scheduler).
--   개인/superuser 계정을 서비스에 넣지 않기 위해 전용 최소권한 계정을 둔다.
--   sj-lab-openapi 가 쓰는 openapi_svc 와 같은 방침이다(docs/k8s-secrets.md).
--
-- 실행
--   **에이전트가 실행하지 않는다.** DB 권한이 있는 담당자가 psql 로 실행한다.
--   비밀번호는 실행하는 자리에서 직접 넣고, **이 파일이나 저장소에 적지 말 것**
--   (이 저장소는 public). 넣은 값은 k8s Secret(estate-db-credentials)과
--   로컬 .claude/settings.local.json 에만 둔다.
--
-- 실행 전에는?
--   계정이 없어도 서비스는 뜬다 — 조회만 503(NOT_CONFIGURED) 이고
--   GET /estate/status 가 ready:false 로 답한다. 화면은 "준비되지 않았다"고 안내한다.
--
-- 2026-10-12 작성. 개발 DB 와 운영 DB 가 같은 인스턴스이므로 한 번만 실행하면 된다.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) 계정 생성 (비밀번호는 실행할 때 바꿔 넣을 것)
-- ----------------------------------------------------------------------------
-- CREATE ROLE estate_read WITH LOGIN PASSWORD '여기에-강한-비밀번호';

-- 이미 있으면 비밀번호만 바꿀 때:
-- ALTER ROLE estate_read WITH PASSWORD '여기에-강한-비밀번호';

COMMENT ON ROLE estate_read IS 'sj-lab-estate 서비스용 조회 전용 계정 (estate 스키마 SELECT)';

-- ----------------------------------------------------------------------------
-- 2) 접속 권한
-- ----------------------------------------------------------------------------
GRANT CONNECT ON DATABASE sjlab TO estate_read;

-- ----------------------------------------------------------------------------
-- 3) 읽기 권한 — 서비스가 실제로 부르는 것만
--    (SELECT 만. INSERT/UPDATE/DELETE 는 필요 없다 — 커넥션도 readOnly 로 연다)
-- ----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA estate TO estate_read;
GRANT SELECT ON estate.apt_trade              TO estate_read;  -- 매매
GRANT SELECT ON estate.apt_rent               TO estate_read;  -- 전월세
GRANT SELECT ON estate.v_apt_trade_monthly    TO estate_read;  -- 지역 선택 시 매매 추세
GRANT SELECT ON estate.v_apt_rent_monthly     TO estate_read;  -- 지역 선택 시 전월세 추세

-- 시군구 이름 표시용(행정구역 경계 표)
GRANT USAGE  ON SCHEMA public      TO estate_read;
GRANT SELECT ON public.g_sgg       TO estate_read;

-- 앞으로 estate 스키마에 표/뷰가 추가돼도 자동으로 읽을 수 있게 한다
-- (오피스텔·빌라 표가 생기면 이 줄 덕분에 따로 GRANT 하지 않아도 된다)
ALTER DEFAULT PRIVILEGES IN SCHEMA estate GRANT SELECT ON TABLES TO estate_read;

-- 집계 MATERIALIZED VIEW 를 만들었다면(db/estate/estate_apt_monthly_matview.sql) 같이:
-- GRANT SELECT ON estate.v_apt_trade_monthly, estate.v_apt_rent_monthly TO estate_read;

-- ----------------------------------------------------------------------------
-- 4) 확인
-- ----------------------------------------------------------------------------
-- 권한 목록
--   SELECT table_schema, table_name, privilege_type
--     FROM information_schema.table_privileges
--    WHERE grantee = 'estate_read'
--    ORDER BY table_schema, table_name;
--
-- 실제로 읽히는지 (estate_read 로 접속해서)
--   SELECT count(*) FROM estate.apt_trade WHERE deal_year = 2026 AND deal_month = 9;
--   SELECT reltuples::bigint FROM pg_class WHERE oid = 'estate.apt_trade'::regclass;
--
-- 쓰기가 막혔는지 (ERROR: permission denied 가 나와야 정상)
--   INSERT INTO estate.apt_trade (sgg_cd) VALUES ('00000');

-- ----------------------------------------------------------------------------
-- 5) 되돌리기
-- ----------------------------------------------------------------------------
-- REVOKE ALL ON ALL TABLES IN SCHEMA estate FROM estate_read;
-- REVOKE ALL ON SCHEMA estate FROM estate_read;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA estate REVOKE SELECT ON TABLES FROM estate_read;
-- REVOKE CONNECT ON DATABASE sjlab FROM estate_read;
-- DROP ROLE estate_read;
