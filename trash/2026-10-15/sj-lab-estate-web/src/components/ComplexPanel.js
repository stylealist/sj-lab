import React, { useEffect, useMemo, useState } from "react";
import {
  fetchComplexDetail,
  fetchComplexMonthly,
  fetchComplexRentMonthly,
  fetchComplexTrades,
  formatCount,
  formatManwon,
  formatYmLong,
  toPyeong,
} from "../api";
import TrendChart from "./TrendChart";

/**
 * 단지 상세 패널 — 호갱노노의 왼쪽 패널에 해당하는 화면이다.
 *
 * <p>평형을 고르고 → 그 평형의 최근 실거래 평균 · 추세 · 거래 목록을 본다.
 * 좌표가 생기면 지도 핀을 눌렀을 때 이 패널을 그대로 띄우면 된다(그래서 단지 키만 받는다).
 *
 * <p><b>평형은 전용면적 기준이다.</b> 원천(국토교통부 실거래)에 공급면적이 없어, 분양 평형과
 * 다를 수 있다 — 그래서 "전용 84㎡" 를 함께 적는다. 숫자만 보여 주면 오해를 부른다.
 */
function ComplexPanel({ propertyType, aptSeq, umdNm, onClose }) {
  const [detail, setDetail] = useState(null);
  const [pyeong, setPyeong] = useState(null);
  const [mode, setMode] = useState("trade"); // trade | rent
  const [monthly, setMonthly] = useState([]);
  const [trades, setTrades] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // 단지 기본 정보 + 평형 목록
  useEffect(() => {
    let alive = true;
    setDetail(null);
    setPyeong(null);
    setError("");
    setLoading(true);
    fetchComplexDetail(propertyType, aptSeq, umdNm)
      .then((data) => {
        if (!alive) return;
        setDetail(data);
        // 거래가 가장 많은 평형을 먼저 보여 준다(그 단지의 대표 평형)
        const areas = data.areas || [];
        const main = areas.slice().sort((a, b) => b.deal_count - a.deal_count)[0];
        setPyeong(main ? main.pyeong : null);
      })
      .catch((e) => alive && setError(e.message))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [propertyType, aptSeq, umdNm]);

  // 고른 평형의 추세·거래
  useEffect(() => {
    if (!detail) return;
    let alive = true;
    setLoading(true);
    const params = { umdNm, pyeong };
    const jobs =
      mode === "trade"
        ? [
            fetchComplexMonthly(propertyType, aptSeq, params).then(
              (d) => alive && setMonthly(d.items || [])
            ),
            fetchComplexTrades(propertyType, aptSeq, { ...params, limit: 30 }).then(
              (d) => alive && setTrades(d.items || [])
            ),
          ]
        : [
            fetchComplexRentMonthly(propertyType, aptSeq, params).then(
              (d) => alive && setMonthly(d.items || [])
            ),
          ];
    Promise.all(jobs)
      .catch((e) => alive && setError(e.message))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [detail, propertyType, aptSeq, umdNm, pyeong, mode]);

  const areas = (detail && detail.areas) || [];
  const currentArea = useMemo(
    () => areas.find((a) => a.pyeong === pyeong) || null,
    [areas, pyeong]
  );

  /** 최근 거래 1건이 아니라 **최근 달의 평균**을 보여 준다(한 건은 특이값일 수 있다). */
  const recentAverage = useMemo(() => {
    if (!monthly || monthly.length === 0) return null;
    return monthly[monthly.length - 1];
  }, [monthly]);

  if (error) {
    return (
      <div style={panelStyle}>
        <PanelHeader detail={detail} aptSeq={aptSeq} onClose={onClose} />
        <p style={errorStyle}>{error}</p>
      </div>
    );
  }

  return (
    <div style={panelStyle}>
      <PanelHeader detail={detail} aptSeq={aptSeq} onClose={onClose} />

      {!detail ? (
        <p style={noteStyle}>불러오는 중…</p>
      ) : (
        <>
          <div style={metaRowStyle}>
            <span style={metaChipStyle}>
              {detail.build_year ? `${detail.build_year}년 준공` : "준공연도 미상"}
            </span>
            {detail.dong_count > 0 && <span style={metaChipStyle}>{detail.dong_count}개 동</span>}
            <span style={metaChipStyle}>거래 {formatCount(detail.deal_count)}건</span>
            <span style={metaChipStyle}>
              {formatYmLong(detail.first_ym)} ~ {formatYmLong(detail.last_ym)}
            </span>
          </div>

          {/* 매매 / 전월세 */}
          <div style={modeRowStyle}>
            {[
              ["trade", "매매"],
              ["rent", "전월세"],
            ].map(([key, label]) => (
              <button
                key={key}
                type="button"
                style={mode === key ? modeActiveStyle : modeButtonStyle}
                onClick={() => setMode(key)}
              >
                {label}
              </button>
            ))}
          </div>

          {/* 평형 선택 — 전용면적 기준임을 함께 적는다 */}
          <div style={areaRowStyle}>
            {areas.map((area) => (
              <button
                key={area.pyeong}
                type="button"
                style={area.pyeong === pyeong ? areaActiveStyle : areaButtonStyle}
                onClick={() => setPyeong(area.pyeong)}
                title={`전용 ${area.area_min}~${area.area_max}㎡ · 거래 ${formatCount(area.deal_count)}건`}
              >
                <strong>{area.pyeong}평</strong>
                <span style={areaSubStyle}>전용 {Math.round(area.area_min)}㎡</span>
              </button>
            ))}
            <button
              type="button"
              style={pyeong === null ? areaActiveStyle : areaButtonStyle}
              onClick={() => setPyeong(null)}
            >
              <strong>전체</strong>
              <span style={areaSubStyle}>모든 평형</span>
            </button>
          </div>

          {/* 최근 실거래 기준 평균 */}
          <div style={headlineStyle}>
            <span style={headlineLabelStyle}>
              {mode === "trade" ? "최근 실거래 기준 1개월 평균" : "최근 1개월 평균 전세 보증금"}
            </span>
            <span style={headlineValueStyle}>
              {recentAverage
                ? formatManwon(
                    mode === "trade" ? recentAverage.avg_amount : recentAverage.avg_jeonse_deposit
                  )
                : "거래 없음"}
            </span>
            {recentAverage && (
              <span style={headlineSubStyle}>
                {formatYmLong(recentAverage.ym)} · {formatCount(recentAverage.deal_count)}건
                {currentArea ? ` · 전용 ${Math.round(currentArea.area_min)}㎡` : ""}
              </span>
            )}
          </div>

          <div style={chartBoxStyle}>
            {mode === "trade" ? (
              <TrendChart items={monthly} lineKey="avg_amount" lineLabel="평균 거래가" />
            ) : (
              <TrendChart
                items={monthly}
                lineKey="avg_jeonse_deposit"
                lineLabel="평균 전세 보증금"
                lineColor="#047857"
                barColor="#bbf7d0"
              />
            )}
          </div>

          {mode === "trade" && (
            <div style={{ marginTop: "1rem" }}>
              <h4 style={subTitleStyle}>최근 거래</h4>
              {trades.length === 0 ? (
                <p style={noteStyle}>{loading ? "불러오는 중…" : "표시할 거래가 없습니다."}</p>
              ) : (
                <div style={{ overflowX: "auto" }}>
                  <table style={tableStyle}>
                    <thead>
                      <tr>
                        <th style={thStyle}>계약일</th>
                        <th style={thStyle}>평형</th>
                        <th style={{ ...thStyle, textAlign: "right" }}>전용(㎡)</th>
                        <th style={{ ...thStyle, textAlign: "right" }}>층</th>
                        <th style={{ ...thStyle, textAlign: "right" }}>거래가</th>
                        <th style={{ ...thStyle, textAlign: "right" }}>㎡당</th>
                      </tr>
                    </thead>
                    <tbody>
                      {trades.map((row, idx) => (
                        <tr key={`${row.deal_year}-${row.deal_month}-${row.deal_day}-${idx}`}>
                          <td style={tdStyle}>
                            {row.deal_year}-{String(row.deal_month).padStart(2, "0")}-
                            {String(row.deal_day).padStart(2, "0")}
                          </td>
                          <td style={tdStyle}>
                            {row.pyeong}평{row.apt_dong ? ` · ${row.apt_dong}동` : ""}
                          </td>
                          <td style={numStyle}>{Number(row.exclu_use_ar).toFixed(2)}</td>
                          <td style={numStyle}>{row.floor}</td>
                          <td style={{ ...numStyle, fontWeight: 600 }}>{formatManwon(row.deal_amount)}</td>
                          <td style={numStyle}>
                            {row.amount_per_m2 ? `${Number(row.amount_per_m2).toLocaleString()}만` : "-"}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

          <p style={footNoteStyle}>
            평형은 <b>전용면적</b> 기준입니다(원천 데이터에 공급면적이 없습니다). 세대수·용적률 같은
            단지 정보와 지도 표시는 아직 없습니다 — 좌표와 단지 정보를 따로 받아야 합니다.
          </p>
        </>
      )}
    </div>
  );
}

export default ComplexPanel;

function PanelHeader({ detail, aptSeq, onClose }) {
  return (
    <div style={headerStyle}>
      <div>
        <div style={titleStyle}>{detail ? detail.apt_nm : aptSeq}</div>
        <div style={addressStyle}>
          {detail ? `${detail.umd_nm} ${detail.jibun || ""}` : ""}
          {detail && detail.road_nm ? ` · ${detail.road_nm}` : ""}
        </div>
      </div>
      <button type="button" style={closeButtonStyle} onClick={onClose} title="닫기">
        ✕
      </button>
    </div>
  );
}

const panelStyle = {
  background: "#ffffff",
  border: "1px solid #e2e8f0",
  borderRadius: "14px",
  padding: "1.2rem 1.3rem",
  boxShadow: "0 1px 2px rgba(15, 23, 42, 0.04)",
};

const headerStyle = { display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: "1rem" };
const titleStyle = { fontSize: "1.15rem", fontWeight: 700, color: "#0f172a" };
const addressStyle = { marginTop: "0.2rem", fontSize: "0.83rem", color: "#64748b" };

const closeButtonStyle = {
  border: "1px solid #e2e8f0",
  background: "#ffffff",
  borderRadius: "8px",
  width: "30px",
  height: "30px",
  cursor: "pointer",
  color: "#64748b",
  flexShrink: 0,
};

const metaRowStyle = { display: "flex", flexWrap: "wrap", gap: "0.4rem", marginTop: "0.8rem" };

const metaChipStyle = {
  padding: "0.2rem 0.55rem",
  borderRadius: "999px",
  background: "#f1f5f9",
  color: "#475569",
  fontSize: "0.76rem",
};

const modeRowStyle = { display: "flex", gap: "0.3rem", marginTop: "1rem" };

const modeButtonStyle = {
  padding: "0.35rem 0.9rem",
  border: "1px solid #e2e8f0",
  background: "#ffffff",
  color: "#475569",
  borderRadius: "8px",
  fontSize: "0.85rem",
  cursor: "pointer",
};

const modeActiveStyle = {
  ...modeButtonStyle,
  background: "#2563eb",
  borderColor: "#2563eb",
  color: "#ffffff",
  fontWeight: 600,
};

const areaRowStyle = { display: "flex", flexWrap: "wrap", gap: "0.4rem", marginTop: "0.8rem" };

const areaButtonStyle = {
  display: "flex",
  flexDirection: "column",
  alignItems: "center",
  gap: "0.1rem",
  padding: "0.4rem 0.7rem",
  border: "1px solid #e2e8f0",
  background: "#ffffff",
  borderRadius: "10px",
  cursor: "pointer",
  color: "#1e293b",
  fontSize: "0.85rem",
  minWidth: "72px",
};

const areaActiveStyle = {
  ...areaButtonStyle,
  background: "#eff6ff",
  borderColor: "#2563eb",
  color: "#1d4ed8",
};

const areaSubStyle = { fontSize: "0.68rem", color: "#94a3b8" };

const headlineStyle = {
  marginTop: "1.1rem",
  padding: "0.9rem 1rem",
  background: "#f8fafc",
  border: "1px solid #e2e8f0",
  borderRadius: "12px",
  display: "flex",
  flexDirection: "column",
  gap: "0.2rem",
};

const headlineLabelStyle = { fontSize: "0.8rem", color: "#64748b" };
const headlineValueStyle = { fontSize: "1.6rem", fontWeight: 700, color: "#1d4ed8" };
const headlineSubStyle = { fontSize: "0.78rem", color: "#94a3b8" };

const chartBoxStyle = { marginTop: "1rem" };
const subTitleStyle = { margin: "0 0 0.5rem", fontSize: "0.95rem", fontWeight: 700, color: "#0f172a" };
const noteStyle = { margin: "0.6rem 0 0", fontSize: "0.85rem", color: "#64748b" };
const errorStyle = { margin: "0.8rem 0 0", fontSize: "0.85rem", color: "#b91c1c" };

const footNoteStyle = {
  margin: "1rem 0 0",
  paddingTop: "0.8rem",
  borderTop: "1px dashed #e2e8f0",
  fontSize: "0.78rem",
  lineHeight: 1.6,
  color: "#94a3b8",
};

const tableStyle = { width: "100%", borderCollapse: "collapse", fontSize: "0.85rem", minWidth: "520px" };

const thStyle = {
  textAlign: "left",
  padding: "0.5rem 0.6rem",
  borderBottom: "1px solid #e2e8f0",
  color: "#64748b",
  fontWeight: 600,
  whiteSpace: "nowrap",
};

const tdStyle = { padding: "0.5rem 0.6rem", borderBottom: "1px solid #f1f5f9", color: "#1e293b", whiteSpace: "nowrap" };
const numStyle = { ...tdStyle, textAlign: "right" };
