import React, { useEffect, useMemo, useRef, useState } from "react";
import Map from "ol/Map";
import View from "ol/View";
import TileLayer from "ol/layer/Tile";
import VectorLayer from "ol/layer/Vector";
import VectorSource from "ol/source/Vector";
import XYZ from "ol/source/XYZ";
import GeoJSON from "ol/format/GeoJSON";
import { Fill, Stroke, Style, Text } from "ol/style";
import { fromLonLat } from "ol/proj";
import { fetchMapRegions, formatCount, formatManwon } from "../api";

/**
 * 지역 지도 — 행정구역을 평균 거래가로 칠해 보여 준다.
 *
 * <p><b>왜 이 지도부터인가</b>: 단지 핀을 찍으려면 좌표가 필요한데 실거래 원천에 좌표가 없다
 * (지오코딩 키 발급이 선행). 반면 <b>행정구역 경계는 이미 DB 에 있어</b> 추가 데이터 없이 지도를
 * 띄울 수 있다. 좌표가 모이면 <b>이 지도 위에 단지 핀 레이어를 얹으면 된다</b>.
 *
 * <p>배경 지도는 지도 서비스(sj-lab-mapservice)와 같은 VWorld 타일을 쓴다 — 플랫폼 안에서 같은
 * 배경을 보게 하려는 것이다.
 *
 * <p>지도 라이브러리는 OpenLayers 다. 이 저장소는 "차트 라이브러리를 들이지 않는다"는 규칙이
 * 있지만 <b>지도는 직접 그릴 수 있는 것이 아니고</b>, 지도 서비스도 같은 라이브러리를 쓴다.
 */
/**
 * OpenLayers 가 쓰는 최소 스타일.
 *
 * <p>이 저장소는 CSS 파일·로더를 들이지 않는 규칙이라 `ol/ol.css` 를 import 할 수 없다
 * (webpack 에 css 로더가 없다). 지도가 보이는 데 꼭 필요한 규칙만 옮겨 적어 한 번만 끼워 넣는다.
 * 지도 레이어 위치는 OpenLayers 가 인라인으로 넣으므로 여기에는 없다.
 */
const OL_BASE_CSS = `
.ol-viewport, .ol-unselectable { -webkit-touch-callout: none; user-select: none; -webkit-user-select: none; -webkit-tap-highlight-color: transparent; }
.ol-viewport { touch-action: pan-x pan-y; }
.ol-viewport canvas { all: unset; overflow: hidden; }
.ol-control { position: absolute; background-color: rgba(255,255,255,0.75); border-radius: 6px; padding: 2px; }
.ol-control button { display: block; margin: 1px; padding: 0; width: 1.6em; height: 1.6em; font-size: 1rem; font-weight: 700; line-height: 1; color: #475569; background: #ffffff; border: none; border-radius: 4px; cursor: pointer; }
.ol-control button:hover { color: #0f172a; }
.ol-zoom { top: 0.6em; left: 0.6em; }
.ol-attribution { right: 0.5em; bottom: 0.5em; text-align: right; max-width: calc(100% - 1.3em); display: flex; flex-flow: row-reverse; align-items: center; }
.ol-attribution ul { margin: 0; padding: 1px 0.5em; font-size: 11px; color: #475569; }
.ol-attribution li { display: inline; list-style: none; }
.ol-attribution.ol-collapsed ul { display: none; }
`;

let olCssInjected = false;

function ensureOlCss() {
  if (olCssInjected || typeof document === "undefined") return;
  const style = document.createElement("style");
  style.setAttribute("data-ol-base", "1");
  style.textContent = OL_BASE_CSS;
  document.head.appendChild(style);
  olCssInjected = true;
}

