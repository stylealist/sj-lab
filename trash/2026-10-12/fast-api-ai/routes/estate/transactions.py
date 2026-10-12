"""부동산 실거래 조회 API (매물 종류별).

게이트웨이 경로는 `/fast-api-ai/estate/{propertyType}/...` 다(앱의 root_path 가 `/fast-api-ai`).
데이터는 estate 스키마에서 읽기만 한다 — 적재는 sj-lab-scheduler 담당.

**매물 종류를 경로에 둔 이유**: 국토교통부가 아파트·오피스텔·연립다세대·단독다가구를
각각 다른 API 로 제공하고 컬럼도 조금씩 달라, DB 표도 종류별로 나뉘게 된다.
경로에 종류를 두면 새 종류를 열 때 경로를 바꾸지 않고 표만 이어 붙이면 된다.

지금은 **아파트만 서비스**하고 나머지는 준비 중이라 503 과 함께 그 사실을 알려 준다
(404 로 두면 "주소가 틀렸나"로 읽혀 원인을 찾기 어렵다).

금액 단위는 모두 **만원**이다(원천 공개데이터 그대로).
"""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, Path, Query

from db import estate_db
from service import estate_service

router = APIRouter(prefix="/estate")

# 매물 종류와 서비스 여부. 표를 만들고 수집을 붙이면 여기 값을 바꾼다.
# 화면(sj-lab-estate-web)의 PROPERTY_TYPES 와 id 가 같아야 한다.
PROPERTY_TYPES = {
    "apt": {"label": "아파트", "available": True},
    "offi": {"label": "오피스텔", "available": False},
    "villa": {"label": "빌라 · 다가구", "available": False},
}


def _check_property_type(property_type: str) -> str:
    """경로의 매물 종류를 확인한다. 모르는 값은 400, 준비 중인 종류는 503."""
    info = PROPERTY_TYPES.get(property_type)
    if info is None:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "UNKNOWN_PROPERTY_TYPE",
                "message": "매물 종류는 %s 중 하나입니다." % ", ".join(PROPERTY_TYPES),
            },
        )
    if not info["available"]:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "PROPERTY_TYPE_NOT_READY",
                "message": "%s 실거래는 아직 서비스 준비 중입니다. 현재는 아파트만 조회할 수 있습니다."
                % info["label"],
            },
        )
    return property_type


def _guard():
    """DB 설정이 없으면 이 라우터만 503. 다른 라우터는 그대로 동작한다."""
    if not estate_db.settings.ESTATE_DB_DSN:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "NOT_CONFIGURED",
                "message": "부동산 데이터 접속 설정이 없습니다(ESTATE_DB_DSN). 관리자에게 문의하세요.",
            },
        )


def _run(fn, *args):
    """조회 중 오류는 원인을 숨기지 않되, 접속 문자열이 응답에 섞이지 않게 한다."""
    _guard()
    try:
        return fn(*args)
    except estate_db.EstateDbNotConfigured as e:
        raise HTTPException(status_code=503, detail={"code": "NOT_CONFIGURED", "message": str(e)})
    except Exception as e:
        raise HTTPException(
            status_code=502,
            detail={
                "code": "QUERY_FAILED",
                "message": "부동산 데이터를 조회하지 못했습니다: " + type(e).__name__,
            },
        )


def _check_ym(value: int | None, name: str) -> int | None:
    """기간은 yyyyMM 숫자로 받는다. 틀린 값은 조용히 무시하지 않고 400 으로 알려 준다."""
    if value is None:
        return None
    if value < 200601 or value > 299912 or not (1 <= value % 100 <= 12):
        raise HTTPException(
            status_code=400,
            detail={"code": "INVALID_PERIOD", "message": f"{name} 은 yyyyMM 형식이어야 합니다(예: 202601)."},
        )
    return value


PROPERTY_TYPE_PATH = Path(description="매물 종류 (apt · offi · villa). 현재 apt 만 서비스합니다.")
SGG_QUERY = Query(default=None, min_length=5, max_length=5, pattern=r"^\d{5}$")


