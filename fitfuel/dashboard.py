"""生成自带交互的本地 HTML 看板。"""

from __future__ import annotations

from pathlib import Path

from .paths import dashboard_path, ensure_parent
from .report import dashboard_data
from .util import json_escape_for_html

HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FitFuel · 训练与饮食看板</title>
<style>
  :root {
    color-scheme: light;
    --page: #f9f9f7;
    --surface-1: #fcfcfb;
    --surface-2: #f2f1ed;
    --text-primary: #0b0b0b;
    --text-secondary: #52514e;
    --text-muted: #898781;
    --border: rgba(11, 11, 11, 0.10);
    --grid: #e1e0d9;
    --axis: #c3c2b7;
    --series-1: #2a78d6;
    --series-2: #eb6834;
    --series-3: #1baf7a;
    --series-4: #eda100;
    --series-5: #e87ba4;
    --series-6: #008300;
    --series-7: #6250d6;
    --series-8: #e34948;
    --series-1-weak: #cde2fb;
    --status-good: #0ca30c;
    --status-warning: #fab219;
    --status-critical: #d03b3b;
    --shadow: 0 1px 2px rgba(11, 11, 11, 0.04);
  }
  :root[data-theme="dark"] {
    color-scheme: dark;
    --page: #0d0d0d;
    --surface-1: #1a1a19;
    --surface-2: #222220;
    --text-primary: #f0efec;
    --text-secondary: #c3c2b7;
    --text-muted: #898781;
    --border: rgba(255, 255, 255, 0.10);
    --grid: #2c2c2a;
    --axis: #383835;
    --series-1: #3987e5;
    --series-2: #d95926;
    --series-3: #199e70;
    --series-4: #c98500;
    --series-5: #d55181;
    --series-6: #0ca30c;
    --series-7: #9085e9;
    --series-8: #e66767;
    --series-1-weak: #184f95;
    --status-good: #0ca30c;
    --status-warning: #fab219;
    --status-critical: #d03b3b;
    --shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --page: #0d0d0d;
      --surface-1: #1a1a19;
      --surface-2: #222220;
      --text-primary: #f0efec;
      --text-secondary: #c3c2b7;
      --text-muted: #898781;
      --border: rgba(255, 255, 255, 0.10);
      --grid: #2c2c2a;
      --axis: #383835;
      --series-1: #3987e5;
      --series-2: #d95926;
      --series-3: #199e70;
      --series-4: #c98500;
      --series-5: #d55181;
      --series-6: #0ca30c;
      --series-7: #9085e9;
      --series-8: #e66767;
      --series-1-weak: #184f95;
      --status-good: #0ca30c;
      --status-warning: #fab219;
      --status-critical: #d03b3b;
      --shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
    }
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    background: var(--page);
    color: var(--text-primary);
    font-family: system-ui, -apple-system, "Segoe UI", "Noto Sans SC", "PingFang SC", sans-serif;
    font-size: 14px;
    line-height: 1.5;
    -webkit-font-smoothing: antialiased;
  }
  .page { max-width: 1440px; margin: 0 auto; padding: 28px 24px 56px; }
  .topbar { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; margin-bottom: 22px; }
  .brand { font-size: 12px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--text-muted); margin-bottom: 4px; }
  h1 { font-size: 26px; line-height: 1.2; margin: 0 0 6px; font-weight: 650; letter-spacing: -0.01em; }
  .sub { margin: 0; color: var(--text-secondary); font-size: 13px; }
  .ghost-btn {
    appearance: none; border: 1px solid var(--border); background: var(--surface-1); color: var(--text-secondary);
    border-radius: 8px; padding: 7px 12px; font: inherit; font-size: 13px; cursor: pointer; box-shadow: var(--shadow);
  }
  .ghost-btn:hover { background: var(--surface-2); color: var(--text-primary); }
  .ghost-btn:focus-visible, .filter-btn:focus-visible, .table-toggle:focus-visible, .chart-svg:focus-visible {
    outline: 2px solid var(--series-1); outline-offset: 2px;
  }
  .filterbar { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin-bottom: 16px; }
  .filter-label { color: var(--text-muted); font-size: 12px; margin-right: 2px; }
  .filter-btn {
    appearance: none; border: 1px solid var(--border); background: transparent; color: var(--text-secondary);
    border-radius: 999px; padding: 5px 12px; font: inherit; font-size: 12px; cursor: pointer;
  }
  .filter-btn:hover { background: var(--surface-2); color: var(--text-primary); }
  .filter-btn[aria-pressed="true"] { background: var(--text-primary); color: var(--surface-1); border-color: var(--text-primary); }
  .hero-grid { display: grid; grid-template-columns: minmax(260px, 1.15fr) 2fr; gap: 16px; margin-bottom: 16px; }
  .card {
    background: var(--surface-1); border: 1px solid var(--border); border-radius: 12px;
    padding: 18px; box-shadow: var(--shadow); min-width: 0;
  }
  .hero-card { display: flex; flex-direction: column; justify-content: space-between; min-height: 176px; }
  .tile-label { color: var(--text-secondary); font-size: 12px; margin-bottom: 6px; }
  .hero-value { font-size: 56px; line-height: 1; font-weight: 640; letter-spacing: -0.03em; margin: 2px 0 8px; }
  .hero-value .unit { font-size: 20px; font-weight: 500; color: var(--text-secondary); margin-left: 6px; letter-spacing: 0; }
  .delta { font-size: 12px; color: var(--text-secondary); display: flex; align-items: center; gap: 5px; min-height: 18px; }
  .delta.good { color: var(--status-good); }
  .delta.bad { color: var(--status-critical); }
  .hero-meta { color: var(--text-muted); font-size: 12px; margin-top: 14px; }
  .stat-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
  .stat { min-height: 80px; display: flex; flex-direction: column; justify-content: center; }
  .stat-value { font-size: 26px; font-weight: 620; line-height: 1.1; letter-spacing: -0.01em; }
  .stat-value .unit { font-size: 13px; color: var(--text-secondary); font-weight: 500; margin-left: 3px; }
  .stat-sub { color: var(--text-muted); font-size: 11px; margin-top: 4px; }
  .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
  .wide { grid-column: 1 / -1; }
  .card-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; margin-bottom: 10px; }
  .card-head h2 { font-size: 15px; font-weight: 620; margin: 0 0 2px; }
  .card-sub { margin: 0; color: var(--text-muted); font-size: 12px; }
  .table-toggle {
    appearance: none; border: 1px solid var(--border); background: transparent; color: var(--text-secondary);
    border-radius: 7px; padding: 4px 9px; font: inherit; font-size: 11px; cursor: pointer; white-space: nowrap;
  }
  .table-toggle:hover { background: var(--surface-2); color: var(--text-primary); }
  .chart-host { position: relative; width: 100%; min-height: 240px; }
  .chart-host.mini { min-height: 150px; }
  .chart-svg { display: block; width: 100%; overflow: visible; }
  .legend { display: flex; flex-wrap: wrap; gap: 12px; margin: 2px 0 8px; color: var(--text-secondary); font-size: 12px; }
  .legend-item { display: inline-flex; align-items: center; gap: 6px; }
  .legend-key { width: 14px; height: 2px; border-radius: 1px; display: inline-block; }
  .legend-key.rect { height: 8px; width: 10px; border-radius: 2px; }
  .tooltip {
    position: absolute; z-index: 5; min-width: 120px; max-width: 240px; pointer-events: none;
    background: var(--surface-1); color: var(--text-primary); border: 1px solid var(--border);
    border-radius: 8px; padding: 8px 10px; box-shadow: 0 6px 20px rgba(0, 0, 0, 0.12);
    font-size: 12px; opacity: 0; transform: translateY(2px); transition: opacity 80ms ease;
  }
  .tooltip.visible { opacity: 1; transform: translateY(0); }
  .tt-date { color: var(--text-muted); font-size: 11px; margin-bottom: 4px; }
  .tt-row { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; padding: 1px 0; }
  .tt-row .name { color: var(--text-secondary); display: inline-flex; align-items: center; gap: 6px; }
  .tt-row .key { width: 10px; height: 2px; border-radius: 1px; display: inline-block; }
  .tt-row .val { font-weight: 600; font-variant-numeric: tabular-nums; }
  .empty { display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 180px; gap: 8px; color: var(--text-muted); text-align: center; }
  .empty code { background: var(--surface-2); color: var(--text-secondary); padding: 4px 8px; border-radius: 6px; font-size: 12px; }
  .table-host { margin-top: 12px; overflow-x: auto; border-top: 1px solid var(--border); padding-top: 10px; }
  table { border-collapse: collapse; width: 100%; font-size: 12px; font-variant-numeric: tabular-nums; }
  th, td { text-align: left; padding: 5px 10px 5px 0; border-bottom: 1px solid var(--border); white-space: nowrap; }
  th { color: var(--text-muted); font-weight: 500; }
  td { color: var(--text-secondary); }
  td.num, th.num { text-align: right; padding-right: 14px; }
  .mini-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(330px, 1fr)); gap: 16px; }
  .mini-cell { min-width: 0; }
  .mini-title { display: flex; align-items: baseline; justify-content: space-between; gap: 8px; font-size: 12px; color: var(--text-secondary); }
  .mini-title .latest { color: var(--text-primary); font-weight: 600; font-variant-numeric: tabular-nums; }
  .meter-list { display: flex; flex-direction: column; gap: 14px; }
  .meter-head { display: flex; justify-content: space-between; gap: 12px; font-size: 12px; margin-bottom: 6px; }
  .meter-name { color: var(--text-secondary); }
  .meter-val { color: var(--text-primary); font-weight: 600; font-variant-numeric: tabular-nums; }
  .meter-track { height: 8px; border-radius: 999px; background: var(--series-1-weak); overflow: hidden; }
  .meter-fill { height: 100%; border-radius: 999px; background: var(--series-1); }
  .meter-fill.good { background: var(--status-good); }
  .meter-note { color: var(--text-muted); font-size: 11px; margin-top: 4px; }
  .status-note { display: inline-flex; align-items: center; gap: 4px; font-size: 11px; color: var(--text-muted); }
  .status-note.warn { color: var(--status-warning); }
  .status-note.bad { color: var(--status-critical); }
  .footnote { color: var(--text-muted); font-size: 11px; margin-top: 10px; }
  .footer { color: var(--text-muted); font-size: 11px; margin-top: 28px; display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap; }
  @media (max-width: 900px) {
    .page { padding: 20px 14px 40px; }
    .hero-grid { grid-template-columns: 1fr; }
    .grid { grid-template-columns: 1fr; }
    .wide { grid-column: auto; }
    .stat-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .hero-value { font-size: 48px; }
  }
