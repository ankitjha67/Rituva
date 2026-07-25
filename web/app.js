/* Rituva PWA — vanilla JS client for the FastAPI backend (PRD §17, Phase D).
   Served same-origin from /app, so fetch('/plans') etc. hit the live API.
   Every number shown comes from the API (Knowledge DB); the client invents nothing. */
'use strict';

const $ = (s, r = document) => r.querySelector(s);
async function api(path, opts) {
  const r = await fetch(path, { headers: { 'Content-Type': 'application/json' }, ...opts });
  if (!r.ok) throw new Error(`${path} → ${r.status}`);
  return r.json();
}

const state = { memberId: 'aarav', ctx: null, members: [], member: null,
                targets: null, anthro: null, plan: null, day: null, view: 'today' };

const SLOT_EMOJI = { breakfast: '🥣', lunch: '🍚', dinner: '🫓', snack1: '🥜', snack2: '🍎' };
const MACROS = [['protein', 'protein_g', '--p'], ['carb', 'carb_g', '--c'],
                ['fat', 'fat_g', '--f'], ['fibre', 'fibre_g', '--fib']];

/* ---------- boot ---------- */
async function boot() {
  try {
    state.ctx = await api('/context');
    state.members = await api('/members');
    await loadMember();
    render();
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('/app/sw.js').catch(() => {});
  } catch (e) {
    $('#view').innerHTML = `<div class="err">Couldn't reach the Rituva API (${e.message}).<br>
      Start it with <code>uvicorn rituva.api:app</code> and reload.</div>`;
  }
}
async function loadMember() {
  const id = state.memberId;
  state.member = await api(`/members/${id}`);
  const t = await api(`/members/${id}/targets`);
  state.targets = t.targets; state.anthro = t.anthropometry;
  state.plan = await api('/plans', { method: 'POST',
    body: JSON.stringify({ member_id: id, days: 7, start: state.ctx.today }) });
  state.day = state.plan.days.find((d) => d.date === state.ctx.today) || state.plan.days[0];
}

/* ---------- helpers ---------- */
const cap = (s) => s ? s[0].toUpperCase() + s.slice(1) : s;
const mainComp = (e) => (e.slot === 'lunch' || e.slot === 'dinner') && e.components[1]
  ? e.components[1] : e.components[0];
function ring(pct, val, label, colorVar) {
  const R = 46, C = 2 * Math.PI * R, off = C * (1 - Math.min(pct, 1));
  return `<div class="ringwrap" style="width:112px;height:112px">
    <svg width="112" height="112" viewBox="0 0 112 112">
      <circle cx="56" cy="56" r="${R}" fill="none" stroke="var(--surface2)" stroke-width="10"/>
      <circle cx="56" cy="56" r="${R}" fill="none" stroke="var(${colorVar})" stroke-width="10"
        stroke-linecap="round" transform="rotate(-90 56 56)"
        stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${off.toFixed(1)}"/>
    </svg><div class="rc"><div class="big" style="font-size:22px">${val}</div>
    <div class="label">${label}</div></div></div>`;
}
function macroBars() {
  const T = state.targets, tot = state.day.totals;
  return MACROS.map(([k, tk, cv]) => {
    const cur = tot[k] || 0, tgt = T[tk] || 1, pct = Math.min(100, Math.round(cur / tgt * 100));
    return `<div style="margin-top:8px"><div class="between" style="font-size:11px">
      <span class="muted">${cap(k)}</span><b>${Math.round(cur)} / ${Math.round(tgt)} g</b></div>
      <div class="bar"><i style="width:${pct}%;background:var(${cv})"></i></div></div>`;
  }).join('');
}

