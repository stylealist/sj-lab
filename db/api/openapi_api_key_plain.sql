-- ============================================================================
-- api.openapi_api_key 에 키 원문 컬럼 추가 (2026-10-01)
--
-- 왜 원문을 저장하나
--   화면("내 API 키")에서 자기 키 전체 값을 언제든 보고 복사할 수 있게 하기 위해서다.
--   전에는 해시만 두어 발급되는 순간에만 원문을 보여 줬고, 놓치면 키를 다시 만들 수밖에 없었다.
--   사용자 요청으로 방침을 바꿨다.
--
-- 무엇이 약해지나 (알고 쓸 것)
--   해시만 두면 DB 가 새도 그 값으로는 호출할 수 없다. 원문을 저장하면 그 보호가 사라진다.
--   이 키로 할 수 있는 일은 조회 전용 12개 API 와 하루 한도(기본 1000회) 소진까지이며
--   쓰기·삭제·권한 상승은 없다. 그래서 피해 범위는 "쿼터 도둑질 + 조회" 수준이다.
--   그래도 아래 두 가지는 지킬 것.
--     1) 검증은 계속 key_hash 로 한다. key_plain 은 본인에게 보여 주는 용도로만 쓰고 로그에 찍지 않는다.
--     2) 조회 전용 계정(mcp_readonly 등)에서 이 컬럼이 보이는지 확인한다 — 맨 아래 설명 참고.
--        pg_read_all_data 역할을 가진 계정은 컬럼 REVOKE 로 막을 수 없다.
--
-- 실행은 에이전트가 하지 않는다(프로젝트 규칙). DB 권한이 있는 담당자가 돌린다.
-- 재실행해도 안전하다(IF NOT EXISTS).
--
-- 이 컬럼이 없어도 서비스는 그대로 뜬다 — sj-lab-openapi 가 컬럼 유무를 확인해,
-- 없으면 예전처럼 앞자리(key_prefix)만 보여 준다. 즉 배포 순서에 묶이지 않는다.
-- ============================================================================

ALTER TABLE api.openapi_api_key
    ADD COLUMN IF NOT EXISTS key_plain varchar(80);

COMMENT ON COLUMN api.openapi_api_key.key_plain
    IS '키 원문. 본인 화면 표시용이며 검증은 key_hash 로 한다. 로그에 남기지 말 것';

-- ----------------------------------------------------------------------------
-- 조회 전용 계정(mcp_readonly)과 이 컬럼
--
-- 주의: 아래처럼 컬럼 단위로 REVOKE 해도 **막히지 않는다**. mcp_readonly 가
-- pg_read_all_data 역할의 멤버라서, 그 역할이 주는 "모든 표 읽기"를 컬럼 REVOKE 가
-- 덮어쓸 수 없기 때문이다(2026-10-01 확인). 다음 쿼리로 지금 상태를 확인한다.
--
--   SELECT r.rolname
--     FROM pg_auth_members m
--     JOIN pg_roles r ON r.oid = m.roleid
--    WHERE m.member = 'mcp_readonly'::regrole;
--
-- 결과에 pg_read_all_data 가 있으면 mcp_readonly 는 key_plain 도 읽을 수 있다.
-- 정말 가려야 한다면 역할 멤버십을 빼고 필요한 스키마만 직접 허용해야 한다.
-- MCP 로 보는 범위가 줄어드니 담당자가 판단해 실행할 것(그래서 주석으로 둔다).
--
--   REVOKE pg_read_all_data FROM mcp_readonly;
--   GRANT USAGE ON SCHEMA map, api, qfield, public TO mcp_readonly;
--   GRANT SELECT ON ALL TABLES IN SCHEMA map, qfield, public TO mcp_readonly;
--   GRANT SELECT (key_id, owner_username, key_prefix, label, daily_quota,
--                 use_yn, reg_date, last_used_at)
--       ON api.openapi_api_key TO mcp_readonly;
--   GRANT SELECT ON api.openapi_api_usage TO mcp_readonly;
--   ALTER DEFAULT PRIVILEGES IN SCHEMA map GRANT SELECT ON TABLES TO mcp_readonly;
--
-- 가리지 않기로 했다면 "조회 전용 계정에서도 키 원문이 보인다"는 사실만 알고 쓰면 된다 —
-- 이 키로 할 수 있는 일은 위에 적은 대로 조회와 쿼터 소진까지다.
-- ----------------------------------------------------------------------------

-- 서비스 계정은 읽고 써야 한다(이미 표 전체에 SELECT·INSERT·UPDATE 가 있으면 추가 작업 없음).
GRANT SELECT (key_plain), INSERT (key_plain), UPDATE (key_plain)
    ON api.openapi_api_key TO openapi_svc;