</style>
</head>
<body data-palette="#2a78d6,#eb6834,#1baf7a,#eda100,#e87ba4,#008300,#6250d6,#e34948">
<div class="page">
  <header class="topbar">
    <div>
      <div class="brand">FitFuel</div>
      <h1>训练与饮食看板</h1>
      <p class="sub">更新于 __GENERATED_AT__ · 所有数据保存在本机 SQLite</p>
    </div>
    <button class="ghost-btn" id="theme-toggle" type="button">深色</button>
  </header>

  <div class="filterbar" role="group" aria-label="趋势范围">
    <span class="filter-label">趋势范围</span>
    <button class="filter-btn" type="button" data-days="30" aria-pressed="false">30 天</button>
    <button class="filter-btn" type="button" data-days="90" aria-pressed="true">90 天</button>
    <button class="filter-btn" type="button" data-days="365" aria-pressed="false">1 年</button>
    <button class="filter-btn" type="button" data-days="0" aria-pressed="false">全部</button>
  </div>

  <section class="hero-grid" aria-label="当前状态">
    <article class="card hero-card">
      <div>
        <div class="tile-label">当前体重</div>
        <div class="hero-value" id="hero-weight">—</div>
        <div class="delta" id="hero-delta"></div>
      </div>
      <div class="hero-meta" id="hero-meta">尚未记录</div>
    </article>
    <div class="stat-grid" id="stat-grid"></div>
  </section>

  <section class="grid">
    <article class="card chart-card">
      <div class="card-head">
        <div><h2>体重趋势</h2><p class="card-sub">kg · 每个点是一次记录</p></div>
        <button class="table-toggle" type="button" data-table="weight" aria-expanded="false">数据表</button>
      </div>
      <div class="chart-host" id="chart-weight"></div>
      <div class="table-host" id="table-weight" hidden></div>
    </article>

    <article class="card chart-card">
      <div class="card-head">
        <div><h2>体脂率趋势</h2><p class="card-sub">% · 最近一次体成分记录</p></div>
        <button class="table-toggle" type="button" data-table="bodyfat" aria-expanded="false">数据表</button>
      </div>
      <div class="chart-host" id="chart-bodyfat"></div>
      <div class="table-host" id="table-bodyfat" hidden></div>
    </article>

    <article class="card chart-card wide">
      <div class="card-head">
        <div><h2>力量 1RM 估算</h2><p class="card-sub">kg · 按 Epley 与 Brzycki 估算，点为当日最佳</p></div>
        <button class="table-toggle" type="button" data-table="strength" aria-expanded="false">数据表</button>
      </div>
      <div class="chart-host" id="chart-strength"></div>
      <div class="table-host" id="table-strength" hidden></div>
    </article>

    <article class="card chart-card">
      <div class="card-head">
        <div><h2>每日热量</h2><p class="card-sub">kcal · 柱为摄入，横线为目标</p></div>
        <button class="table-toggle" type="button" data-table="calories" aria-expanded="false">数据表</button>
      </div>
      <div class="chart-host" id="chart-calories"></div>
      <div class="table-host" id="table-calories" hidden></div>
    </article>

    <article class="card chart-card">
      <div class="card-head">
        <div><h2>每周训练量</h2><p class="card-sub">kg · 重量 × 次数，按自然周汇总</p></div>
        <button class="table-toggle" type="button" data-table="volume" aria-expanded="false">数据表</button>
      </div>
      <div class="chart-host" id="chart-volume"></div>
      <div class="table-host" id="table-volume" hidden></div>
    </article>

    <article class="card wide">
      <div class="card-head">
        <div><h2>围度变化</h2><p class="card-sub">cm · 每个部位独立刻度</p></div>
        <button class="table-toggle" type="button" data-table="measure" aria-expanded="false">数据表</button>
      </div>
      <div class="mini-grid" id="measure-grid"></div>
      <div class="table-host" id="table-measure" hidden></div>
    </article>

    <article class="card">
      <div class="card-head">
        <div><h2>今日宏量</h2><p class="card-sub" id="today-sub">—</p></div>
      </div>
      <div class="meter-list" id="today-macros"></div>
    </article>

    <article class="card">
      <div class="card-head">
        <div><h2>目标进度</h2><p class="card-sub">当前值与目标的距离</p></div>
      </div>
      <div class="meter-list" id="goals"></div>
    </article>

    <article class="card wide">
      <div class="card-head">
        <div><h2>最近训练</h2><p class="card-sub">区间内最近 8 次</p></div>
      </div>
      <div class="table-host" id="table-workouts" style="border-top:0; padding-top:0; margin-top:0"></div>
    </article>
  </section>

  <div class="footer">
    <span>FitFuel · 本地优先，不上传任何数据</span>
    <span>估算值仅供训练参考，不构成医疗或营养处方</span>
  </div>
