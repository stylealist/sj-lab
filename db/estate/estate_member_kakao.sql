-- ============================================================================
-- 목표가 도달을 카카오톡으로 알리기 — 연결 정보 표 + 보낸 기록 컬럼
--
--   대상 DB : sjlab  (개발 = 운영 같은 인스턴스)
--   실행    : DB 담당자. 에이전트는 실행하지 않는다.
--   쓰는 곳 : sj-lab-estate 의 /estate/member/kakao/**
--   선행    : estate_member.sql(표 3개) · estate_member_target.sql(목표가 컬럼)
--   상태    : 미실행 (2026-11-26 작성)
--
-- ── 어떤 방식인가 ───────────────────────────────────────────────────────────
-- 카카오톡 **"나에게 보내기"** 다. 사용자가 자기 카카오 계정으로 한 번 동의하면, 서버가
-- 그 사람의 **"나와의 채팅"** 으로 메시지를 보낸다.
--
--   사업자등록 불필요 · 발송 비용 없음 · 템플릿 심사 없음
--   대신 **본인에게만** 보낼 수 있다(남에게 보내려면 카카오의 별도 심사가 필요하다).
--
-- ── 무엇을 저장하나 ─────────────────────────────────────────────────────────
-- 카카오가 주는 **갱신 토큰(refresh token)** 이다. 이것이 있어야 사용자가 사이트에 없을 때도
-- 서버가 대신 보낼 수 있다. **비밀값이므로 로그에 찍지 않고 화면에도 내려보내지 않는다**
-- (서비스는 "연결됨/안 됨" 만 알려 준다).
--
--   사용자가 "연결 끊기" 를 누르면 행을 지운다 — 토큰을 남겨 두면 끊었는데도 보낼 수 있다.
--
-- ── 실행하지 않으면 ─────────────────────────────────────────────────────────
-- **오류가 아니라 카카오 알림만 꺼진다.** `GET /estate/member/kakao/status` 가
-- `ready:false` 로 답하고 화면이 연결 단추를 숨긴다. 목표가 배지(화면 알림)는 그대로 돈다.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) 연결 정보
-- ----------------------------------------------------------------------------
-- 한 계정에 카카오 연결 하나다(`username` 이 기본키). 여러 개를 허용하면 "어디로 보낼지" 를
-- 또 골라야 하는데, 쓰는 사람에게는 그런 선택지가 필요 없다.
CREATE TABLE IF NOT EXISTS member.estate_kakao (
    username          varchar(120) NOT NULL,   -- 로그인 계정(authserver 가 확인해 준 값)

    -- 카카오가 발급한 토큰. refresh_token 은 길어질 수 있어 넉넉히 잡는다.
    refresh_token     varchar(500) NOT NULL,
    access_token      varchar(500),
    access_expires_at timestamp,

    kakao_user_id     bigint,                  -- 카카오 회원번호(같은 사람인지 확인용)

    -- 보내기를 잠시 끄고 싶을 때. 연결은 유지한 채 발송만 멈춘다.
    enabled           boolean      NOT NULL DEFAULT true,

    linked_at         timestamp    NOT NULL DEFAULT now(),
    last_sent_at      timestamp,

    -- **연달아 실패하면 스스로 멈춘다.** 사용자가 카카오 쪽에서 연결을 끊었는데 서버가 계속
    -- 두드리면 로그만 쌓인다. 실패가 쌓이면 서비스가 enabled 를 false 로 내린다.
    fail_count        integer      NOT NULL DEFAULT 0,
    last_error        varchar(300),

    CONSTRAINT pk_estate_kakao PRIMARY KEY (username)
);

COMMENT ON TABLE member.estate_kakao IS
    '카카오톡 "나에게 보내기" 연결. refresh_token 은 비밀값 — 로그·화면에 내보내지 않는다';
COMMENT ON COLUMN member.estate_kakao.refresh_token IS
    '카카오 갱신 토큰. 이것으로 접근 토큰을 다시 받아 사용자가 없을 때도 보낸다';
COMMENT ON COLUMN member.estate_kakao.fail_count IS
    '연속 실패 횟수. 일정 횟수를 넘으면 enabled=false 로 스스로 멈춘다';

-- ----------------------------------------------------------------------------
-- 2) 보낸 기록 (관심 단지 표에 컬럼 하나)
-- ----------------------------------------------------------------------------
-- **이 컬럼이 없으면 감시가 돌 때마다 같은 알림을 또 보낸다.** 마지막으로 알린 거래의
-- 계약일(YYYYMMDD)을 적어 두고, 그보다 뒤의 도달만 새로 알린다. 화면 배지와 달리
-- 카카오톡은 한 번 가면 되돌릴 수 없으므로 여기는 반드시 기록으로 막는다.
ALTER TABLE member.estate_favorite
    ADD COLUMN IF NOT EXISTS target_notified_ymd integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN member.estate_favorite.target_notified_ymd IS
    '카카오톡으로 알린 마지막 도달 거래의 계약일(YYYYMMDD). 중복 발송을 막는다';

-- ----------------------------------------------------------------------------
-- 3) 권한
-- ----------------------------------------------------------------------------
-- `estate_member.sql` 의 ALTER DEFAULT PRIVILEGES 가 새 표에도 같은 권한을 주지만,
-- 그 스크립트를 실행한 계정과 지금 계정이 다르면 적용되지 않으므로 명시해 둔다.
GRANT SELECT, INSERT, UPDATE, DELETE ON member.estate_kakao TO openapi_svc;

-- ----------------------------------------------------------------------------
-- 4) 확인
-- ----------------------------------------------------------------------------
--   SELECT username, enabled, linked_at, last_sent_at, fail_count
--     FROM member.estate_kakao;
--
--   SELECT apt_seq, target_amount, target_notified_ymd
--     FROM member.estate_favorite WHERE target_amount IS NOT NULL;
--
--   -- 서비스가 보는 상태(로컬)
--   -- curl http://localhost:8100/estate/member/kakao/status

-- ----------------------------------------------------------------------------
-- 5) 되돌리기
-- ----------------------------------------------------------------------------
-- 연결 정보가 사라진다(사용자는 다시 연결하면 된다). 관심 단지·목표가는 그대로다.
--
--   DROP TABLE IF EXISTS member.estate_kakao;
--   ALTER TABLE member.estate_favorite DROP COLUMN IF EXISTS target_notified_ymd;
