/* =================================================================
   MAP ENGINE — human-authored map pipeline for Nine Lives
   -----------------------------------------------------------------
   Pure logic, no DOM. Loaded by index.html (sets window.MapEngine)
   AND runnable under Node (module.exports) so maps can be validated
   from the command line.

   Public API:
     MapEngine.parseAndValidate(text)  -> { ok, errors:[{line,message}], model }
     MapEngine.layout(model, w, h, opts) -> { id: {x, y, node} }
     MapEngine.describe(node)           -> short human label
     MapEngine.SUIT_SYMBOL, RANK_VALUE  -> lookup tables

   The "model" is the parsed map:
     { phase, order:{n,of}|null, suit,
       rows: [ [node|null, ...] | null, ... ],   // index 0 = START row (bottom)
       nodes: [node, ...],                        // all real nodes, flat
       links: [ {from:"r.i", to:"r.i"}, ... ] }   // valid links only

   A node: { type, row, index, id:"r.i", line, ...typeParams }
     START                         {}
     DEAL  { piles }
     BOSS  { piles }
     CARD  { rank, rankLabel, suit, suitSymbol }
     PACK  { count, suit, suitSymbol }   // suit may be "any"
     STORE                         {}
   ================================================================= */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.MapEngine = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const SUIT_SYMBOL = { diamond: '♦', heart: '♥', spade: '♠', club: '♣' };
  const VALID_SUITS = Object.keys(SUIT_SYMBOL);
  const RANK_VALUE = {
    '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, '10': 10,
    'J': 11, 'Q': 12, 'K': 13, 'A': 14,
  };

  /* ---- tokenizer: split a row body on whitespace, but keep [bracketed]
     params (which may contain spaces, e.g. "CARD[Q diamond]") together. ---- */
  function tokenizeRow(body) {
    const tokens = [];
    let cur = '';
    let depth = 0;
    for (const ch of body) {
      if (ch === '[') { depth++; cur += ch; }
      else if (ch === ']') { depth = Math.max(0, depth - 1); cur += ch; }
      else if (/\s/.test(ch) && depth === 0) { if (cur) { tokens.push(cur); cur = ''; } }
      else cur += ch;
    }
    if (cur) tokens.push(cur);
    return tokens;
  }

  /* drop a trailing "# comment" from a line */
  function stripComment(line) {
    const i = line.indexOf('#');
    return i >= 0 ? line.slice(0, i) : line;
  }

  function describe(n) {
    switch (n.type) {
      case 'START': return 'START';
      case 'STORE': return 'STORE';
      case 'DEAL': return `DEAL piles:${n.piles}`;
      case 'BOSS': return `BOSS piles:${n.piles}`;
      case 'CARD': return `CARD ${n.rankLabel}${n.suitSymbol}`;
      case 'PACK': return `PACK +${n.count} ${n.suit}`;
      default: return n.type;
    }
  }

  /* parse one node token into a node object, pushing any error. */
  function parseNodeToken(token, ctx, errors) {
    const here = `ROW ${ctx.row} node ${ctx.index} ("${token}")`;
    if (token === 'START') return { type: 'START' };
    if (token === 'STORE') return { type: 'STORE' };

    const m = token.match(/^([A-Za-z]+)\[(.*)\]$/);
    if (!m) {
      errors.push({ line: ctx.line, message:
        `${here}: unrecognized node. Expected START, STORE, DEAL[piles:N], BOSS[piles:N], CARD[rank suit], or PACK[+N suit].` });
      return null;
    }
    const kind = m[1].toUpperCase();
    const inner = m[2].trim();

    if (kind === 'DEAL' || kind === 'BOSS') {
      const pm = inner.match(/^piles\s*:\s*(\d+)$/i);
      if (!pm) {
        errors.push({ line: ctx.line, message:
          `${here}: ${kind} needs piles:N (a positive integer), e.g. ${kind}[piles:5]. Got "[${inner}]".` });
        return null;
      }
      const piles = parseInt(pm[1], 10);
      if (piles < 1) { errors.push({ line: ctx.line, message: `${here}: ${kind} piles must be at least 1.` }); return null; }
      return { type: kind, piles };
    }

    if (kind === 'CARD') {
      const parts = inner.split(/\s+/).filter(Boolean);
      if (parts.length !== 2) {
        errors.push({ line: ctx.line, message:
          `${here}: CARD needs "rank suit", e.g. CARD[Q diamond]. Got "[${inner}]".` });
        return null;
      }
      const rank = parts[0].toUpperCase();
      const suit = parts[1].toLowerCase();
      if (!(rank in RANK_VALUE)) {
        errors.push({ line: ctx.line, message: `${here}: CARD rank "${parts[0]}" is invalid. Use 2-10, J, Q, K, or A.` });
        return null;
      }
      if (!VALID_SUITS.includes(suit)) {
        errors.push({ line: ctx.line, message: `${here}: CARD suit "${parts[1]}" is invalid. Use diamond, heart, spade, or club.` });
        return null;
      }
      return { type: 'CARD', rank: RANK_VALUE[rank], rankLabel: rank, suit, suitSymbol: SUIT_SYMBOL[suit] };
    }

    if (kind === 'PACK') {
      const pm = inner.match(/^\+(\d+)\s+([A-Za-z]+)$/);
      if (!pm) {
        errors.push({ line: ctx.line, message:
          `${here}: PACK needs "+N suit", e.g. PACK[+3 diamond] or PACK[+2 any]. Got "[${inner}]".` });
        return null;
      }
      const count = parseInt(pm[1], 10);
      const suit = pm[2].toLowerCase();
      if (count < 1) { errors.push({ line: ctx.line, message: `${here}: PACK count must be at least 1.` }); return null; }
      if (suit !== 'any' && !VALID_SUITS.includes(suit)) {
        errors.push({ line: ctx.line, message: `${here}: PACK suit "${pm[2]}" is invalid. Use diamond, heart, spade, club, or any.` });
        return null;
      }
      return { type: 'PACK', count, suit, suitSymbol: suit === 'any' ? '★' : SUIT_SYMBOL[suit] };
    }

    errors.push({ line: ctx.line, message: `${here}: unknown node type "${kind}".` });
    return null;
  }

  /* ---- parse: text -> structural data + syntax errors ---- */
  function parse(text) {
    const errors = [];
    const meta = { phase: null, order: null, suit: null };
    const rowMap = new Map();   // rowIndex -> node[]
    const links = [];
    let inLinks = false;

    const lines = String(text).split(/\r?\n/);
    lines.forEach((raw, idx) => {
      const lineNo = idx + 1;
      const content = stripComment(raw).trim();
      if (!content) return;

      if (/^LINKS\s*:?\s*$/i.test(content)) { inLinks = true; return; }

      if (inLinks) {
        const lm = content.match(/^(\d+)\.(\d+)\s*->\s*(.+)$/);
        if (!lm) {
          errors.push({ line: lineNo, message: `LINKS: can't parse "${content}". Expected "row.index -> row.index, row.index".` });
          return;
        }
        const from = { row: +lm[1], index: +lm[2] };
        const targets = lm[3].split(',').map(s => s.trim()).filter(Boolean);
        if (!targets.length) { errors.push({ line: lineNo, message: `LINKS: "${content}" has no targets after "->".` }); return; }
        for (const t of targets) {
          const tm = t.match(/^(\d+)\.(\d+)$/);
          if (!tm) { errors.push({ line: lineNo, message: `LINKS: target "${t}" is not in row.index form.` }); continue; }
          links.push({ from: { ...from }, to: { row: +tm[1], index: +tm[2] }, line: lineNo });
        }
        return;
      }

      const hm = content.match(/^(PHASE|ORDER|SUIT)\s*:\s*(.+)$/i);
      if (hm) {
        const key = hm[1].toUpperCase();
        const val = hm[2].trim();
        if (key === 'PHASE') meta.phase = val;
        else if (key === 'SUIT') meta.suit = val.toLowerCase();
        else if (key === 'ORDER') {
          const om = val.match(/^(\d+)\s+of\s+(\d+)$/i);
          if (!om) errors.push({ line: lineNo, message: `ORDER must be "N of M" (e.g. "1 of 3"). Got "${val}".` });
          else meta.order = { n: +om[1], of: +om[2] };
        }
        return;
      }

      const rm = content.match(/^ROW\s+(\d+)\s*:\s*(.*)$/i);
      if (rm) {
        const rowIndex = +rm[1];
        if (rowMap.has(rowIndex)) errors.push({ line: lineNo, message: `ROW ${rowIndex} is defined more than once.` });
        const tokens = tokenizeRow(rm[2].trim());
        if (!tokens.length) errors.push({ line: lineNo, message: `ROW ${rowIndex} has no nodes.` });
        const nodes = [];
        tokens.forEach((tok, i) => {
          const node = parseNodeToken(tok, { line: lineNo, row: rowIndex, index: i }, errors);
          if (node) { node.row = rowIndex; node.index = i; node.id = `${rowIndex}.${i}`; node.line = lineNo; nodes.push(node); }
          else nodes.push(null); // keep index slots aligned with link addressing
        });
        rowMap.set(rowIndex, nodes);
        return;
      }

      errors.push({ line: lineNo, message: `Unrecognized line: "${content}".` });
    });

    const maxRow = rowMap.size ? Math.max(...rowMap.keys()) : -1;
    const rows = [];
    for (let r = 0; r <= maxRow; r++) rows.push(rowMap.has(r) ? rowMap.get(r) : null);

    return { meta, rows, links, errors };
  }

  function bfs(adj, start) {
    const seen = new Set([start]);
    const queue = [start];
    while (queue.length) {
      const cur = queue.shift();
      for (const nx of (adj.get(cur) || [])) if (!seen.has(nx)) { seen.add(nx); queue.push(nx); }
    }
    return seen;
  }

  function buildModel(parsed) {
    const { meta, rows, links } = parsed;
    const nodeAt = (r, i) => (rows[r] && rows[r][i]) || null;
    const nodes = [];
    rows.forEach(ns => (ns || []).forEach(n => { if (n) nodes.push(n); }));
    const validLinks = links
      .filter(l => nodeAt(l.from.row, l.from.index) && nodeAt(l.to.row, l.to.index))
      .map(l => ({ from: `${l.from.row}.${l.from.index}`, to: `${l.to.row}.${l.to.index}` }));
    return { phase: meta.phase, order: meta.order, suit: meta.suit, rows, nodes, links: validLinks };
  }

  function finalize(parsed, errors) {
    errors.sort((a, b) => (a.line || 0) - (b.line || 0));
    const seen = new Set();
    const out = [];
    for (const e of errors) {
      const k = (e.line || 0) + '|' + e.message;
      if (!seen.has(k)) { seen.add(k); out.push(e); }
    }
    return { ok: out.length === 0, errors: out, model: buildModel(parsed) };
  }

  /* ---- validate: structural data -> semantic errors ---- */
  function validate(parsed) {
    const errors = parsed.errors.slice();
    const { meta, rows, links } = parsed;

    // headers
    if (!meta.phase) errors.push({ line: 0, message: 'Missing required header: PHASE.' });
    if (!meta.suit) errors.push({ line: 0, message: 'Missing required header: SUIT.' });
    else if (!VALID_SUITS.includes(meta.suit)) errors.push({ line: 0, message: `SUIT "${meta.suit}" is invalid. Use diamond, heart, spade, or club.` });

    if (!rows.length) {
      errors.push({ line: 0, message: 'No ROW lines found. A map needs at least "ROW 0: START" and a BOSS row.' });
      return finalize(parsed, errors);
    }

    // rows sequential from 0
    for (let r = 0; r < rows.length; r++) {
      if (rows[r] === null) errors.push({ line: 0, message: `ROW ${r} is missing. Rows must be sequential starting at 0 (no gaps).` });
    }

    const nodeAt = (r, i) => (rows[r] && rows[r][i]) || null;
    const rowLen = (r) => (rows[r] ? rows[r].length : 0);

    // START: exactly one, in row 0, alone
    const startNodes = [];
    const bossNodes = [];
    rows.forEach(ns => (ns || []).forEach(n => {
      if (!n) return;
      if (n.type === 'START') startNodes.push(n);
      if (n.type === 'BOSS') bossNodes.push(n);
    }));
    const row0 = rows[0] || [];
    if (startNodes.length === 0) errors.push({ line: 0, message: 'No START node. ROW 0 must be exactly: "ROW 0: START".' });
    if (startNodes.length > 1) errors.push({ line: startNodes[1].line, message: `Found ${startNodes.length} START nodes; there must be exactly one (at ROW 0).` });
    if (!(row0.length === 1 && row0[0] && row0[0].type === 'START')) {
      errors.push({ line: rows[0] && rows[0][0] ? rows[0][0].line : 0, message: 'ROW 0 must contain exactly one node: START.' });
    }

    // BOSS: exactly one, top row, alone
    const topRow = rows.length - 1;
    if (bossNodes.length === 0) errors.push({ line: 0, message: 'No BOSS node. The top row must contain a single BOSS[piles:N].' });
    else if (bossNodes.length > 1) errors.push({ line: bossNodes[1].line, message: `Found ${bossNodes.length} BOSS nodes; there must be exactly one.` });
    else {
      const boss = bossNodes[0];
      if (boss.row !== topRow) errors.push({ line: boss.line, message: `BOSS must be in the top row (ROW ${topRow}), but is in ROW ${boss.row}.` });
      if (rowLen(boss.row) !== 1) errors.push({ line: boss.line, message: `The BOSS row (ROW ${boss.row}) must contain only the BOSS node.` });
    }

    // links: endpoints exist + go exactly one row up.
    // When a referenced slot exists but its node failed to parse, that node
    // already has its own error — don't pile on a misleading "out of range".
    const slotInRange = (r, i) => rows[r] && i >= 0 && i < rows[r].length;
    for (const link of links) {
      const f = nodeAt(link.from.row, link.from.index);
      const t = nodeAt(link.to.row, link.to.index);
      if (!f) {
        if (!rows[link.from.row]) errors.push({ line: link.line, message: `LINKS: source ${link.from.row}.${link.from.index} but ROW ${link.from.row} does not exist.` });
        else if (!slotInRange(link.from.row, link.from.index)) errors.push({ line: link.line, message: `LINKS: source ${link.from.row}.${link.from.index} but ROW ${link.from.row} has only ${rowLen(link.from.row)} node(s).` });
      }
      if (!t) {
        if (!rows[link.to.row]) errors.push({ line: link.line, message: `LINKS: links to ${link.to.row}.${link.to.index} but ROW ${link.to.row} does not exist.` });
        else if (!slotInRange(link.to.row, link.to.index)) errors.push({ line: link.line, message: `ROW ${link.from.row} links to ${link.to.row}.${link.to.index} but ROW ${link.to.row} has only ${rowLen(link.to.row)} node(s).` });
      }
      if (f && t && link.to.row !== link.from.row + 1) {
        errors.push({ line: link.line, message: `LINKS: ${link.from.row}.${link.from.index} -> ${link.to.row}.${link.to.index} must connect to the next row up (ROW ${link.from.row + 1}).` });
      }
    }

    // reachability (only meaningful with a unique START and BOSS)
    if (startNodes.length === 1 && bossNodes.length === 1) {
      const allNodes = [];
      rows.forEach(ns => (ns || []).forEach(n => { if (n) allNodes.push(n); }));
      const fwd = new Map();
      const rev = new Map();
      allNodes.forEach(n => { fwd.set(n.id, []); rev.set(n.id, []); });
      links
        .filter(l => nodeAt(l.from.row, l.from.index) && nodeAt(l.to.row, l.to.index))
        .forEach(l => {
          const fid = `${l.from.row}.${l.from.index}`;
          const tid = `${l.to.row}.${l.to.index}`;
          fwd.get(fid).push(tid);
          rev.get(tid).push(fid);
        });
      const fromStart = bfs(fwd, startNodes[0].id);
      const toBoss = bfs(rev, bossNodes[0].id);
      for (const n of allNodes) {
        if (!fromStart.has(n.id)) {
          errors.push({ line: n.line, message: `Node ${n.id} (${describe(n)}) is unreachable from START.` });
        } else if (!toBoss.has(n.id)) {
          errors.push({ line: n.line, message: `Node ${n.id} (${describe(n)}) is a dead end — no path from it leads to the BOSS.` });
        }
      }
    }

    return finalize(parsed, errors);
  }

  function parseAndValidate(text) {
    return validate(parse(text));
  }

  /* ---- auto-layout: positions from (row, order-in-row) only ----
     row 0 (START) sits at the bottom; the top row (BOSS) at the top.
     Within a row, k nodes spread evenly across the usable width, so
     forks naturally widen toward the edges. No pixel authoring. */
  function layout(model, width, height, opts) {
    opts = opts || {};
    const padX = opts.padX != null ? opts.padX : 0.14 * width;
    const padY = opts.padY != null ? opts.padY : 0.12 * height;
    const R = model.rows.length;
    const pos = {};
    model.rows.forEach((nodes, r) => {
      if (!nodes) return;
      const real = nodes.filter(Boolean);
      const k = real.length;
      const y = R <= 1 ? height / 2 : (height - padY) - r * ((height - 2 * padY) / (R - 1));
      real.forEach((n, j) => {
        const slot = k === 1 ? 0.5 : (j + 1) / (k + 1);
        const x = padX + (width - 2 * padX) * slot;
        pos[n.id] = { x, y, node: n };
      });
    });
    return pos;
  }

  return { parseAndValidate, parse, validate, layout, describe, SUIT_SYMBOL, RANK_VALUE, VALID_SUITS };
});