@router.get("/status")
def status():
    """화면이 "데이터를 쓸 수 있는 상태인지" 확인할 때 쓴다. 로그인·설정이 없어도 부를 수 있다.

    매물 종류와 서비스 여부도 함께 돌려줘, 화면이 "준비 중" 목록을 하드코딩하지 않아도 되게 한다.
    """
    ready = estate_db.is_ready()
    return {
        "ready": ready,
        "message": "부동산 실거래 데이터를 조회할 수 있습니다."
        if ready
        else "부동산 데이터 접속이 준비되지 않았습니다.",
        "propertyTypes": [
            {"id": key, "label": info["label"], "available": info["available"]}
            for key, info in PROPERTY_TYPES.items()
        ],
    }


@router.get("/{propertyType}/meta")
def meta(propertyType: str = PROPERTY_TYPE_PATH):
    """데이터 범위 요약 — 건수·기간·지역 수·마지막 적재."""
    _check_property_type(propertyType)
    return _run(estate_service.get_meta)


@router.get("/{propertyType}/regions")
def regions(propertyType: str = PROPERTY_TYPE_PATH):
    """데이터가 있는 시군구 목록(코드 + 이름 + 거래건수). 화면 지역 선택에 쓴다."""
    _check_property_type(propertyType)
    return {"items": _run(estate_service.get_regions)}


@router.get("/{propertyType}/trade/monthly")
def trade_monthly(
    propertyType: str = PROPERTY_TYPE_PATH,
    sggCd: str | None = SGG_QUERY,
    fromYm: int | None = Query(default=None),
    toYm: int | None = Query(default=None),
):
    """매매 월별 추세(건수·평균·중위·최저·최고·㎡당). sggCd 를 빼면 전국."""
    _check_property_type(propertyType)
    _check_ym(fromYm, "fromYm")
    _check_ym(toYm, "toYm")
    return {"items": _run(estate_service.get_trade_monthly, sggCd, fromYm, toYm)}


@router.get("/{propertyType}/rent/monthly")
def rent_monthly(
    propertyType: str = PROPERTY_TYPE_PATH,
    sggCd: str | None = SGG_QUERY,
    fromYm: int | None = Query(default=None),
    toYm: int | None = Query(default=None),
):
    """전월세 월별 추세(전세·월세 건수와 평균 보증금·월세). sggCd 를 빼면 전국."""
    _check_property_type(propertyType)
    _check_ym(fromYm, "fromYm")
    _check_ym(toYm, "toYm")
    return {"items": _run(estate_service.get_rent_monthly, sggCd, fromYm, toYm)}


@router.get("/{propertyType}/trade")
def trades(
    propertyType: str = PROPERTY_TYPE_PATH,
    sggCd: str | None = SGG_QUERY,
    fromYm: int | None = Query(default=None),
    toYm: int | None = Query(default=None),
    aptNm: str | None = Query(default=None, max_length=100),
    limit: int = Query(default=estate_service.LIST_LIMIT_DEFAULT, ge=1, le=estate_service.LIST_LIMIT_MAX),
):
    """매매 거래 목록(최근 계약일 순). 단지명은 부분 일치로 찾는다."""
    _check_property_type(propertyType)
    _check_ym(fromYm, "fromYm")
    _check_ym(toYm, "toYm")
    return {"items": _run(estate_service.get_trades, sggCd, fromYm, toYm, aptNm, limit)}


@router.get("/{propertyType}/trade/ranking")
def trade_ranking(
    propertyType: str = PROPERTY_TYPE_PATH,
    fromYm: int | None = Query(default=None),
    toYm: int | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
):
    """지역별 평균 거래가 순위. 평균이 튀지 않게 거래 10건 이상인 지역만 센다."""
    _check_property_type(propertyType)
    _check_ym(fromYm, "fromYm")
    _check_ym(toYm, "toYm")
    return {"items": _run(estate_service.get_trade_ranking, fromYm, toYm, limit)}
