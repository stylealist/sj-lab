-- estate.apt_complex 의 단지 영역(boundary) 겹침 정리
--
-- 왜 필요한가 (2026-10-26)
--   단지 영역을 대지 기준(_V7)으로 받으면서 "1·2단지로 나뉜 단지는 가까운 동 묶음을 같이
--   넣는다"는 규칙을 넣었다. 그 판정이 **"그 건물 묶음 30m 안에 남의 단지 핀이 있나"** 만
--   보기 때문에, 옆 단지가 동 여러 묶음으로 쪼개져 있으면(핀은 그중 한 곳에만 있다) 나머지
--   묶음이 "주인 없는 땅"으로 보여 빨려 들어왔다. 평촌·비산처럼 단지가 촘촘한 곳에서
--   거의 모든 단지가 옆 단지 땅을 머금었다(실측: 한승미메이드 영역의 92% 가 메가트리아 땅,
--   비산 삼성래미안 251,267㎡ 로 14개 단지와 겹침).
--
-- 무엇을 하는가
--   겹친 땅을 **핀이 더 가까운 단지에게** 준다(보로노이). 겹치지 않은 땅은 그대로 둔다.
--   땅을 나눠 갖는 쪽은 **살아 있는 단지**(최근 5년 거래가 있는 단지)뿐이다 — 철거된 옛 단지는
--   지도에 나오지 않으므로 셈에서 뺀다(그 단지의 영역은 손대지 않는다).
--   영역이 바뀌면 핀도 새 영역 가운데로 다시 옮긴다.
--
-- 되돌리기
--   원래 영역은 보관하지 않는다 — 수집기(`/scheduler/estate/complex/boundary`)로 다시 받으면
--   같은 값이 복원되므로 백업 컬럼을 두지 않았다.
--
-- 대상 DB · 계정
--   sjlab (개발 = 운영 같은 인스턴스) · estate 스키마에 쓰기 권한이 있는 계정으로 실행한다.
--
-- 실행
--   psql "<접속문자열>" -f db/estate/estate_apt_complex_boundary_clip.sql
--   (시군구 하나씩 돌며 UPDATE 한다. 전국 약 250개 시군구, 수 분 소요)

DO $$
DECLARE
    r       record;
    changed int;
    total   int := 0;
BEGIN
    FOR r IN
        SELECT DISTINCT sgg_cd
          FROM estate.apt_complex
         WHERE boundary IS NOT NULL AND geom IS NOT NULL
         ORDER BY 1
    LOOP
        WITH mine AS (
            -- 이 시군구에서 영역을 손볼 단지(살아 있는 단지만)
            SELECT c.apt_seq, c.geom, c.boundary
              FROM estate.apt_complex c
             WHERE c.sgg_cd = r.sgg_cd
               AND c.geom IS NOT NULL
               AND c.boundary IS NOT NULL
               AND EXISTS (
                   SELECT 1 FROM estate.apt_trade t
                    WHERE t.sgg_cd = c.sgg_cd AND t.umd_nm = c.umd_nm
                      AND t.jibun  = c.jibun  AND t.apt_nm = c.apt_nm
                      AND t.deal_year >= extract(year from now())::int - 4
               )
        ),
        box AS (
            -- 시군구 경계에 걸친 단지도 제대로 나뉘도록 2km 넓힌 범위를 쓴다
            SELECT ST_Expand(ST_Collect(geom), 2000) AS g FROM mine
        ),
        claim AS (
            -- 땅을 나눠 갖는 후보(옆 시군구 단지까지 포함)
            SELECT c.apt_seq, c.geom
              FROM estate.apt_complex c, box
             WHERE c.geom IS NOT NULL
               AND box.g IS NOT NULL
               AND ST_Intersects(c.geom, box.g)
               AND EXISTS (
                   SELECT 1 FROM estate.apt_trade t
                    WHERE t.sgg_cd = c.sgg_cd AND t.umd_nm = c.umd_nm
                      AND t.jibun  = c.jibun  AND t.apt_nm = c.apt_nm
                      AND t.deal_year >= extract(year from now())::int - 4
               )
        ),
        cells AS (
            SELECT (ST_Dump(ST_VoronoiPolygons(ST_Collect(c.geom), 0, (SELECT g FROM box)))).geom AS cell
              FROM claim c
        ),
        cut AS (
            SELECT m.apt_seq,
                   ST_CollectionExtract(ST_MakeValid(ST_Intersection(m.boundary, k.cell)), 3) AS g
              FROM mine m
              JOIN cells k ON ST_Contains(k.cell, m.geom)
        ),
        parts AS (
            SELECT c.apt_seq, d.geom AS part, ST_Area(d.geom) AS a
              FROM cut c, LATERAL ST_Dump(c.g) d
             WHERE c.g IS NOT NULL AND NOT ST_IsEmpty(c.g)
        ),
        kept AS (
            -- 잘린 자리에 남는 아주 작은 부스러기(300㎡ 미만)는 버린다
            SELECT apt_seq, ST_Multi(ST_Collect(part)) AS g
              FROM parts WHERE a >= 300 GROUP BY apt_seq
        ),
        biggest AS (
            -- 전부 부스러기면 그중 가장 큰 조각만 남긴다
            SELECT DISTINCT ON (apt_seq) apt_seq, ST_Multi(part) AS g
              FROM parts ORDER BY apt_seq, a DESC
        ),
        fin AS (
            SELECT p.apt_seq, COALESCE(k.g, b.g) AS g
              FROM (SELECT DISTINCT apt_seq FROM parts) p
              LEFT JOIN kept    k ON k.apt_seq = p.apt_seq
              LEFT JOIN biggest b ON b.apt_seq = p.apt_seq
        )
        UPDATE estate.apt_complex c
           SET boundary  = fin.g,
               geom      = ST_PointOnSurface(fin.g),
               lon       = ST_X(ST_Transform(ST_PointOnSurface(fin.g), 4326)),
               lat       = ST_Y(ST_Transform(ST_PointOnSurface(fin.g), 4326)),
               update_at = now()
          FROM fin
         WHERE c.apt_seq = fin.apt_seq
           AND fin.g IS NOT NULL
           AND NOT ST_IsEmpty(fin.g)
           AND ST_Area(fin.g) > 100
           -- 모양이 실제로 달라진 단지만 고친다(겹치지 않던 단지는 건드리지 않는다)
           AND ST_Area(fin.g) < ST_Area(c.boundary) - 1;

        GET DIAGNOSTICS changed = ROW_COUNT;
        total := total + changed;
        IF changed > 0 THEN
            RAISE NOTICE '% : 단지 %개 정리', r.sgg_cd, changed;
        END IF;
    END LOOP;

    RAISE NOTICE '끝 — 모두 %개 단지의 영역을 정리했다', total;
END $$;
