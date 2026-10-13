-- ============================================================================
-- 부동산 조회 서비스가 쓰는 계정에 estate 스키마 읽기 권한 주기
--
-- 왜 이 스크립트인가
--   운영에 새 Secret(estate-db-credentials)을 만들지 않고 **이미 있는
--   openapi-db-credentials 를 그대로 쓰기로** 했다(2026-10-13 결정).
--   그 Secret 의 계정은 `openapi_svc` 이고, 공개 API 용으로 만들어져
--   **estate 스키마에는 아무 권한이 없다** — 확인 결과:
--
--     has_schema_privilege('openapi_svc','estate','usage')      → false
--     has_table_privilege('openapi_svc','estate.apt_trade','select') → false
--
--   권한을 주지 않으면 접속은 되고 조회만 "권한 없음"으로 실패한다.
--   이 스크립트가 **읽기 권한만** 준다(쓰기는 주지 않는다).
--
-- 실행
--   **에이전트가 실행하지 않는다.** DB 권한이 있는 담당자가 psql 로 실행한다.
--   대상 DB: sjlab (개발·운영 같은 인스턴스)
--
-- 실행 전에는?
--   서비스는 뜨지만 `GET /estate/status` 가 `reason: CONNECT_FAILED` 로 답하고
--   조회가 막힌다(화면에 그 이유가 그대로 표시된다).
--
-- 되돌리기·대안
--   계정을 섞지 않으려면 전용 계정(`estate_read`, db/estate/estate_read_role.sql)을 만들고
--   Secret 만 바꾸면 된다. 그때는 이 스크립트의 마지막 REVOKE 블록으로 되돌린다.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) 읽기 권한 — 서비스가 실제로 부르는 것만
-- ----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA estate TO openapi_svc;

GRANT SELECT ON estate.apt_trade           TO openapi_svc;  -- 매매
GRANT SELECT ON estate.apt_rent            TO openapi_svc;  -- 전월세
GRANT SELECT ON estate.v_apt_trade_monthly TO openapi_svc;  -- 지역 선택 시 매매 추세
GRANT SELECT ON estate.v_apt_rent_monthly  TO openapi_svc;  -- 지역 선택 시 전월세 추세

-- 지역 이름 표시용(행정구역 경계 표). 시도는 2026-10-13 지역 3단 선택 때 추가됐다 —
-- 없으면 시도 이름 대신 코드가 보인다(서비스가 그렇게 버티도록 만들어 뒀다).
GRANT USAGE  ON SCHEMA public TO openapi_svc;
GRANT SELECT ON public.g_sgg  TO openapi_svc;
GRANT SELECT ON public.g_sido TO openapi_svc;

-- 앞으로 estate 스키마에 표/뷰가 추가돼도(오피스텔·빌라) 따로 GRANT 하지 않도록
ALTER DEFAULT PRIVILEGES IN SCHEMA estate GRANT SELECT ON TABLES TO openapi_svc;

-- ----------------------------------------------------------------------------
-- 2) 확인 — 네 값이 모두 true 여야 한다
-- ----------------------------------------------------------------------------
SELECT has_schema_privilege('openapi_svc', 'estate', 'usage')                    AS 스키마_접속,
       has_table_privilege ('openapi_svc', 'estate.apt_trade', 'select')         AS 매매_읽기,
       has_table_privilege ('openapi_svc', 'estate.v_apt_trade_monthly','select') AS 매매뷰_읽기,
       has_table_privilege ('openapi_svc', 'public.g_sgg', 'select')             AS 시군구_읽기,
       has_table_privilege ('openapi_svc', 'public.g_sido', 'select')            AS 시도_읽기;

-- 쓰기가 막혀 있는지도 함께 확인(세 값 모두 false 여야 한다)
SELECT has_table_privilege('openapi_svc', 'estate.apt_trade', 'insert') AS 매매_쓰기,
       has_table_privilege('openapi_svc', 'estate.apt_trade', 'update') AS 매매_수정,
       has_table_privilege('openapi_svc', 'estate.apt_trade', 'delete') AS 매매_삭제;

-- ----------------------------------------------------------------------------
-- 3) 되돌리기 (전용 계정으로 옮길 때)
-- ----------------------------------------------------------------------------
-- ALTER DEFAULT PRIVILEGES IN SCHEMA estate REVOKE SELECT ON TABLES FROM openapi_svc;
-- REVOKE SELECT ON estate.apt_trade, estate.apt_rent,
--                  estate.v_apt_trade_monthly, estate.v_apt_rent_monthly FROM openapi_svc;
-- REVOKE USAGE ON SCHEMA estate FROM openapi_svc;
-- (public.g_sgg 는 공개 API 쪽에서도 쓸 수 있으니 확인 후 결정할 것)
