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
--     2) 조회 전용 계정(mcp_readonly 등)에서는 이 컬럼을 읽지 못하게 한다 — 맨 아래 GRANT 참고.
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

-- 조회 전용 계정이 남의 키를 볼 이유가 없다. 계정 이름이 다르면 맞춰 바꿀 것.
-- (권한이 없는 계정에 REVOKE 하면 오류가 아니라 무시된다)
REVOKE SELECT (key_plain) ON api.openapi_api_key FROM mcp_readonly;

-- 서비스 계정은 읽고 써야 한다(이미 표 전체에 SELECT·INSERT·UPDATE 가 있으면 추가 작업 없음).
GRANT SELECT (key_plain), INSERT (key_plain), UPDATE (key_plain)
    ON api.openapi_api_key TO openapi_svc;