function RegionMap({ level, sidoCd, sggCd, fromYm, toYm, propertyType, onSelectRegion }) {
  const containerRef = useRef(null);
  const mapRef = useRef(null);
  const sourceRef = useRef(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [hovered, setHovered] = useState(null);
  const [range, setRange] = useState({ min: 0, max: 0 });

  // 지도는 한 번만 만든다(데이터가 바뀔 때마다 다시 만들면 보던 위치가 튄다)
  useEffect(() => {
    if (mapRef.current) return;
    ensureOlCss();

    const source = new VectorSource();
    sourceRef.current = source;

    const map = new Map({
      target: containerRef.current,
      layers: [
        new TileLayer({
          source: new XYZ({
            // 지도 서비스와 같은 배경 타일
            url: "https://xdworld.vworld.kr/2d/Base/service/{z}/{x}/{y}.png",
            crossOrigin: "anonymous",
            attributions: "VWorld",
            maxZoom: 19,
          }),
        }),
        new VectorLayer({ source, style: (feature) => regionStyle(feature, rangeRef.current) }),
      ],
      view: new View({ center: fromLonLat([127.0, 37.55]), zoom: 10 }),
    });

    map.on("pointermove", (event) => {
      const feature = map.forEachFeatureAtPixel(event.pixel, (f) => f);
      setHovered(feature ? feature.getProperties() : null);
      map.getTargetElement().style.cursor = feature ? "pointer" : "";
    });

    map.on("singleclick", (event) => {
      const feature = map.forEachFeatureAtPixel(event.pixel, (f) => f);
      if (!feature) return;
      const props = feature.getProperties();
      if (onSelectRegion) onSelectRegion(props.level, props.code, props.name);
    });

    mapRef.current = map;
    return () => {
      map.setTarget(undefined);
      mapRef.current = null;
    };
    // onSelectRegion 은 매 렌더마다 새로 만들어질 수 있어 의존성에서 뺀다(아래 ref 로 최신을 쓴다)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 색 범위를 스타일 함수에서 읽기 위해 ref 로 둔다(스타일은 지도 생성 시 한 번 묶인다)
  const rangeRef = useRef(range);
  rangeRef.current = range;

  // 조건이 바뀌면 경계+평균가를 다시 받아 그린다
  useEffect(() => {
    const source = sourceRef.current;
    if (!source) return;
    if (level === "emd" && !sggCd) return;

    let alive = true;
    setLoading(true);
    setError("");
    fetchMapRegions(propertyType, { level, sidoCd, sggCd, fromYm, toYm })
      .then((geojson) => {
        if (!alive) return;
        const features = new GeoJSON().readFeatures(geojson, {
          dataProjection: "EPSG:4326",
          featureProjection: "EPSG:3857",
        });
        source.clear();
        source.addFeatures(features);

        // 색 범위는 그때그때 데이터로 정한다 — 전국과 한 구는 금액대가 완전히 다르다
        const amounts = features
          .map((f) => Number(f.get("avg_amount")))
          .filter((v) => Number.isFinite(v) && v > 0)
          .sort((a, b) => a - b);
        if (amounts.length > 0) {
          // 양 끝 값에 색이 휘둘리지 않게 10~90% 구간을 쓴다
          const low = amounts[Math.floor(amounts.length * 0.1)];
          const high = amounts[Math.floor(amounts.length * 0.9)];
          setRange({ min: low, max: high > low ? high : low + 1 });
        } else {
          setRange({ min: 0, max: 0 });
        }

        const extent = source.getExtent();
        if (extent && Number.isFinite(extent[0])) {
          mapRef.current.getView().fit(extent, { padding: [40, 40, 40, 40], duration: 300 });
        }
        // 색 범위가 바뀌었으니 다시 그린다
        source.changed();
      })
      .catch((e) => alive && setError(e.message))
      .finally(() => alive && setLoading(false));

    return () => {
      alive = false;
    };
  }, [propertyType, level, sidoCd, sggCd, fromYm, toYm]);

  const legend = useMemo(() => {
    if (!range.max) return [];
    const steps = 5;
    return Array.from({ length: steps }, (_, i) => {
      const value = range.min + ((range.max - range.min) * i) / (steps - 1);
      return { value, color: colorFor(value, range) };
    });
  }, [range]);

  return (
    <div style={wrapStyle}>
      <div ref={containerRef} style={mapStyle} />

      {loading && <div style={badgeStyle}>지도 불러오는 중…</div>}
      {error && <div style={{ ...badgeStyle, color: "#b91c1c" }}>{error}</div>}

      {hovered && (
        <div style={tooltipStyle}>
          <strong>{hovered.name}</strong>
          <span style={tooltipSubStyle}>
            {hovered.deal_count > 0
              ? `${formatCount(hovered.deal_count)}건 · 평균 ${formatManwon(hovered.avg_amount)}`
              : "이 기간 거래 없음"}
          </span>
        </div>
      )}

      {legend.length > 0 && (
        <div style={legendStyle}>
          <span style={legendTitleStyle}>평균 거래가</span>
          <div style={legendBarStyle}>
            {legend.map((item, idx) => (
              <span key={idx} style={{ ...legendChipStyle, background: item.color }} />
            ))}
          </div>
          <div style={legendRangeStyle}>
            <span>{formatManwon(range.min)}</span>
            <span>{formatManwon(range.max)}</span>
          </div>
        </div>
      )}
    </div>
  );
}

export default RegionMap;

/** 금액이 높을수록 진한 파랑. 거래가 없는 지역은 회색으로 둔다(0원으로 칠하면 "가장 싼 곳"처럼 보인다). */
function colorFor(value, range) {
  if (!value || !range.max) return "rgba(148, 163, 184, 0.35)";
  const ratio = Math.max(0, Math.min(1, (value - range.min) / (range.max - range.min)));
  const light = 92 - ratio * 52; // 92% → 40%
  return `hsla(217, 85%, ${light}%, 0.78)`;
}

function regionStyle(feature, range) {
  const amount = Number(feature.get("avg_amount"));
  const name = feature.get("name");
  return new Style({
    fill: new Fill({ color: colorFor(amount, range) }),
    stroke: new Stroke({ color: "rgba(30, 64, 175, 0.55)", width: 1 }),
    text: new Text({
      text: name || "",
      font: "600 12px system-ui, sans-serif",
      fill: new Fill({ color: "#0f172a" }),
      stroke: new Stroke({ color: "rgba(255,255,255,0.85)", width: 3 }),
      overflow: true,
    }),
  });
}

const wrapStyle = {
  position: "relative",
  width: "100%",
  height: "clamp(380px, 60vh, 720px)",
  borderRadius: "14px",
  overflow: "hidden",
  border: "1px solid #e2e8f0",
  background: "#eef2f7",
};

const mapStyle = { width: "100%", height: "100%" };

const badgeStyle = {
  position: "absolute",
  top: "12px",
  left: "12px",
  padding: "0.35rem 0.7rem",
  borderRadius: "999px",
  background: "rgba(255,255,255,0.92)",
  border: "1px solid #e2e8f0",
  fontSize: "0.8rem",
  color: "#475569",
};

const tooltipStyle = {
  position: "absolute",
  top: "12px",
  right: "12px",
  display: "flex",
  flexDirection: "column",
  gap: "0.15rem",
  padding: "0.5rem 0.8rem",
  borderRadius: "10px",
  background: "rgba(255,255,255,0.95)",
  border: "1px solid #e2e8f0",
  fontSize: "0.85rem",
  color: "#0f172a",
  maxWidth: "220px",
};

const tooltipSubStyle = { fontSize: "0.78rem", color: "#64748b" };

const legendStyle = {
  position: "absolute",
  left: "12px",
  bottom: "12px",
  padding: "0.5rem 0.7rem",
  borderRadius: "10px",
  background: "rgba(255,255,255,0.95)",
  border: "1px solid #e2e8f0",
  minWidth: "180px",
};

const legendTitleStyle = { fontSize: "0.74rem", color: "#64748b" };
const legendBarStyle = { display: "flex", gap: "2px", margin: "0.3rem 0 0.2rem" };
const legendChipStyle = { flex: 1, height: "10px", borderRadius: "2px" };
const legendRangeStyle = { display: "flex", justifyContent: "space-between", fontSize: "0.72rem", color: "#94a3b8" };
