-- ============================================================================
-- estate.apt_complex 에 "단지 테두리"와 필지 키를 더한다 (2026-10-15)
--
-- 왜 필요한가
--   핀을 찍어 보니 단지 한가운데가 아니라 **가장자리**에 있었다. 행안부 좌표제공 API 가 주는
--   entX/entY 는 단지 중심이 아니라 **건물 출입구 좌표**이기 때문이다(은마아파트의 경우
--   실제 단지 서쪽 끝). 호갱노노처럼 단지 테두리도 없었다.
--
--   브이월드 연속지적도에서 그 단지의 **필지 폴리곤**을 받아오면 두 가지가 한 번에 풀린다.
--     - 핀 위치  : 폴리곤의 중심점(ST_PointOnSurface)을 쓴다
--     - 테두리   : 폴리곤을 그대로 지도에 그린다
--   연결고리는 PNU(필지 고유번호 19자리)다. 브이월드 지오코더가 지번으로 PNU 를 주고,
--   그 PNU 로 필지를 꺼낸다.
--
-- 실행 계정
--   estate.apt_complex 의 소유자(stylealist)로 실행한다. scheduler 의 datasource 계정과 같다.
--   조회 전용 계정(openapi_svc)에는 아래 GRANT 로 읽기만 준다.
--
-- 다시 실행해도 안전하다(IF NOT EXISTS).
-- ============================================================================

-- 1) 필지 키와 테두리 ---------------------------------------------------------
ALTER TABLE estate.apt_complex
    ADD COLUMN IF NOT EXISTS pnu             varchar(19),
    ADD COLUMN IF NOT EXISTS boundary        geometry(MultiPolygon, 3857),
    ADD COLUMN IF NOT EXISTS boundary_source varchar(20),
    ADD COLUMN IF NOT EXISTS boundary_at     timestamp;

COMMENT ON COLUMN estate.apt_complex.pnu IS
    '필지 고유번호 19자리. 브이월드 지오코더 응답의 level4LC. 연속지적도를 꺼내는 키';
COMMENT ON COLUMN estate.apt_complex.boundary IS
    '단지 테두리(연속지적도 필지 폴리곤, EPSG:3857). 지도 테두리와 핀 중심점의 원천';
COMMENT ON COLUMN estate.apt_complex.boundary_source IS
    '테두리를 받은 곳(VWORLD_CBND 등)';
COMMENT ON COLUMN estate.apt_complex.boundary_at IS
    '테두리를 받은 시각';

-- 2) 인덱스 -------------------------------------------------------------------
--    테두리를 아직 못 받은 단지를 골라내는 용도(수집기가 반복해서 묻는다)
CREATE INDEX IF NOT EXISTS ix_apt_complex_boundary_null
    ON estate.apt_complex (sgg_cd)
    WHERE boundary IS NULL;

--    화면 영역(bbox)으로 테두리를 꺼낼 때
CREATE INDEX IF NOT EXISTS ix_apt_complex_boundary_gist
    ON estate.apt_complex USING gist (boundary);

-- 3) 조회 전용 계정에 읽기 권한 -------------------------------------------------
--    컬럼을 더해도 표 단위 SELECT 권한은 그대로 이어지지만, 계정이 바뀐 경우를 대비해 한 번 더 준다.
GRANT SELECT ON estate.apt_complex TO openapi_svc;

-- 확인 ------------------------------------------------------------------------
-- select count(*) filter (where boundary is not null) as 테두리있음,
--        count(*) filter (where boundary is null)     as 아직,
--        count(*)                                     as 전체
--   from estate.apt_complex;