/* ---------- top bar + nav ---------- */
function topbar() {
  const c = state.ctx, name = state.member ? state.member.name : '…';
  $('#topbar').innerHTML = `<div class="tb-row">
    <div class="avatar">${(name[0] || 'R')}</div>
    <div style="flex:1"><div class="hi">${c ? c.greeting : 'Rituva'}, ${name}</div>
      <div class="sub">${c ? c.today : ''} · next meal ${c ? c.current_slot : ''}</div></div>
    <span class="pill season">☀︎ ${c ? cap(c.season) : ''}</span></div>`;
}
const NAV = [['today', 'Today', 'M3 11l9-8 9 8M5 10v10h14V10'],
  ['plan', 'Plan', 'M3 4h18v17H3zM8 2v4M16 2v4M3 10h18'],
  ['health', 'Health', 'M20 8a4 4 0 0 0-7-2 4 4 0 0 0-7 2c0 5 7 9 7 9s7-4 7-9z'],
  ['insights', 'Insights', 'M4 19V10M9 19V5M14 19v-7M19 19V8'],
  ['profile', 'Profile', 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21c0-4 4-6 8-6s8 2 8 6']];
function nav() {
  $('#nav').innerHTML = NAV.map(([id, lbl, d]) => `<button class="navbtn ${state.view === id ? 'on' : ''}"
    data-action="nav" data-arg="${id}"><span class="ic"><svg viewBox="0 0 24 24"><path d="${d}"/></svg></span>${lbl}</button>`).join('');
}

/* ---------- views ---------- */
function todayView() {
  const d = state.day, T = state.targets;
  const kpct = (d.totals.kcal || 0) / (T.kcal || 1);
  const cites = (state.plan.provenance && state.plan.provenance.citations) || [];
  const why = cites[0];
  const meals = d.entries.map((e) => {
    const names = e.components.map((c) => c.name).join(' + ');
    const mc = mainComp(e); const reg = mc && mc.region;
    return `<button class="meal" data-action="swap" data-arg="${mc ? mc.recipe_id : ''}" style="margin-top:8px">
      <div class="thumb">${SLOT_EMOJI[e.slot] || '🍽️'}</div>
      <div style="flex:1"><div class="mtitle">${names}</div>
        <div class="mmeta">${cap(e.slot)} · ${Math.round(e.nutrients.kcal)} kcal</div></div>
      ${reg ? `<span class="tag ${reg}">${reg[0]}</span>` : ''}</button>`;
  }).join('');
  return `<div class="card">
    <div class="row" style="gap:16px">${ring(kpct, Math.round(d.totals.kcal), 'of ' + T.kcal + ' kcal', '--gold')}
      <div style="flex:1">${macroBars()}</div></div>
    <div class="between" style="margin-top:12px">
      <span class="pill ${d.validation.in_tolerance ? 'good' : 'warn'}">DQS ${d.validation.dqs} · ${d.validation.in_tolerance ? 'on target' : 'review'}</span>
      <span class="pill season">🌱 ${cap(d.season)}</span></div></div>
  ${why ? `<div class="card" style="margin-top:10px"><div class="row"><span class="cite">◆ cited</span>
     <div style="font-size:11px" class="muted">${why.text} — <b style="color:var(--ink)">${why.source}</b></div></div></div>` : ''}
  <div class="h2">Today's menu · tap to swap</div>${meals}
  <button class="btn ghost" data-action="regen" style="margin-top:12px">↻ Regenerate week</button>`;
}

function planView() {
  const rows = state.plan.days.map((d) => `<div class="card" style="margin-top:8px">
    <div class="between"><b style="font-size:13px">${d.date}${d.date === state.ctx.today ? ' · today' : ''}</b>
      <span class="pill ${d.validation.in_tolerance ? 'good' : 'warn'}">DQS ${d.validation.dqs}</span></div>
    <div class="mmeta" style="margin-top:6px">${d.entries.map((e) => mainComp(e) ? mainComp(e).name : '').filter(Boolean).slice(0, 3).join(' · ')}</div>
    <div class="between" style="margin-top:6px"><span class="cite">${Math.round(d.totals.kcal)} kcal</span>
      <span class="muted" style="font-size:11px">P ${Math.round(d.totals.protein)} · Fib ${Math.round(d.totals.fibre)}</span></div></div>`).join('');
  return `<div class="between"><div><div class="hi" style="font-size:18px">This week</div>
    <div class="sub">${state.plan.summary.on_target}/7 on target · avg DQS ${state.plan.summary.avg_dqs}</div></div>
    <span class="pill season">all unique</span></div>
    <div class="row" style="gap:8px;margin:10px 0 2px">
      <button class="chip" data-action="grocery">🛒 Grocery list</button>
      <a class="chip" href="/plans/${state.plan.plan_id}/export.xlsx?people=2" download>⬇ Export .xlsx</a>
    </div>${rows}`;
}

async function healthView() {
  const m = state.member, T = state.targets, a = state.anthro;
  const mem = await api(`/members/${state.memberId}/memory`);
  const never = (mem.memory.never || []).concat(mem.memory.dislike || []);
  const conds = (m.conditions || []).map((c) => `<span class="chip">${c.replace(/_/g, ' ')}</span>`).join(' ') || '<span class="muted">none</span>';
  const neverChips = never.length ? never.map((v) => `<span class="chip on" data-action="unnever" data-arg="${v}">${v} ✕</span>`).join(' ')
    : '<span class="muted" style="font-size:12px">nothing excluded yet</span>';
  return `<div class="card"><span class="label">Daily targets · ${T.source}</span>
    <div class="grid3" style="margin-top:10px">
      <div class="card stat"><div class="big">${a.bmi}</div><div class="label">BMI · ${a.bmi_category}</div></div>
      <div class="card stat"><div class="big">${T.kcal}</div><div class="label">kcal</div></div>
      <div class="card stat"><div class="big">${T.protein_g}</div><div class="label">protein g</div></div></div>
    <div class="mmeta" style="margin-top:8px">Sodium ≤${Math.round(T.sodium_mg_max)} mg · added sugar ≤${Math.round(T.added_sugar_g_max)} g · ${(T.citations || []).join(', ')}</div></div>
  <div class="card" style="margin-top:10px"><span class="label">Conditions</span><div style="margin-top:8px">${conds}</div></div>
  <div class="card" style="margin-top:10px"><span class="label">Never / disliked (shapes every plan)</span>
    <div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap">${neverChips}</div>
    <div class="row" style="margin-top:10px;gap:8px">
      <input class="input" id="neverInput" placeholder="e.g. mushroom, paneer, cabbage">
      <button class="btn" style="width:auto;padding:11px 16px" data-action="addnever">Never</button></div></div>`;
}

async function insightsView() {
  const adh = await api(`/members/${state.memberId}/adherence?date=${state.day.date}&plan_id=${state.plan.plan_id}`);
  const rows = adh.per_nutrient.map((r) => {
    const pct = r.pct_of_target || 0, col = pct >= 90 && pct <= 120 ? '--good' : '--gold';
    return `<div style="margin-top:8px"><div class="between" style="font-size:11px">
      <span class="muted">${cap(r.nutrient)}</span><b>${r.actual} / ${r.target} ${r.unit}${r.planned != null ? ` · plan ${r.planned}` : ''}</b></div>
      <div class="bar"><i style="width:${Math.min(100, pct)}%;background:var(${col})"></i></div></div>`;
  }).join('');
  const logged = adh.actuals.kcal > 0;
  return `<div class="between"><div class="hi" style="font-size:18px">Insights · ${state.day.date}</div>
    <span class="pill ${logged ? 'good' : 'warn'}">Adherence ${adh.score}%</span></div>
  <div class="card" style="margin-top:10px"><span class="label">Actual intake vs plan vs target</span>${rows}
    <div class="mmeta" style="margin-top:10px;color:var(--p)">◆ Actuals summed from the Knowledge DB — never invented.</div></div>
  <button class="btn" data-action="markeaten" style="margin-top:12px">${logged ? '↻ Re-log today as eaten' : '✓ Mark today\'s plan as eaten'}</button>
  <div class="mmeta" style="margin-top:8px;text-align:center">Logging expands each dish to its ingredients and computes actuals from IFCT 2017.</div>`;
}

function profileView() {
  const switcher = state.members.map((m) => `<button class="chip ${m.id === state.memberId ? 'on' : ''}"
    data-action="member" data-arg="${m.id}">${m.name}</button>`).join(' ');
  const prov = state.plan.provenance || {};
  return `<div class="card"><span class="label">Household</span>
    <div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap">${switcher}</div></div>
  <div class="card" style="margin-top:10px"><span class="label">Menu engine</span>
    <div class="mmeta" style="margin-top:8px">Provider: <b style="color:var(--ink)">${prov.llm_provider || 'none'}</b>
    (deterministic core; numbers always from the DB). KB: ${prov.kb || ''}.</div></div>
  <div class="card" style="margin-top:10px"><span class="label">Region taste</span>
    <div style="margin-top:8px" class="mmeta">${(state.member.region_prefs || []).map(cap).join(', ') || 'any'} · diet ${state.member.diet_type}</div></div>
  <div class="card" style="margin-top:10px"><div class="between"><span>Sources & citations</span>
    <button class="chip" data-action="sources">View →</button></div></div>
  <div class="mmeta" style="margin-top:14px;text-align:center">Rituva · guideline-grounded · not medical advice</div>`;
}

/* ---------- sheet (swap / sources) ---------- */
function openSheet(html) { const s = $('#sheet'); s.innerHTML = `<div class="sheet"><div class="handle"></div>${html}</div>`; s.hidden = false; }
function closeSheet() { $('#sheet').hidden = true; }
$('#sheet').addEventListener('click', (e) => { if (e.target.id === 'sheet') closeSheet(); });

async function showSwap(recipeId) {
  openSheet('<div class="loading">Finding equivalent options…</div>');
  const res = await api(`/members/${state.memberId}/alternatives?recipe_id=${recipeId}&day=${state.day.date}`);
  const d = res.declined;
  const alts = res.alternatives.map((a) => {
    const ing = a.ingredients.slice(0, 3).map((i) => `${i.name} ${i.qty_g}g → P${i.nutrients.protein}`).join(' · ');
    return `<div class="card" style="margin-top:8px"><div class="between">
      <div><div class="mtitle">${a.name} ${a.region ? `<span class="tag ${a.region}">${a.region[0]}</span>` : ''}</div>
        <div class="nb"><span><i class="sw" style="background:var(--p)"></i>P ${a.nutrients.protein}</span>
        <span><i class="sw" style="background:var(--c)"></i>C ${a.nutrients.carb}</span>
        <span><i class="sw" style="background:var(--fib)"></i>Fib ${a.nutrients.fibre}</span></div></div>
      <div style="text-align:right"><div class="big" style="font-size:15px">${Math.round(a.nutrients.kcal)}</div>
        <span class="pill good" style="font-size:9px">${a.delta}</span></div></div>
      <div class="mmeta" style="margin-top:6px">${ing} … [IFCT 2017]</div></div>`;
  }).join('');
  openSheet(`<div class="between"><h3 class="hi" style="font-size:17px">Swap · ${d.name}</h3><span class="chip" data-action="closesheet">✕</span></div>
    <div class="mmeta">${Math.round(d.nutrients.kcal)} kcal · matched on calories & nutrients, from the DB</div>
    ${alts}<button class="btn ghost" data-action="closesheet" style="margin-top:12px">Close</button>`);
}
async function showSources() {
  openSheet('<div class="loading">Loading cited rules…</div>');
  const g = await api('/guideline-rules');
  const rows = g.rules.map((r) => `<div class="card" style="margin-top:8px"><div class="mtitle">${r.statement}</div>
    <div class="mmeta" style="margin-top:4px">${r.topic} · <b style="color:var(--p)">${r.source} p.${r.page || ''}</b></div></div>`).join('');
  openSheet(`<div class="between"><h3 class="hi" style="font-size:17px">Sources (${g.count})</h3><span class="chip" data-action="closesheet">✕</span></div>
    <div class="mmeta">Every target and limit traces to a cited guideline.</div>${rows}
    <button class="btn ghost" data-action="closesheet" style="margin-top:12px">Close</button>`);
}

async function showGrocery() {
  openSheet('<div class="loading">Building your list…</div>');
  const g = await api(`/plans/${state.plan.plan_id}/grocery?people=2`);
  const cats = g.categories.map((c) => `<div class="h2" style="margin:12px 2px 4px">${c.category}</div>` +
    c.items.map((it) => `<div class="between" style="padding:8px 2px;border-bottom:1px solid var(--line)">
      <span>${it.item}</span><b class="muted">${it.quantity} ${it.unit}</b></div>`).join('')).join('');
  openSheet(`<div class="between"><h3 class="hi" style="font-size:17px">Grocery · ${g.total_items} items</h3>
    <span class="chip" data-action="closesheet">✕</span></div>
    <div class="mmeta">${g.days} days · ${g.people} people · summed from the ingredient BOM</div>${cats}
    <button class="btn ghost" data-action="closesheet" style="margin-top:12px">Close</button>`);
}

/* ---------- actions (event delegation) ---------- */
document.addEventListener('click', async (ev) => {
  const t = ev.target.closest('[data-action]'); if (!t) return;
  const a = t.dataset.action, arg = t.dataset.arg;
  try {
    if (a === 'nav') { state.view = arg; render(); }
    else if (a === 'swap' && arg) { showSwap(arg); }
    else if (a === 'closesheet') { closeSheet(); }
    else if (a === 'sources') { showSources(); }
    else if (a === 'grocery') { showGrocery(); }
    else if (a === 'regen') { await loadMember(); render(); }
    else if (a === 'member') { state.memberId = arg; await loadMember(); state.view = 'today'; render(); }
    else if (a === 'addnever') {
      const v = $('#neverInput').value.trim().toLowerCase(); if (!v) return;
      await api(`/members/${state.memberId}/memory`, { method: 'POST', body: JSON.stringify({ kind: 'never', value: v }) });
      await loadMember(); render();
    } else if (a === 'unnever') {
      await api(`/members/${state.memberId}/memory?kind=never&value=${encodeURIComponent(arg)}`, { method: 'DELETE' });
      await api(`/members/${state.memberId}/memory?kind=dislike&value=${encodeURIComponent(arg)}`, { method: 'DELETE' }).catch(() => {});
      await loadMember(); render();
    } else if (a === 'markeaten') {
      const items = [];
      state.day.entries.forEach((e) => e.components.forEach((c) => items.push({ recipe_id: c.recipe_id, scale: 1.0 })));
      await api(`/members/${state.memberId}/intake`, { method: 'POST', body: JSON.stringify({ date: state.day.date, slot: 'all', items }) });
      render();
    }
  } catch (e) { alert('Error: ' + e.message); }
});

/* ---------- render ---------- */
async function render() {
  topbar(); nav();
  const v = $('#view'); v.innerHTML = '<div class="loading">…</div>';
  try {
    if (state.view === 'today') v.innerHTML = todayView();
    else if (state.view === 'plan') v.innerHTML = planView();
    else if (state.view === 'health') v.innerHTML = await healthView();
    else if (state.view === 'insights') v.innerHTML = await insightsView();
    else if (state.view === 'profile') v.innerHTML = profileView();
  } catch (e) { v.innerHTML = `<div class="err">Error: ${e.message}</div>`; }
}

boot();