</div>

<script id="fitfuel-data" type="application/json">__DATA_JSON__</script>
<script>
(function () {
  "use strict";
  const DATA = JSON.parse(document.getElementById("fitfuel-data").textContent);
  const NS = "http://www.w3.org/2000/svg";
  const state = { days: DATA.default_days || 90 };
  const fmtNum = (v, d = 1) => (v === null || v === undefined || Number.isNaN(Number(v)))
    ? "—"
    : Number(v).toLocaleString("zh-CN", { maximumFractionDigits: d });
  const signed = (v, d = 1) => (v > 0 ? "+" : "") + fmtNum(v, d);
  const toDate = (s) => new Date(s + "T00:00:00");
  const isoLocal = (d) => {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + day;
  };
  const shortDate = (s) => {
    const d = toDate(s);
    return (d.getMonth() + 1) + "/" + d.getDate();
  };
  const addDays = (s, n) => {
    const d = toDate(s);
    d.setDate(d.getDate() + n);
    return isoLocal(d);
  };
  const cutoff = () => {
    if (!state.days) return null;
    const d = new Date();
    d.setDate(d.getDate() - (state.days - 1));
    return isoLocal(d);
  };
  const inRange = (dateStr) => {
    const c = cutoff();
    return !c || dateStr >= c;
  };
  const cssVar = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const seriesColor = (slot) => cssVar("--series-" + slot) || cssVar("--series-1");
  const surface = () => cssVar("--surface-1");
  const inkSecondary = () => cssVar("--text-secondary");
  const inkMuted = () => cssVar("--text-muted");
  const gridColor = () => cssVar("--grid");
  const axisColor = () => cssVar("--axis");

  function svgEl(tag, attrs, parent) {
    const node = document.createElementNS(NS, tag);
    if (attrs) Object.keys(attrs).forEach((k) => node.setAttribute(k, attrs[k]));
    if (parent) parent.appendChild(node);
    return node;
  }
  function clear(el) { while (el.firstChild) el.removeChild(el.firstChild); }
  function el(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  function niceScale(min, max, count) {
    count = count || 4;
    if (!Number.isFinite(min) || !Number.isFinite(max)) { min = 0; max = 1; }
    if (min === max) { min -= 1; max += 1; }
    const span = max - min;
    const rawStep = span / count;
    const mag = Math.pow(10, Math.floor(Math.log10(rawStep)));
    const norm = rawStep / mag;
    const mult = norm >= 7.5 ? 10 : norm >= 3.5 ? 5 : norm >= 1.5 ? 2 : 1;
    const step = mult * mag;
    const lo = Math.floor(min / step) * step;
    const hi = Math.ceil(max / step) * step;
    const ticks = [];
    for (let v = lo; v <= hi + step * 1e-6; v += step) ticks.push(Number(v.toFixed(10)));
    return { lo: lo, hi: hi === lo ? lo + step : hi, step: step, ticks: ticks };
  }

  function emptyState(host, text, hint) {
    clear(host);
    const box = el("div", "empty");
    box.appendChild(el("p", null, text));
    if (hint) box.appendChild(el("code", null, hint));
    host.appendChild(box);
  }

  function makeTooltip(host) {
    const tip = el("div", "tooltip");
    tip.setAttribute("role", "status");
    tip.setAttribute("aria-live", "polite");
    host.appendChild(tip);
    return tip;
  }

  function fillTooltip(tip, dateStr, rows) {
    clear(tip);
    tip.appendChild(el("div", "tt-date", dateStr));
    rows.forEach((row) => {
      const line = el("div", "tt-row");
      const name = el("span", "name");
      if (row.color) {
        const key = el("span", "key");
        key.style.background = row.color;
        name.appendChild(key);
      }
      name.appendChild(document.createTextNode(row.label));
      line.appendChild(name);
      line.appendChild(el("span", "val", row.value));
      tip.appendChild(line);
    });
    tip.classList.add("visible");
  }

  function placeTooltip(tip, host, x, y) {
    const rect = host.getBoundingClientRect();
    const tipRect = tip.getBoundingClientRect();
    let left = x + 14;
    if (left + tipRect.width > rect.width - 4) left = x - tipRect.width - 14;
    left = Math.max(4, Math.min(left, rect.width - tipRect.width - 4));
    let top = y - tipRect.height - 10;
    if (top < 4) top = y + 14;
    top = Math.max(4, Math.min(top, rect.height - tipRect.height - 4));
    tip.style.left = left + "px";
    tip.style.top = top + "px";
  }

  function hideTooltip(tip) { tip.classList.remove("visible"); }

  function unionDates(seriesList) {
    const set = new Set();
    seriesList.forEach((s) => s.points.forEach((p) => set.add(p.date)));
    return Array.from(set).sort();
  }

  function renderLineChart(host, opts) {
    const series = opts.series.filter((s) => s.points.length);
    if (!series.length) {
      emptyState(host, opts.emptyText || "暂无数据", opts.emptyHint || "");
      return;
    }
    clear(host);
    if (series.length >= 2) {
      const legend = el("div", "legend");
      series.forEach((s) => {
        const item = el("span", "legend-item");
        const key = el("span", "legend-key");
        key.style.background = s.color;
        item.appendChild(key);
        item.appendChild(document.createTextNode(s.label));
        legend.appendChild(item);
      });
      host.appendChild(legend);
    }
    const tip = makeTooltip(host);
    const compact = !!opts.compact;
    const width = Math.max(240, host.clientWidth || 640);
    const height = opts.height || 240;
    const margin = {
      top: compact ? 10 : 14,
      right: compact ? 10 : (opts.right || 64),
      bottom: compact ? 22 : 30,
      left: compact ? 34 : (opts.left || 50)
    };
    const plotW = width - margin.left - margin.right;
    const plotH = height - margin.top - margin.bottom;
    const svg = svgEl("svg", {
      class: "chart-svg", width: width, height: height,
      viewBox: "0 0 " + width + " " + height, role: "img",
      "aria-label": opts.ariaLabel || opts.title || "趋势图", tabindex: "0"
    }, host);

    const allDates = unionDates(series);
    let t0 = toDate(allDates[0]).getTime();
    let t1 = toDate(allDates[allDates.length - 1]).getTime();
    if (t0 === t1) { t0 -= 86400000; t1 += 86400000; }
    const values = [];
    series.forEach((s) => s.points.forEach((p) => values.push(p.value)));
    let vMin = Math.min.apply(null, values);
    let vMax = Math.max.apply(null, values);
    if (opts.target && Number.isFinite(opts.target.value)) {
      vMin = Math.min(vMin, opts.target.value);
      vMax = Math.max(vMax, opts.target.value);
    }
    const pad = Math.max((vMax - vMin) * 0.08, 0.5);
    const scale = compact
      ? { lo: vMin - pad, hi: vMax + pad, ticks: vMin === vMax ? [vMin] : [vMin, vMax] }
      : niceScale(vMin - pad, vMax + pad, 4);
    const x = (dateStr) => margin.left + ((toDate(dateStr).getTime() - t0) / (t1 - t0)) * plotW;
    const y = (v) => margin.top + plotH - ((v - scale.lo) / (scale.hi - scale.lo)) * plotH;
    const axisFont = compact ? 10 : 11;

    scale.ticks.forEach((tick) => {
      const yy = y(tick);
      svgEl("line", { x1: margin.left, x2: margin.left + plotW, y1: yy, y2: yy, stroke: gridColor(), "stroke-width": 1 }, svg);
      svgEl("text", { x: margin.left - 6, y: yy + 3, "text-anchor": "end", fill: compact ? inkSecondary() : inkMuted(), "font-size": axisFont, "font-variant-numeric": "tabular-nums" }, svg)
        .textContent = fmtNum(tick, opts.decimals === 0 ? 0 : 1);
    });
    const tickCount = compact ? 2 : (width < 480 ? 3 : 5);
    const tickDates = [];
    if (allDates.length <= tickCount) {
      tickDates.push(...allDates);
    } else {
      for (let i = 0; i < tickCount; i++) {
        const idx = Math.round((i * (allDates.length - 1)) / (tickCount - 1));
        const candidate = allDates[idx];
        if (!tickDates.includes(candidate)) tickDates.push(candidate);
      }
    }
    tickDates.forEach((dateStr, i) => {
      const xx = x(dateStr);
      svgEl("text", {
        x: xx, y: height - 7,
        "text-anchor": i === 0 ? "start" : i === tickDates.length - 1 ? "end" : "middle",
        fill: inkMuted(), "font-size": axisFont
      }, svg).textContent = shortDate(dateStr);
    });
    svgEl("line", { x1: margin.left, x2: margin.left + plotW, y1: margin.top + plotH, y2: margin.top + plotH, stroke: axisColor(), "stroke-width": 1 }, svg);

    if (opts.target && Number.isFinite(opts.target.value)) {
      const yy = y(opts.target.value);
      svgEl("line", { x1: margin.left, x2: margin.left + plotW, y1: yy, y2: yy, stroke: inkMuted(), "stroke-width": 1, "stroke-dasharray": "4 5" }, svg);
      svgEl("text", { x: margin.left + 6, y: yy - 6, fill: inkSecondary(), "font-size": 11 }, svg)
        .textContent = (opts.target.label || "目标") + " " + fmtNum(opts.target.value, opts.decimals === 0 ? 0 : 1) + (opts.unit ? " " + opts.unit : "");
    }

    const endLabels = [];
    series.forEach((s) => {
      const pts = s.points;
      const d = pts.map((p, i) => (i === 0 ? "M" : "L") + x(p.date).toFixed(2) + " " + y(p.value).toFixed(2)).join(" ");
      svgEl("path", {
        d: d, fill: "none", stroke: s.color, "stroke-width": 2,
        "stroke-linecap": "round", "stroke-linejoin": "round"
      }, svg);
      const last = pts[pts.length - 1];
      const lx = x(last.date);
      const ly = y(last.value);
      svgEl("circle", { cx: lx, cy: ly, r: 4, fill: s.color, stroke: surface(), "stroke-width": 2 }, svg);
      endLabels.push({ x: lx, y: ly, text: fmtNum(last.value, opts.decimals === 0 ? 0 : 1), color: s.color, series: s });
    });
    endLabels.sort((a, b) => a.y - b.y);
    if (!compact) {
      for (let i = 0; i < endLabels.length; i++) {
        const label = endLabels[i];
        const collides = endLabels.some((other, j) => j !== i && Math.abs(other.y - label.y) < 14 && Math.abs(other.x - label.x) < 50);
        if (collides) continue;
        svgEl("text", {
          x: label.x + 9, y: label.y + 4, fill: inkSecondary(), "font-size": 11,
          "font-variant-numeric": "tabular-nums"
        }, svg).textContent = label.text;
      }
    }

    const hoverGroup = svgEl("g", null, svg);
    const hit = svgEl("rect", {
      x: margin.left, y: margin.top, width: plotW, height: plotH, fill: "transparent",
      style: "cursor: crosshair"
    }, svg);
    const dateMs = allDates.map((d) => toDate(d).getTime());

    function nearestIndex(px) {
      const t = t0 + ((px - margin.left) / plotW) * (t1 - t0);
      let best = 0;
      let bestDist = Infinity;
      for (let i = 0; i < dateMs.length; i++) {
        const dist = Math.abs(dateMs[i] - t);
        if (dist < bestDist) { bestDist = dist; best = i; }
      }
      return best;
    }

    function showAt(dateStr, px, py) {
      clear(hoverGroup);
      const xx = x(dateStr);
      svgEl("line", { x1: xx, x2: xx, y1: margin.top, y2: margin.top + plotH, stroke: axisColor(), "stroke-width": 1 }, hoverGroup);
      const rows = [];
      series.forEach((s) => {
        const point = s.points.find((p) => p.date === dateStr);
        if (point) {
          svgEl("circle", { cx: xx, cy: y(point.value), r: 4, fill: s.color, stroke: surface(), "stroke-width": 2 }, hoverGroup);
          rows.push({ label: s.label, value: fmtNum(point.value, opts.decimals === 0 ? 0 : 1) + (opts.unit ? " " + opts.unit : ""), color: s.color });
        } else {
          rows.push({ label: s.label, value: "—", color: s.color });
        }
      });
      fillTooltip(tip, dateStr, rows);
      placeTooltip(tip, host, px, py);
    }

    let activeIndex = allDates.length - 1;
    hit.addEventListener("pointermove", (event) => {
      const svgRect = svg.getBoundingClientRect();
      const hostRect = host.getBoundingClientRect();
      const offsetX = svgRect.left - hostRect.left;
      const pxSvg = event.clientX - svgRect.left;
      activeIndex = nearestIndex(pxSvg);
      const dateStr = allDates[activeIndex];
      showAt(dateStr, x(dateStr) + offsetX, event.clientY - hostRect.top);
    });
    hit.addEventListener("pointerleave", () => { clear(hoverGroup); hideTooltip(tip); });
    svg.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault();
      activeIndex = Math.max(0, Math.min(allDates.length - 1, activeIndex + (event.key === "ArrowRight" ? 1 : -1)));
      const dateStr = allDates[activeIndex];
      showAt(dateStr, x(dateStr), margin.top + plotH / 2);
    });
    svg.addEventListener("blur", () => { clear(hoverGroup); hideTooltip(tip); });
  }

  function renderBarChart(host, opts) {
    const data = opts.data || [];
    if (!data.length) {
      emptyState(host, opts.emptyText || "暂无数据", opts.emptyHint || "");
      return;
    }
    clear(host);
    const tip = makeTooltip(host);
    const width = Math.max(280, host.clientWidth || 640);
    const height = opts.height || 240;
    const margin = { top: 16, right: 18, bottom: 30, left: 54 };
    const plotW = width - margin.left - margin.right;
    const plotH = height - margin.top - margin.bottom;
    const svg = svgEl("svg", {
      class: "chart-svg", width: width, height: height, viewBox: "0 0 " + width + " " + height,
      role: "img", "aria-label": opts.ariaLabel || opts.title || "柱状图", tabindex: "0"
    }, host);
    const values = data.map((d) => d.value);
    let vMin = 0;
    let vMax = Math.max.apply(null, values);
    if (opts.target && Number.isFinite(opts.target.value)) vMax = Math.max(vMax, opts.target.value);
    const scale = niceScale(vMin, vMax * 1.08, 4);
    const band = plotW / data.length;
    const barW = Math.min(24, Math.max(2, band * 0.58));
    const y = (v) => margin.top + plotH - ((v - scale.lo) / (scale.hi - scale.lo)) * plotH;

    scale.ticks.forEach((tick) => {
      const yy = y(tick);
      svgEl("line", { x1: margin.left, x2: margin.left + plotW, y1: yy, y2: yy, stroke: gridColor(), "stroke-width": 1 }, svg);
      svgEl("text", { x: margin.left - 8, y: yy + 4, "text-anchor": "end", fill: inkMuted(), "font-size": 11, "font-variant-numeric": "tabular-nums" }, svg)
        .textContent = fmtNum(tick, 0);
    });
    svgEl("line", { x1: margin.left, x2: margin.left + plotW, y1: margin.top + plotH, y2: margin.top + plotH, stroke: axisColor(), "stroke-width": 1 }, svg);

    if (opts.target && Number.isFinite(opts.target.value)) {
      const yy = y(opts.target.value);
      svgEl("line", { x1: margin.left, x2: margin.left + plotW, y1: yy, y2: yy, stroke: inkMuted(), "stroke-width": 1, "stroke-dasharray": "4 5" }, svg);
      svgEl("text", { x: margin.left + 6, y: yy - 6, fill: inkSecondary(), "font-size": 11 }, svg)
        .textContent = (opts.target.label || "目标") + " " + fmtNum(opts.target.value, 0);
    }

    const slotColor = seriesColor(1);
    const marks = [];
    data.forEach((d, i) => {
      const x0 = margin.left + i * band + (band - barW) / 2;
      const y0 = y(d.value);
      const h = margin.top + plotH - y0;
      let bar = null;
      if (h > 0.2) {
        const r = Math.min(4, h, barW / 2);
        const x1 = x0 + barW;
        const yb = margin.top + plotH;
        const path = "M" + x0 + " " + yb + " L" + x0 + " " + (y0 + r) +
          " Q" + x0 + " " + y0 + " " + (x0 + r) + " " + y0 +
          " L" + (x1 - r) + " " + y0 + " Q" + x1 + " " + y0 + " " + x1 + " " + (y0 + r) +
          " L" + x1 + " " + yb + " Z";
        bar = svgEl("path", { d: path, fill: slotColor, "fill-opacity": "0.92" }, svg);
      }
      marks.push(bar);
    });

    const overlay = svgEl("rect", {
      x: margin.left, y: margin.top, width: plotW, height: plotH,
      fill: "transparent", style: "cursor: pointer"
    }, svg);
    let active = -1;
    function clearActive() {
      if (active >= 0 && marks[active]) marks[active].setAttribute("fill-opacity", "0.92");
      active = -1;
    }
    function activate(index) {
      if (index < 0 || index >= data.length) return;
      if (index !== active) {
        clearActive();
        active = index;
        if (marks[index]) marks[index].setAttribute("fill-opacity", "0.72");
      }
      const d = data[index];
      const svgRect = svg.getBoundingClientRect();
      const hostRect = host.getBoundingClientRect();
      const offsetX = svgRect.left - hostRect.left;
      const offsetY = svgRect.top - hostRect.top;
      const px = margin.left + index * band + band / 2;
      fillTooltip(tip, d.label || d.date, [
        { label: opts.seriesLabel || "数值", value: fmtNum(d.value, 0) + (opts.unit ? " " + opts.unit : ""), color: slotColor }
      ]);
      placeTooltip(tip, host, px + offsetX, Math.max(margin.top, y(d.value)) + offsetY);
    }
    overlay.addEventListener("pointermove", (event) => {
      const rect = svg.getBoundingClientRect();
      const index = Math.floor((event.clientX - rect.left - margin.left) / band);
      activate(index);
    });
    overlay.addEventListener("pointerleave", () => { clearActive(); hideTooltip(tip); });
    svg.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      event.preventDefault();
      const step = event.key === "ArrowRight" ? 1 : -1;
      const index = active < 0 ? 0 : Math.max(0, Math.min(data.length - 1, active + step));
      activate(index);
    });
    svg.addEventListener("blur", () => { clearActive(); hideTooltip(tip); });

    const labelEvery = Math.max(1, Math.ceil(data.length / (width < 480 ? 4 : 7)));
    data.forEach((d, i) => {
      if (i % labelEvery !== 0 && i !== data.length - 1) return;
      const xx = margin.left + i * band + band / 2;
      svgEl("text", { x: xx, y: height - 8, "text-anchor": "middle", fill: inkMuted(), "font-size": 11 }, svg)
        .textContent = d.label || shortDate(d.date);
    });
  }

  function renderMiniLine(host, title, points, unit) {
    clear(host);
    const head = el("div", "mini-title");
    head.appendChild(el("span", null, title));
    const latest = points[points.length - 1];
    head.appendChild(el("span", "latest", fmtNum(latest.value, 1) + " " + unit));
    host.appendChild(head);
    const chartHost = el("div", "chart-host mini");
    host.appendChild(chartHost);
    renderLineChart(chartHost, {
      series: [{ label: title, color: seriesColor(1), points: points }],
      unit: unit,
      decimals: 1,
      height: 160,
      compact: true,
      ariaLabel: title + "趋势",
      emptyText: "暂无数据"
    });
  }

  function buildLineTable(host, series, unit) {
    clear(host);
    if (!series.length) return;
    const dates = unionDates(series);
    const map = {};
    series.forEach((s) => { map[s.label] = new Map(s.points.map((p) => [p.date, p.value])); });
    const table = el("table");
    const thead = el("thead");
    const hr = el("tr");
    hr.appendChild(el("th", null, "日期"));
    series.forEach((s) => hr.appendChild(el("th", "num", s.label + (unit ? " (" + unit + ")" : ""))));
    thead.appendChild(hr);
    table.appendChild(thead);
    const tbody = el("tbody");
    dates.forEach((dateStr) => {
      const tr = el("tr");
      tr.appendChild(el("td", null, dateStr));
      series.forEach((s) => tr.appendChild(el("td", "num", map[s.label].has(dateStr) ? fmtNum(map[s.label].get(dateStr), 1) : "—")));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    host.appendChild(table);
  }

  function buildBarTable(host, data, unit) {
    clear(host);
    if (!data.length) return;
    const table = el("table");
    const thead = el("thead");
    const hr = el("tr");
    hr.appendChild(el("th", null, "日期"));
    hr.appendChild(el("th", "num", "数值" + (unit ? " (" + unit + ")" : "")));
    thead.appendChild(hr);
    table.appendChild(thead);
    const tbody = el("tbody");
    data.forEach((d) => {
      const tr = el("tr");
      tr.appendChild(el("td", null, d.label || d.date));
      tr.appendChild(el("td", "num", fmtNum(d.value, 0)));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    host.appendChild(table);
  }

  function buildMeasureTable(host, series) {
    clear(host);
    const rows = [];
    series.forEach((s) => s.points.forEach((p) => rows.push({ date: p.date, label: s.label, value: p.value })));
    rows.sort((a, b) => a.date.localeCompare(b.date) || a.label.localeCompare(b.label));
    if (!rows.length) return;
    const table = el("table");
    const thead = el("thead");
    const hr = el("tr");
    ["日期", "部位", "数值 (cm)"].forEach((h, i) => hr.appendChild(el("th", i === 2 ? "num" : null, h)));
    thead.appendChild(hr);
    table.appendChild(thead);
    const tbody = el("tbody");
    rows.forEach((r) => {
      const tr = el("tr");
      tr.appendChild(el("td", null, r.date));
      tr.appendChild(el("td", null, r.label));
      tr.appendChild(el("td", "num", fmtNum(r.value, 1)));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    host.appendChild(table);
  }

  function buildVolumeTable(host, data) {
    clear(host);
    if (!data.length) return;
    const table = el("table");
    const thead = el("thead");
    const hr = el("tr");
    ["周起始", "训练量 (kg)", "组数", "训练次数"].forEach((h, i) => hr.appendChild(el("th", i === 0 ? null : "num", h)));
    thead.appendChild(hr);
    table.appendChild(thead);
    const tbody = el("tbody");
    data.forEach((d) => {
      const tr = el("tr");
      tr.appendChild(el("td", null, d.week_start));
      tr.appendChild(el("td", "num", fmtNum(d.volume_kg, 0)));
      tr.appendChild(el("td", "num", d.sets));
      tr.appendChild(el("td", "num", d.workouts));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    host.appendChild(table);
  }

  function weeklyFromSessions(sessions) {
    const buckets = {};
    sessions.forEach((s) => {
      const d = toDate(s.date);
      const monday = addDays(s.date, -((d.getDay() + 6) % 7));
      if (!buckets[monday]) buckets[monday] = { week_start: monday, volume_kg: 0, sets: 0, workouts: 0, names: new Set() };
      buckets[monday].volume_kg += s.volume_kg || 0;
      buckets[monday].sets += s.set_count || 0;
      buckets[monday].workouts += 1;
      buckets[monday].names.add(s.id);
    });
    return Object.keys(buckets).sort().map((k) => buckets[k]).map((b) => ({
      week_start: b.week_start,
      volume_kg: Math.round(b.volume_kg * 10) / 10,
      sets: b.sets,
      workouts: b.workouts
    }));
  }

  function meterRow(name, valueText, ratio, note, good) {
    const box = el("div");
    const head = el("div", "meter-head");
    head.appendChild(el("span", "meter-name", name));
    head.appendChild(el("span", "meter-val", valueText));
    box.appendChild(head);
    const track = el("div", "meter-track");
    const fill = el("div", "meter-fill" + (good ? " good" : ""));
    fill.style.width = Math.max(0, Math.min(100, ratio * 100)).toFixed(1) + "%";
    track.appendChild(fill);
    box.appendChild(track);
    if (note) box.appendChild(el("div", "meter-note", note));
    return box;
  }

  function renderHero(model) {
    const weights = model.metrics.filter((m) => m.weight_kg !== null && m.weight_kg !== undefined);
    const hero = document.getElementById("hero-weight");
    clear(hero);
    const latest = weights.length ? weights[weights.length - 1] : null;
    if (!latest) {
      hero.textContent = "—";
    } else {
      hero.appendChild(document.createTextNode(fmtNum(latest.weight_kg, 1)));
      hero.appendChild(el("span", "unit", "kg"));
    }
    const deltaEl = document.getElementById("hero-delta");
    clear(deltaEl);
    deltaEl.className = "delta";
    if (weights.length >= 2) {
      const first = weights[0];
      const delta = latest.weight_kg - first.weight_kg;
      const goal = (DATA.profile && DATA.profile.goal_type) || "maintain";
      const goodDirection = goal === "cut" ? -1 : goal === "bulk" ? 1 : 0;
      if (goodDirection && Math.abs(delta) >= 0.05) {
        deltaEl.classList.add(delta * goodDirection > 0 ? "good" : "bad");
      }
      const arrow = delta > 0 ? "▲" : delta < 0 ? "▼" : "•";
      deltaEl.appendChild(document.createTextNode(arrow + " " + signed(delta, 1) + " kg"));
      deltaEl.appendChild(el("span", null, "较区间起点"));
    } else {
      deltaEl.appendChild(document.createTextNode("记录两次以上后可看变化"));
    }
    const meta = document.getElementById("hero-meta");
    const bits = [];
    if (DATA.profile.height_cm) bits.push("身高 " + fmtNum(DATA.profile.height_cm, 0) + " cm");
    if (latest && latest.bmi) bits.push("BMI " + fmtNum(latest.bmi, 1));
    if (DATA.profile.age) bits.push(DATA.profile.age + " 岁");
    meta.textContent = bits.length ? bits.join(" · ") : "尚未完善个人档案";
  }

  function renderStats() {
    const grid = document.getElementById("stat-grid");
    clear(grid);
    const latest = DATA.latest || {};
    const targets = DATA.targets && DATA.targets.available ? DATA.targets.targets : null;
    const today = (DATA.today_summary && DATA.today_summary.totals) || {};
    const goals = DATA.goals || [];
    const goalWeight = goals.find((g) => g.kind === "weight");

    const tiles = [
      { label: "体脂率", value: latest.body_fat_pct, unit: "%", sub: latest.date ? "记录于 " + latest.date : "尚无记录" },
      { label: "骨骼肌量", value: latest.skeletal_muscle_kg, unit: "kg", sub: latest.date ? "记录于 " + latest.date : "尚无记录" },
      { label: "今日热量", value: today.kcal, unit: "kcal", sub: targets ? "目标 " + fmtNum(targets.kcal, 0) + " kcal" : "未设置目标" },
      { label: "今日蛋白质", value: today.protein, unit: "g", sub: targets ? "目标 " + fmtNum(targets.protein, 0) + " g" : "未设置目标" }
    ];
    tiles.forEach((tile) => {
      const card = el("article", "card stat");
      card.appendChild(el("div", "tile-label", tile.label));
      const value = el("div", "stat-value");
      value.appendChild(document.createTextNode(tile.value === null || tile.value === undefined ? "—" : fmtNum(tile.value, 1)));
      if (tile.value !== null && tile.value !== undefined) value.appendChild(el("span", "unit", tile.unit));
      card.appendChild(value);
      card.appendChild(el("div", "stat-sub", tile.sub));
      grid.appendChild(card);
    });
    if (goalWeight && goalWeight.target_value) {
      // 仅用于无障碍描述的补充信息，不额外占视觉空间
      grid.setAttribute("aria-label", "当前状态：目标体重 " + goalWeight.target_value + " kg");
    }
  }

  function buildModel() {
    const c = cutoff();
    const metrics = DATA.metrics.filter((m) => !c || m.date >= c);
    const measurementSeries = DATA.measurement_series
      .map((s) => ({ site: s.site, label: s.label, points: s.points.filter((p) => !c || p.date >= c) }))
      .filter((s) => s.points.length);
    const strengthOrder = { bench: 1, squat: 2, deadlift: 3, ohp: 4, row: 5, pullup: 6 };
    const known = DATA.strength_series
      .map((s) => ({ lift: s.lift, label: s.label, points: s.points.filter((p) => !c || p.date >= c) }))
      .filter((s) => s.points.length && strengthOrder[s.lift])
      .sort((a, b) => strengthOrder[a.lift] - strengthOrder[b.lift])
      .map((s) => ({ ...s, slot: strengthOrder[s.lift] }));
    const custom = DATA.strength_series
      .map((s) => ({ lift: s.lift, label: s.label, points: s.points.filter((p) => !c || p.date >= c) }))
      .filter((s) => s.points.length && !strengthOrder[s.lift])
      .sort((a, b) => a.lift.localeCompare(b.lift))
      .slice(0, 2)
      .map((s, i) => ({ ...s, slot: 7 + i }));
    const strengthSeries = known.concat(custom).map((s) => ({ ...s, color: seriesColor(s.slot) }));
    const nutritionDaily = DATA.nutrition_daily.filter((d) => !c || d.date >= c);
    const sessions = DATA.workout_sessions.filter((s) => !c || s.date >= c);
    return { metrics, measurementSeries, strengthSeries, nutritionDaily, sessions };
  }

  function renderWeight(model) {
    const points = model.metrics
      .filter((m) => m.weight_kg !== null && m.weight_kg !== undefined)
      .map((m) => ({ date: m.date, value: m.weight_kg }));
    const goal = (DATA.goals || []).find((g) => g.kind === "weight");
    renderLineChart(document.getElementById("chart-weight"), {
      series: [{ label: "体重", color: seriesColor(1), points }],
      unit: "kg",
      title: "体重趋势",
      target: goal ? { value: goal.target_value, label: "目标" } : null,
      emptyText: "还没有体重记录",
      emptyHint: "python3 -m fitfuel weight add 72.5"
    });
    buildLineTable(document.getElementById("table-weight"), [{ label: "体重", points }], "kg");
  }

  function renderBodyFat(model) {
    const points = model.metrics
      .filter((m) => m.body_fat_pct !== null && m.body_fat_pct !== undefined)
      .map((m) => ({ date: m.date, value: m.body_fat_pct }));
    const goal = (DATA.goals || []).find((g) => g.kind === "body_fat");
    renderLineChart(document.getElementById("chart-bodyfat"), {
      series: [{ label: "体脂率", color: seriesColor(1), points }],
      unit: "%",
      title: "体脂率趋势",
      target: goal ? { value: goal.target_value, label: "目标" } : null,
      emptyText: "还没有体脂率记录",
      emptyHint: "python3 -m fitfuel weight add 72.5 --body-fat 18"
    });
    buildLineTable(document.getElementById("table-bodyfat"), [{ label: "体脂率", points }], "%");
  }

  function renderStrength(model) {
    const series = model.strengthSeries.map((s) => ({ label: s.label, color: s.color, points: s.points }));
    renderLineChart(document.getElementById("chart-strength"), {
      series,
      unit: "kg",
      title: "力量 1RM 估算",
      decimals: 0,
      emptyText: "还没有力量记录",
      emptyHint: "python3 -m fitfuel strength add bench 80 5"
    });
    buildLineTable(document.getElementById("table-strength"), series, "kg");
  }

  function renderCalories(model) {
    let daily = model.nutritionDaily.filter((d) => d.kcal !== null && d.kcal !== undefined);
    let data;
    let subtitle = "每日摄入，横线为目标";
    if (daily.length > 60) {
      const buckets = {};
      daily.forEach((d) => {
        const dt = toDate(d.date);
        const monday = addDays(d.date, -((dt.getDay() + 6) % 7));
        if (!buckets[monday]) buckets[monday] = { date: monday, label: shortDate(monday) + " 周", sum: 0, n: 0 };
        buckets[monday].sum += d.kcal;
        buckets[monday].n += 1;
      });
      data = Object.keys(buckets).sort().map((k) => ({
        date: buckets[k].date,
        label: buckets[k].label,
        value: Math.round(buckets[k].sum / buckets[k].n)
      }));
      subtitle = "周均摄入，横线为每日目标";
    } else {
      data = daily.map((d) => ({ date: d.date, label: shortDate(d.date), value: d.kcal }));
    }
    const target = DATA.targets && DATA.targets.available ? DATA.targets.targets.kcal : null;
    renderBarChart(document.getElementById("chart-calories"), {
      data,
      unit: "kcal",
      title: "每日热量",
      target: target ? { value: target, label: "目标" } : null,
      seriesLabel: daily.length > 60 ? "周均" : "摄入",
      emptyText: "还没有饮食记录",
      emptyHint: "python3 -m fitfuel meal add --type lunch --item 鸡胸肉:150"
    });
    buildBarTable(document.getElementById("table-calories"), data, "kcal");
    const sub = document.querySelector("#chart-calories")?.closest(".card")?.querySelector(".card-sub");
    if (sub) sub.textContent = subtitle;
  }

  function renderVolume(model) {
    const data = weeklyFromSessions(model.sessions).map((w) => ({
      date: w.week_start,
      label: shortDate(w.week_start),
      value: w.volume_kg,
      sets: w.sets,
      workouts: w.workouts
    }));
    renderBarChart(document.getElementById("chart-volume"), {
      data,
      unit: "kg",
      title: "每周训练量",
      seriesLabel: "训练量",
      emptyText: "还没有训练记录",
      emptyHint: "python3 -m fitfuel workout add --set \"卧推 80 5 @8\""
    });
    const host = document.getElementById("table-volume");
    clear(host);
    if (data.length) {
      const table = el("table");
      const thead = el("thead");
      const hr = el("tr");
      ["周起始", "训练量 (kg)", "组数", "训练次数"].forEach((h, i) => hr.appendChild(el("th", i === 0 ? null : "num", h)));
      thead.appendChild(hr);
      table.appendChild(thead);
      const tbody = el("tbody");
      data.forEach((d) => {
        const tr = el("tr");
        tr.appendChild(el("td", null, d.date));
        tr.appendChild(el("td", "num", fmtNum(d.value, 0)));
        tr.appendChild(el("td", "num", d.sets));
        tr.appendChild(el("td", "num", d.workouts));
        tbody.appendChild(tr);
      });
      table.appendChild(tbody);
      host.appendChild(table);
    }
  }

  function renderMeasurements(model) {
    const grid = document.getElementById("measure-grid");
    clear(grid);
    if (!model.measurementSeries.length) {
      emptyState(grid, "还没有围度记录", "python3 -m fitfuel measure add --waist 82 --chest 100");
      buildMeasureTable(document.getElementById("table-measure"), []);
      return;
    }
    model.measurementSeries.forEach((s) => {
      const cell = el("div", "mini-cell");
      grid.appendChild(cell);
      renderMiniLine(cell, s.label, s.points, "cm");
    });
    buildMeasureTable(document.getElementById("table-measure"), model.measurementSeries);
  }

  function renderTodayMacros() {
    const host = document.getElementById("today-macros");
    clear(host);
    const totals = (DATA.today_summary && DATA.today_summary.totals) || {};
    const targetInfo = DATA.targets || {};
    const targets = targetInfo.available ? targetInfo.targets : null;
    document.getElementById("today-sub").textContent = DATA.today || "";
    if (!DATA.today_summary || !(DATA.today_summary.meals || []).length) {
      host.appendChild(el("div", "meter-note", "今天还没有饮食记录"));
      return;
    }
    const rows = [
      { key: "kcal", label: "热量", unit: "kcal", target: targets ? targets.kcal : null },
      { key: "protein", label: "蛋白质", unit: "g", target: targets ? targets.protein : null },
      { key: "carbs", label: "碳水", unit: "g", target: targets ? targets.carbs : null },
      { key: "fat", label: "脂肪", unit: "g", target: targets ? targets.fat : null }
    ];
    rows.forEach((row) => {
      const value = Number(totals[row.key] || 0);
      const ratio = row.target ? value / row.target : 0;
      const over = row.target && value > row.target * 1.05;
      const text = fmtNum(value, row.key === "kcal" ? 0 : 1) + (row.target ? " / " + fmtNum(row.target, 0) : "") + " " + row.unit;
      const note = row.target
        ? (over ? "超出目标 " + fmtNum(value - row.target, 0) + " " + row.unit : "还剩 " + fmtNum(row.target - value, 0) + " " + row.unit)
        : "未设置目标";
      const box = meterRow(row.label, text, row.target ? Math.min(ratio, 1) : 0, note, false);
      if (over) {
        const noteEl = box.querySelector(".meter-note");
        noteEl.className = "status-note warn";
        noteEl.textContent = "! " + note;
      }
      host.appendChild(box);
    });
  }

  function renderGoals() {
    const host = document.getElementById("goals");
    clear(host);
    const goals = DATA.goals || [];
    if (!goals.length) {
      host.appendChild(el("div", "meter-note", "还没有设置目标"));
      host.appendChild(el("div", "footnote", "例如：python3 -m fitfuel goal set weight 68 --date 2027-03-01"));
      return;
    }
    goals.forEach((goal) => {
      const current = goal.current_value;
      const target = goal.target_value;
      const unit = goal.unit || "";
      const ratio = goal.progress === null || goal.progress === undefined ? 0 : goal.progress;
      let note;
      if (goal.achieved) {
        note = "已达成";
      } else if (goal.progress === null || goal.progress === undefined) {
        note = "需要至少一次对应记录";
      } else if (goal.target_date) {
        note = "目标日期 " + goal.target_date;
      } else {
        note = "还差 " + fmtNum(Math.abs((current || 0) - target), 1) + " " + unit;
      }
      const text = (current === null || current === undefined ? "—" : fmtNum(current, 1)) + " / " + fmtNum(target, 1) + " " + unit;
      const box = meterRow(goal.label, text, ratio, note, goal.achieved);
      host.appendChild(box);
    });
  }

  function renderWorkouts(model) {
    const host = document.getElementById("table-workouts");
    clear(host);
    const sessions = model.sessions.slice().sort((a, b) => b.date.localeCompare(a.date)).slice(0, 8);
    if (!sessions.length) {
      emptyState(host, "区间内还没有训练记录", "python3 -m fitfuel workout add --name 推日 --set \"卧推 80 5 @8\"");
      return;
    }
    const table = el("table");
    const thead = el("thead");
    const hr = el("tr");
    ["日期", "训练", "动作", "组数", "训练量 (kg)"].forEach((h, i) => hr.appendChild(el("th", i >= 2 ? "num" : null, h)));
    thead.appendChild(hr);
    table.appendChild(thead);
    const tbody = el("tbody");
    sessions.forEach((s) => {
      const tr = el("tr");
      tr.appendChild(el("td", null, s.date));
      tr.appendChild(el("td", null, s.name || "未命名训练"));
      tr.appendChild(el("td", "num", s.exercise_count));
      tr.appendChild(el("td", "num", s.set_count));
      tr.appendChild(el("td", "num", fmtNum(s.volume_kg, 0)));
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    host.appendChild(table);
  }

  function render(rangeOnly) {
    const model = buildModel();
    renderHero(model);
    if (!rangeOnly) renderStats();
    renderWeight(model);
    renderBodyFat(model);
    renderStrength(model);
    renderCalories(model);
    renderVolume(model);
    renderMeasurements(model);
    renderTodayMacros();
    renderGoals();
    renderWorkouts(model);
  }

  function wireTables() {
    document.querySelectorAll(".table-toggle").forEach((btn) => {
      btn.addEventListener("click", () => {
        const key = btn.getAttribute("data-table");
        const host = document.getElementById("table-" + key);
        if (!host) return;
        const open = host.hidden;
        host.hidden = !open;
        btn.setAttribute("aria-expanded", String(open));
        btn.textContent = open ? "隐藏数据表" : "数据表";
      });
    });
  }

  function wireFilters() {
    const buttons = Array.from(document.querySelectorAll(".filter-btn"));
    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        state.days = Number(btn.getAttribute("data-days")) || 0;
        buttons.forEach((b) => b.setAttribute("aria-pressed", String(b === btn)));
        render(true);
      });
    });
  }

  function wireTheme() {
    const btn = document.getElementById("theme-toggle");
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const current = () => document.documentElement.dataset.theme || (media.matches ? "dark" : "light");
    const sync = () => { btn.textContent = current() === "dark" ? "浅色" : "深色"; };
    let saved = null;
    try { saved = localStorage.getItem("fitfuel-theme"); } catch (e) { saved = null; }
    if (saved) document.documentElement.dataset.theme = saved;
    sync();
    btn.addEventListener("click", () => {
      const next = current() === "dark" ? "light" : "dark";
      document.documentElement.dataset.theme = next;
      try { localStorage.setItem("fitfuel-theme", next); } catch (e) { /* 文件模式下可能不可用 */ }
      sync();
      render(false);
    });
    media.addEventListener("change", () => {
      if (!document.documentElement.dataset.theme) { sync(); render(false); }
    });
  }

  let resizeTimer = null;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => render(false), 160);
  });

  wireTheme();
  wireTables();
  wireFilters();
  render(false);
})();
</script>
</body>
</html>
"""


def generate_dashboard(con, days: int = 90, out_path: str | Path | None = None) -> Path:
    data = dashboard_data(con, default_days=days)
    generated = data.get("generated_at", "").replace("T", " ")[:16]
    html = (
        HTML_TEMPLATE.replace("__GENERATED_AT__", generated)
        .replace("__DATA_JSON__", json_escape_for_html(data))
    )
    path = Path(out_path) if out_path else dashboard_path()
    ensure_parent(path)
    path.write_text(html, encoding="utf-8")
    return path
