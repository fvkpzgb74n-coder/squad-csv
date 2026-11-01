// Match simulation for the tactics board.
// Both sides play automatically from the positions on the board and the players' ratings.
// Model coordinates: x runs 0..105 along the pitch (home attacks towards 105), y runs 0..68 across.
// Uses globals from index.html: state, render, setFacing, place, kitNodes, ballNode, gArrows, toast.

const PITCH_L = 105, PITCH_W = 68, GOAL_HALF = 3.66;
const CLOCK_RATE = 22.5; // match seconds per simulated second: 90 minutes take about 4 minutes at 1×
const STEP = 1 / 60;
const BALL_DRAG = 0.75, SHOT_DRAG = 0.25;
const SHOOT_RANGE = 27; // metres from goal where players start looking to shoot
// The match is a fast highlights reel: 90 minutes pass in about 4, so teams play more directly than real life // how quickly a rolling ball slows down (per second)

const match = { active: false, running: false, speed: 1 };

const dirOf = side => (side === "home" ? 1 : -1);
const goalX = side => (side === "home" ? PITCH_L : 0); // the goal a side attacks
const ownGoalX = side => (side === "home" ? 0 : PITCH_L);
const otherSide = side => (side === "home" ? "away" : "home");
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const gauss = () => (Math.random() + Math.random() + Math.random() - 1.5) / 0.5; // roughly normal, mean 0, sd 1
const squadList = side => state[side].players;
const everyone = () => [...state.home.players, ...state.away.players];
const keeperOf = side => squadList(side).find(p => p.pos === "GK") || squadList(side)[0];
// Tired players lose pace first, and some sharpness on the ball and in the tackle
const FATIGUE = { pace: 0.3, dribbling: 0.15, defending: 0.15, physical: 0.2 };
const attr = (p, key) => {
  const base = p[key] || p.ovr || 60;
  const f = FATIGUE[key];
  return f ? base * (1 - f * (1 - (p.energy ?? 100) / 100)) : base;
};
// Stamina drain in % per match minute: players finish about 55% (stamina 90+) down to about 35% (stamina 55).
// Keepers barely run, so they tire far more slowly; sprinting tires everyone faster.
const drainRate = p => (0.45 + (100 - (p.stamina || 65)) / 135) * (p.pos === "GK" ? 0.25 : 1);
const minute = () => Math.min(90, Math.floor(match.clock / 60) + 1);

function segDist(p, a, b) { // distance from point p to the segment a–b
  const dx = b.x - a.x, dy = b.y - a.y, L2 = dx * dx + dy * dy || 1;
  const t = clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / L2, 0, 1);
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

// ---------- match flow ----------
function startMatch() {
  if (selected) selected = null;
  match.saved = {
    showAway: state.showAway, showBall: state.showBall, ball: { x: state.ball.x, y: state.ball.y },
    positions: everyone().map(p => [p, p.x, p.y]),
  };
  state.showAway = state.showBall = true;
  for (const p of everyone()) { p.bx = p.x; p.by = p.y; p.cool = 0; p.energy = 100; }
  Object.assign(match, {
    active: true, running: true, over: false, clock: 0, half: 1,
    score: { home: 0, away: 0 }, shots: { home: 0, away: 0 }, possTime: { home: 0, away: 0 },
    events: [], owner: null, poss: null, passTo: null, shot: null, lastTouch: null, lastPlayer: null,
    noTouch: null, pause: 0, then: null, decide: 0, firstKick: Math.random() < 0.5 ? "home" : "away",
  });
  matchActive = true;
  render();
  gArrows.style.display = "none";
  kickoff(match.firstKick);
  addEvent(`Kick-off. ${state[match.firstKick].name} get us started.`);
  updateMatchUI();
  match.last = null;
  requestAnimationFrame(loop);
}

function endMatch() {
  match.active = match.running = false;
  matchActive = false;
  for (const p of everyone()) p.energy = 100;
  const s = match.saved;
  if (s) {
    for (const [p, x, y] of s.positions) { p.x = x; p.y = y; }
    state.showAway = s.showAway; state.showBall = s.showBall; state.ball = { ...s.ball };
  }
  gArrows.style.display = "";
  clearPuffs();
  drawCountdown();
  render();
  updateMatchUI();
}

function loop(ts) {
  if (!match.active) return;
  if (match.running) {
    const elapsed = match.last == null ? 0 : Math.min(0.1, (ts - match.last) / 1000);
    match.acc = (match.acc || 0) + elapsed * match.speed;
    while (match.acc >= STEP && match.running) { step(STEP); match.acc -= STEP; }
    sync();
    if ((match.frame = (match.frame || 0) + 1) % 6 === 0) updateMatchUI();
  }
  match.last = ts;
  requestAnimationFrame(loop);
}

function step(dt) {
  if (match.pause > 0) { // a restart is being set up: the clock stops and players drift back into shape
    movePlayers(dt);
    match.pause -= dt;
    if (match.pause <= 0 && match.then) { const f = match.then; match.then = null; f(); }
    return;
  }
  if (match.countdown > 0) {
    match.countdown = Math.max(0, match.countdown - dt / match.speed);
    return;
  }
  match.clock += dt * CLOCK_RATE;
  if (match.half === 1 && match.clock >= 45 * 60) return halfTime();
  if (match.clock >= 90 * 60) return fullTime();
  if (match.poss) match.possTime[match.poss] += dt;
  if (match.noTouch && (match.noTouch.t -= dt) <= 0) match.noTouch = null;
  moveBall(dt);
  if (checkBall()) return;
  movePlayers(dt);
  if (match.owner) carrierThink(dt); else pickups();
  tackles(dt);
}

function restart(delay, fn) { match.kickoffTo = null; match.countdown = 0; match.owner = null; match.passTo = null; match.shot = null; match.pause = delay; match.then = fn; }

function halfTime() {
  match.half = 2; match.clock = 45 * 60;
  addEvent(`Half time: ${scoreLine()}.`);
  restart(3, () => kickoff(otherSide(match.firstKick)));
}

function fullTime() {
  match.clock = 90 * 60; match.running = false; match.over = true;
  match.owner = null; state.ball.vx = state.ball.vy = 0;
  addEvent(`Full time: ${scoreLine()}.`);
  updateMatchUI();
}

const scoreLine = () => `${state.home.name} ${match.score.home}–${match.score.away} ${state.away.name}`;

const FORWARD_DEPTH = 24; // metres ahead of the back line on the board that makes a player a forward
// Team tactics, 0–100, set by how good each XI is compared with the opposition:
// the better side holds a higher line and attacks more patiently; the weaker side sits deeper and goes direct.
const TACTIC_PER_POINT = 2; // tactic points per point of average rating difference
function tacticsFor(side) {
  const mine = avgOvr(state[side]) || 70, theirs = avgOvr(state[otherSide(side)]) || 70;
  const edge = (mine - theirs) * TACTIC_PER_POINT;
  return { defLine: Math.round(clamp(50 + edge, 15, 85)), attackSpeed: Math.round(clamp(50 - edge, 15, 85)) };
}
const CIRCLE_R = 9.15; // centre circle radius in metres
const COUNTDOWN = 3;   // real seconds of 3-2-1 before each kick-off
const MIDFIELD = ["DM", "CM", "AM", "CDM", "CAM", "LM", "RM"];

// Kick-off: the centre forward stands over the ball and plays it back to a central midfielder
// waiting at the edge of the centre circle. Everyone else starts in their own half, outside the circle.
function kickoff(side) {
  const mid = PITCH_L / 2, d = dirOf(side);
  const outfield = squadList(side).filter(p => p.pos !== "GK");
  const strikers = outfield.filter(p => p.pos === "ST" || p.pos === "CF");
  const taker = (strikers.length ? strikers : outfield).sort((a, b) => Math.abs(a.by - 34) - Math.abs(b.by - 34) || d * (b.bx - a.bx))[0];
  const mids = outfield.filter(p => p !== taker && MIDFIELD.includes(p.pos));
  const receiver = (mids.length ? mids : outfield.filter(p => p !== taker)).sort((a, b) => Math.abs(a.by - 34) - Math.abs(b.by - 34))[0];

  for (const p of everyone()) {
    const pd = dirOf(p.side);
    let x = pd > 0 ? Math.min(p.bx, mid - 1) : Math.max(p.bx, mid + 1);
    let y = p.by;
    if (Math.hypot(x - mid, y - 34) < CIRCLE_R + 0.6) {
      // Step back out of the circle, staying in our own half
      const r = CIRCLE_R + 0.8;
      let ang = Math.atan2(y - 34, x - mid);
      if (Math.abs(y - 34) < 0.5 && Math.abs(x - mid) < 0.5) ang = pd > 0 ? Math.PI : 0;
      x = mid + Math.cos(ang) * r; y = 34 + Math.sin(ang) * r;
      x = pd > 0 ? Math.min(x, mid - 0.5) : Math.max(x, mid + 0.5);
      if (Math.hypot(x - mid, y - 34) < r) y = 34 + Math.sign(y - 34 || 1) * Math.sqrt(r * r - (x - mid) ** 2);
    }
    p.x = x; p.y = y; p.cool = 0; p.dx = p.dy = undefined;
  }
  taker.x = mid + d * 0.9; taker.y = 34; // just inside the opposition half, facing back over the ball
  receiver.x = mid - d * (CIRCLE_R + 0.6); receiver.y = 34;
  giveBall(taker);
  Object.assign(state.ball, { x: mid, y: 34, vx: 0, vy: 0 });
  match.kickoffTo = receiver;
  match.decide = 0;
  match.countdown = COUNTDOWN;
}

function giveBall(p) {
  match.owner = p; match.poss = p.side; match.lastTouch = p.side; match.lastPlayer = p;
  match.passTo = null; match.shot = null;
  state.ball.vx = state.ball.vy = 0;
  p.dx = p.dy = undefined;
  match.decide = 0.15 + Math.random() * 0.2; // move the ball on quickly after receiving it
}

function release(p) {
  match.owner = null; match.lastTouch = p.side; match.lastPlayer = p;
  match.noTouch = { p, t: 0.3 };
}

// ---------- ball ----------
function moveBall(dt) {
  const b = state.ball;
  if (match.owner && match.kickoffTo) return; // the ball waits on the centre spot
  if (match.owner) {
    const o = match.owner, d = dirOf(o.side);
    b.x = clamp(o.x + d * 0.9, 0.2, PITCH_L - 0.2); b.y = o.y;
    return;
  }
  b.x += b.vx * dt; b.y += b.vy * dt;
  const f = Math.exp(-(match.shot ? SHOT_DRAG : BALL_DRAG) * dt);
  b.vx *= f; b.vy *= f;
  if (Math.hypot(b.vx, b.vy) < 0.3) { b.vx = b.vy = 0; if (!match.shot) match.passTo = null; }
}

// Goals, saves and the ball going out of play. Returns true when play stops.
function checkBall() {
  const b = state.ball;
  const s = match.shot;
  if (s && !s.resolved && Math.abs(b.x - goalX(s.side)) < 2.2) {
    s.resolved = true;
    if (Math.abs(b.y - 34) < GOAL_HALF) {
      const gk = keeperOf(otherSide(s.side));
      const save = clamp(0.64 + (attr(gk, "ovr") - 70) / 60 - (attr(s.by, "shooting") - 70) / 90 + (s.dist - 16) / 60, 0.15, 0.92);
      if (Math.random() < save) {
        addEvent(`${minute()}' Save! ${gk.name} keeps out ${s.by.name}.`);
        gk.x = goalX(s.side) - dirOf(s.side) * 1.5; gk.y = clamp(b.y, 31, 37);
        giveBall(gk);
        restart(1, () => giveBall(gk));
        return true;
      }
    }
  }
  if (b.x < 0 || b.x > PITCH_L) {
    const attackers = b.x > PITCH_L ? "home" : "away"; // the side attacking that goal
    if (Math.abs(b.y - 34) < GOAL_HALF) goal(attackers);
    else {
      if (match.shot) addEvent(`${minute()}' ${match.shot.by.name} shoots wide.`);
      if (match.lastTouch === attackers) goalKick(otherSide(attackers)); else corner(attackers, b.y < 34 ? 0.5 : PITCH_W - 0.5);
    }
    return true;
  }
  if (b.y < 0 || b.y > PITCH_W) { throwIn(otherSide(match.lastTouch), clamp(b.x, 1, PITCH_L - 1), b.y < 0 ? 0.5 : PITCH_W - 0.5); return true; }
  return false;
}

function goal(side) {
  match.score[side]++;
  const scorer = match.lastPlayer;
  const ownGoal = scorer && scorer.side !== side;
  addEvent(`${minute()}' GOAL! ${scorer ? scorer.name : "Scrambled in"}${ownGoal ? " (own goal)" : ""} for ${state[side].name}. ${scoreLine()}.`, true);
  const b = state.ball; b.vx = b.vy = 0; b.x = clamp(b.x, -1.5, PITCH_L + 1.5);
  restart(2.5, () => kickoff(otherSide(side)));
}

function goalKick(side) {
  restart(1.2, () => {
    const gk = keeperOf(side);
    gk.x = ownGoalX(side) + dirOf(side) * 5.5; gk.y = 34;
    Object.assign(state.ball, { x: gk.x, y: gk.y });
    giveBall(gk);
  });
}

function corner(side, y) {
  addEvent(`${minute()}' Corner to ${state[side].name}.`);
  restart(1.2, () => {
    const spot = { x: goalX(side) - dirOf(side) * 0.5, y };
    const taker = squadList(side).filter(p => p.pos !== "GK").sort((a, b) => dist(a, spot) - dist(b, spot))[0];
    taker.x = spot.x; taker.y = spot.y;
    giveBall(taker);
    match.decide = 0.5;
  });
}

function throwIn(side, x, y) {
  restart(0.8, () => {
    const spot = { x, y };
    const taker = squadList(side).filter(p => p.pos !== "GK").sort((a, b) => dist(a, spot) - dist(b, spot))[0];
    taker.x = x; taker.y = y;
    giveBall(taker);
  });
}

// ---------- players ----------
function movePlayers(dt) {
  const b = state.ball;
  for (const side of ["home", "away"]) {
    const d = dirOf(side), list = squadList(side), attacking = match.poss === side;
    const outfield = list.filter(p => p.pos !== "GK" && p !== match.owner);
    outfield.sort((p, q) => dist(p, b) - dist(q, b));
    const [chaser, cover] = outfield;
    const chase = match.pause <= 0 && !match.shot && (!attacking || (!match.owner && !match.passTo));
    // Height of our back line, in metres from our own goal, set by where the ball is
    const ballU = d * (b.x - ownGoalX(side));
    const tactics = tacticsFor(side);
    // The opposition's last outfield defender: our forwards play off this line
    const opp = otherSide(side), od = dirOf(opp);
    const oppLineU = Math.min(...squadList(opp).filter(p => p.pos !== "GK").map(p => od * (p.x - ownGoalX(opp))));
    const oppLineX = ownGoalX(opp) + od * oppLineU;
    const shape = {
      oppLineX,
      ref: Math.min(...list.filter(p => p.pos !== "GK").map(p => d * (p.bx - ownGoalX(side)))),
      line: (attacking ? clamp(ballU - 24, 22, 60) : clamp(ballU - 18, 16, 58))
        + (tactics.defLine - 50) * (attacking ? 0.1 : 0.16), // up to ±8 m when defending
    };
    for (const p of list) {
      let tx, ty, sprint = false;
      if (p === match.owner) {
        tx = p.dx ?? p.x + d * 3; ty = p.dy ?? p.y;
      } else if (p.pos === "GK") {
        // Sweeper keeper: steps up behind a high line
        tx = ownGoalX(side) + d * clamp(shape.line * (attacking ? 0.4 : 0.15), 2.5, attacking ? 22 : 10);
        ty = 34 + (b.y - 34) * 0.25;
      } else if (p === match.passTo && match.pause <= 0) {
        // Run onto the line of the pass
        const v = Math.hypot(b.vx, b.vy) || 1, ux = b.vx / v, uy = b.vy / v;
        const along = clamp((p.x - b.x) * ux + (p.y - b.y) * uy, 0, v / BALL_DRAG);
        tx = b.x + ux * along; ty = b.y + uy * along; sprint = true;
      } else if (chase && p === chaser) {
        tx = b.x; ty = b.y; sprint = true;
      } else if (!attacking && p === cover && match.pause <= 0) {
        tx = b.x - d * 6; ty = b.y + (34 - b.y) * 0.3; // sit between the ball and our goal
      } else {
        // Team shape: keep each player's place in the board formation, but set the block's height and
        // depth from the ball. Defending, the back line steps up behind the ball and the team squeezes;
        // attacking, the team stretches so forwards play on the opposition's back line.
        const depth = d * (p.bx - ownGoalX(side)) - shape.ref; // metres in front of our back line on the board
        const u = shape.line + depth * (attacking ? 1.3 : 0.8);
        tx = ownGoalX(side) + d * u;
        ty = attacking ? p.by + (b.y - 34) * 0.3 : 34 + (p.by - 34) * 0.8 + (b.y - 34) * 0.4;
        if (depth > FORWARD_DEPTH) {
          // Forwards play right up against the opposition's back line: on its shoulder when we
          // attack, a few metres off it when we defend, ready to press their centre-backs
          tx = shape.oppLineX - d * (attacking ? 0.5 : 2.5);
          if (attacking) ty += Math.sin(match.clock / 40 + p.bx * 7) * 4; // drift to find space
          sprint = Math.abs(tx - p.x) > 2.5; // keep up with the line as it moves
        }
        tx = clamp(tx, 3, PITCH_L - 3);
      }
      if (match.pause <= 0 && !(match.countdown > 0)) {
        p.energy = Math.max(0, (p.energy ?? 100) - (dt * CLOCK_RATE / 60) * drainRate(p) * (sprint ? 1.4 : 0.9));
      }
      const pace = attr(p, "pace");
      const speed = (5.5 + pace * 0.055) * (sprint ? 1 : 0.85) * (p === match.owner ? 0.85 : 1) * (match.pause > 0 ? 0.6 : 1);
      const dx = tx - p.x, dy = ty - p.y, L = Math.hypot(dx, dy);
      if (L > 0.2) { const m = Math.min(L, speed * dt); p.x += (dx / L) * m; p.y += (dy / L) * m; }
    }
    // Keep teammates from bunching on top of each other
    for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) {
      const a = list[i], c = list[j], gap = dist(a, c);
      if (gap > 0 && gap < 2.5) {
        const push = ((2.5 - gap) / gap) * 0.5 * dt * 4;
        if (a !== match.owner) { a.x -= (c.x - a.x) * push; a.y -= (c.y - a.y) * push; }
        if (c !== match.owner) { c.x += (c.x - a.x) * push; c.y += (c.y - a.y) * push; }
      }
    }
    for (const p of list) { p.x = clamp(p.x, 0.5, PITCH_L - 0.5); p.y = clamp(p.y, 0.5, PITCH_W - 0.5); }
  }
}

// A loose ball goes to whoever reaches it first; fast passes are harder to cut out
function pickups() {
  const b = state.ball, speed = Math.hypot(b.vx, b.vy);
  let best = null, bestD = 1.4;
  for (const p of everyone()) {
    if (match.noTouch && match.noTouch.p === p) continue;
    const d = dist(p, b);
    if (d > 1.4) continue;
    let chance = 1;
    if (match.shot) chance = p.pos === "GK" ? 0 : 0.06; // outfield blocks; keepers are handled at the line
    else if (match.passTo && p.side !== match.passTo.side) {
      // Each opponent gets one go at cutting out a pass, as it reaches them
      if (match.passTried.has(p)) continue;
      match.passTried.add(p);
      const def = attr(p, "defending") / 100;
      chance = speed > 10 ? 0.05 + def * def * 0.35 : 0.55;
    }
    if (Math.random() < chance && d < bestD) { best = p; bestD = d; }
  }
  if (!best) return;
  if (match.shot && best.side !== match.shot.side) addEvent(`${minute()}' Blocked by ${best.name}.`);
  giveBall(best);
}

function tackles(dt) {
  const c = match.owner;
  for (const p of everyone()) p.cool = Math.max(0, (p.cool || 0) - dt);
  if (!c) return;
  for (const o of squadList(otherSide(c.side))) {
    if (o.cool > 0 || dist(o, c) > 1.6) continue;
    o.cool = 0.6;
    const win = clamp(0.35 * (attr(o, "defending") / attr(c, "dribbling")) ** 2, 0.05, 0.75);
    if (Math.random() < win) { giveBall(o); c.cool = 0.8; return; }
  }
}

// ---------- decisions on the ball ----------
function carrierThink(dt) {
  const c = match.owner;
  if ((match.decide -= dt) > 0) return;
  const tempo = tacticsFor(c.side).attackSpeed / 100; // 0.15 (patient) to 0.85 (direct)
  match.decide = (0.18 + Math.random() * 0.22) * (1.25 - tempo * 0.5); // quicker teams release the ball sooner
  if (match.kickoffTo) { const to = match.kickoffTo; match.kickoffTo = null; return pass(c, to); }
  const d = dirOf(c.side), opp = squadList(otherSide(c.side)), mates = squadList(c.side).filter(p => p !== c);
  const gx = goalX(c.side), toGoal = Math.hypot(gx - c.x, 34 - c.y);
  const pressure = Math.min(...opp.map(o => dist(o, c)));

  if (toGoal < SHOOT_RANGE && Math.abs(34 - c.y) < 22 && c.pos !== "GK") {
    const keen = ((SHOOT_RANGE - toGoal) / SHOOT_RANGE) * 1.1 + (pressure < 3 ? 0.2 : 0) + (attr(c, "shooting") - 60) / 250;
    if (Math.random() < keen) return shoot(c);
  }

  // Build-up: in our own half, keeping the ball matters more than going forward,
  // so players recycle it to a free teammate (back to the centre-backs or keeper if needed).
  const ownHalf = d * (c.x - ownGoalX(c.side)) < PITCH_L / 2;
  const pressed = pressure < 4;
  const progressWeight = (ownHalf ? 0.25 : 0.5) * (0.6 + tempo * 0.8); // ×1 at 50, more forward-minded when quicker
  // Dribbling skill is judged against the player's own level: a 64-rated winger with 70 dribbling is a
  // good dribbler for his level, a centre-back usually dribbles well below his overall.
  // Typical gaps: wingers +2 (best +5 or more), full-backs -3, centre-backs -13.
  const flairGap = attr(c, "dribbling") - (c.ovr || attr(c, "dribbling"));
  const keepItSimple = Math.max(0, (-flairGap - 1) * 0.5); // poor dribblers look for the simple, short pass
  let best = null, bestScore = -Infinity;
  for (const m of mates) {
    const L = dist(c, m);
    if (L < 4 || L > 45) continue;
    if (m.pos === "GK" && !ownHalf) continue;
    const progress = d * (m.x - c.x);
    const lane = Math.min(...opp.map(o => segDist(o, c, m)));
    const space = Math.min(...opp.map(o => dist(o, m)));
    const inBox = Math.abs(gx - m.x) < 16 && Math.abs(m.y - 34) < 20;
    let score = progress * progressWeight + Math.min(space, 8) + Math.min(lane, 6) * 1.7 - L * 0.1
      + (lane < 1.5 ? -8 : 0) + (inBox ? 5 : 0) + Math.random() * 3;
    if (ownHalf && progress < -3 && space > 6 && pressed) score += 3 * (1.5 - tempo); // under pressure, a safe ball back; patient teams more so
    if (m.pos === "GK") score -= pressed ? 1 : 4; // the keeper is an outlet, mostly when pressed
    if (L < 20 && lane > 2.5) score += keepItSimple; // a short, safe ball to a nearby teammate
    if (score > bestScore) { best = m; bestScore = score; }
  }

  const ahead = opp.filter(o => d * (o.x - c.x) > 0 && dist(o, c) < 10);
  const room = ahead.length ? Math.min(...ahead.map(o => dist(o, c))) : 10;
  // Good dribblers want to carry it and take players on; poor ones would rather not
  const flair = 3 + flairGap * 1.3; // about +10 for a standout dribbler, +5 for a typical winger, -14 for a centre-back
  // Attacking channels: the wide and half-space areas of the final third. Players there are
  // encouraged to take their man on and drive at the box, more so if they dribble well for their level.
  const inChannel = d * (c.x - ownGoalX(c.side)) > PITCH_L * 2 / 3 && Math.abs(c.y - 34) > 9;
  const channelUrge = inChannel ? 6 + Math.max(0, flairGap) * 0.6 : 0;
  const dribble = c.pos === "GK" ? -100
    : room * 1.2 + flair + channelUrge + Math.random() * 4 - (pressure < 2 ? 4 : 0) - (ownHalf ? 3 : 0);

  // Tightly marked, most players move it on; good dribblers may still try to beat their man,
  // and in the channels anyone dribbling at or above their level will have a go
  const mustRelease = pressure < 2.2 && flairGap < (inChannel ? 0 : 3);
  if (best && (bestScore > dribble || mustRelease)) return pass(c, best);
  c.dx = clamp(c.x + d * (inChannel ? 8 : 10), 1, PITCH_L - 1);
  c.dy = inChannel
    ? clamp(c.y + (34 - c.y) * 0.35 + gauss() * 2, 2, PITCH_W - 2) // drive at the box, cutting inside
    : clamp(c.y + (34 - c.y) * 0.25 + gauss() * 3, 2, PITCH_W - 2);
}

function pass(c, m) {
  const b = state.ball, L = dist(c, m);
  const err = gauss() * (1 - attr(c, "passing") / 100) * 0.35; // radians off target: better passers are more accurate
  const ang = Math.atan2(m.y - c.y, m.x + dirOf(c.side) * 1.5 - c.x) + err;
  const v = Math.min(34, L * BALL_DRAG * 1.15 + 10); // firm, zipped passes
  release(c);
  b.vx = Math.cos(ang) * v; b.vy = Math.sin(ang) * v;
  match.passTo = m;
  match.passTried = new Set();
}

function shoot(c) {
  const b = state.ball, gx = goalX(c.side);
  const aimY = 34 + (Math.random() * 2 - 1) * (GOAL_HALF - 0.6);
  const L = Math.hypot(gx - c.x, aimY - c.y);
  const miss = gauss() * ((100 - attr(c, "shooting")) / 100) * (3 + L * 0.18); // metres wide of the aim
  const ang = Math.atan2(aimY + miss - c.y, gx - c.x);
  const v = 24 + attr(c, "shooting") / 12;
  release(c);
  b.vx = Math.cos(ang) * v; b.vy = Math.sin(ang) * v;
  match.shot = { side: c.side, by: c, dist: L, resolved: false };
  match.shots[c.side]++;
}

// ---------- drawing and panel ----------
// Big 3-2-1 over the centre spot, popping in as each number changes
function drawCountdown() {
  let t = document.getElementById("countdown");
  if (!t) {
    t = document.createElementNS("http://www.w3.org/2000/svg", "text");
    t.id = "countdown";
    t.setAttribute("x", DRAW_W / 2); t.setAttribute("y", PITCH_L / 2 + 6.5);
    t.setAttribute("text-anchor", "middle");
    document.getElementById("pitch").appendChild(t);
  }
  const n = match.active && match.countdown > 0 ? String(Math.ceil(match.countdown)) : "";
  if (t.textContent !== n) {
    t.textContent = n;
    t.classList.remove("pop"); void t.getBBox(); if (n) t.classList.add("pop");
  }
}
// Breath bubbles: a tired player gets a little pixel cloud speech bubble at the top right of their
// shirt that moves with them. Each breath pops the bubble up and fades it; below 70% stamina the
// breaths come more often and the bubble grows as the player tires.
const BREATH_FROM = 70, BREATH_FULL = 25;  // stamina where bubbles start, and where they are at their most
const PUFF_ART = [ // W white, S soft shade, O grey outline; the dots bottom-left trail down to the shirt
  "...OOO.OOO.",
  "..OWWWOWWWO",
  ".OWWWWWWWWO",
  "OWWWWWWWWWO",
  "OWWWWWWWWSO",
  ".OWWWWWSSO.",
  "..OOOOOOO..",
  ".OWO.......",
  "O..........",
];
const PUFF_W = 11, PUFF_H = 9, PUFF_SIZE = 2.4; // pixel grid, and drawn width in metres at normal size
const puffs = [];
function puffSymbol() {
  if (document.getElementById("px-puff")) return;
  const NS = "http://www.w3.org/2000/svg", sym = document.createElementNS(NS, "symbol");
  sym.id = "px-puff"; sym.setAttribute("viewBox", `0 0 ${PUFF_W} ${PUFF_H}`); sym.setAttribute("shape-rendering", "crispEdges");
  PUFF_ART.forEach((row, y) => [...row].forEach((ch, x) => {
    const fill = { W: "#ffffff", S: "#d4dbe8", O: "#5d6884" }[ch];
    if (!fill) return;
    const r = document.createElementNS(NS, "rect");
    r.setAttribute("x", x); r.setAttribute("y", y); r.setAttribute("width", 1.02); r.setAttribute("height", 1.02);
    r.setAttribute("fill", fill); sym.appendChild(r);
  }));
  document.querySelector("#pitch defs").appendChild(sym);
}
function breathe(now) {
  const layer = document.getElementById("puffs");
  puffSymbol();
  for (const p of everyone()) {
    const e = p.energy ?? 100;
    if (e > BREATH_FROM) { p.nextPuff = null; continue; }
    const t = clamp((BREATH_FROM - e) / (BREATH_FROM - BREATH_FULL), 0, 1); // 0 = just tiring, 1 = exhausted
    const every = (1.8 - t * 1.45) * 1000;                                  // 1.8s down to 0.35s between breaths
    if (p.nextPuff == null) p.nextPuff = now + Math.random() * every;
    if (now < p.nextPuff) continue;
    p.nextPuff = now + every * (0.8 + Math.random() * 0.4);
    if (p.bubble) { p.bubble.el.remove(); puffs.splice(puffs.indexOf(p.bubble), 1); } // one bubble per player
    const el = document.createElementNS("http://www.w3.org/2000/svg", "use");
    el.setAttribute("href", "#px-puff"); el.setAttribute("width", PUFF_SIZE); el.setAttribute("height", PUFF_SIZE * PUFF_H / PUFF_W);
    layer.appendChild(el);
    p.bubble = { el, p, born: now, life: clamp(every * 0.9, 320, 1100), size: 0.8 + t * 0.9 }; // up to ~2x when exhausted
    puffs.push(p.bubble);
  }
  for (let i = puffs.length - 1; i >= 0; i--) {
    const f = puffs[i], age = (now - f.born) / f.life;
    if (age >= 1) { f.el.remove(); puffs.splice(i, 1); if (f.p.bubble === f) f.p.bubble = null; continue; }
    // pop in quickly, hold, then fade; anchored by its bottom-left tail to the shirt's top-right corner
    const pop = age < 0.15 ? 0.6 + (age / 0.15) * 0.4 : 1;
    const s = f.size * pop;
    const ax = f.p.y * DRAW_SCALE + KIT_W * ICON_SCALE / 2 - 0.4;
    const ay = PITCH_L - f.p.x - KIT_H * ICON_SCALE / 2 + 0.4 - age * 0.5;
    f.el.setAttribute("transform", `translate(${ax} ${ay - PUFF_SIZE * PUFF_H / PUFF_W * s}) scale(${s})`);
    f.el.setAttribute("opacity", (age < 0.55 ? 1 : 1 - (age - 0.55) / 0.45).toFixed(2));
  }
}
function clearPuffs() { for (const f of puffs) f.el.remove(); puffs.length = 0; for (const p of everyone()) { p.nextPuff = null; p.bubble = null; } }

function sync() {
  drawCountdown();
  for (const p of everyone()) {
    const n = kitNodes.get(p.id);
    if (n) { n.g.setAttribute("transform", place(p)); setFacing(p); }
  }
  if (match.active && match.running) breathe(performance.now());
  if (ballNode) ballNode.setAttribute("transform", place(state.ball));
}

// Match events are kept for the record; goals also pop up as a banner
function addEvent(text, big) {
  match.events.unshift({ text, big });
  if (big) toast(text.replace(/^\d+' /, ""));
}

function updateMatchUI() {
  const on = match.active;
  const ko = document.getElementById("kickoff");
  ko.innerHTML = !on || (!match.running && !match.over) ? "&#9654;" : match.over ? "&#8634;" : "&#10074;&#10074;";
  ko.setAttribute("aria-label", !on ? "Kick off" : match.over ? "Back to the board" : match.running ? "Pause" : "Resume");
  document.getElementById("speed").hidden = !on || match.over;
  document.getElementById("speed").textContent = `${match.speed}×`;
  document.getElementById("end-match").hidden = !on || match.over;
  updateStaminaBars();
  const t = { home: tacticsFor("home"), away: tacticsFor("away") };
  const setT = (id, v) => { document.getElementById(id).textContent = v; };
  setT("st-def-h", t.home.defLine); setT("st-def-a", t.away.defLine);
  setT("st-spd-h", t.home.attackSpeed); setT("st-spd-a", t.away.attackSpeed);
  if (!on) {
    for (const id of ["st-poss-h", "st-poss-a", "st-shots-h", "st-shots-a", "st-goals-h", "st-goals-a"]) setT(id, "–");
    document.getElementById("st-poss-bar").style.width = "50%";
  }
  if (on) {
    const total = match.possTime.home + match.possTime.away;
    const pct = total ? Math.round((match.possTime.home / total) * 100) : 50;
    const set = (id, v) => { document.getElementById(id).textContent = v; };
    set("st-poss-h", `${pct}%`); set("st-poss-a", `${100 - pct}%`);
    document.getElementById("st-poss-bar").style.width = `${pct}%`;
    set("st-shots-h", match.shots.home); set("st-shots-a", match.shots.away);
    set("st-goals-h", match.score.home); set("st-goals-a", match.score.away);
  }
  updateScoreboard();
}

document.getElementById("kickoff").addEventListener("click", () => {
  document.querySelectorAll(".popover").forEach(p => { p.hidden = true; });
  if (!match.active) startMatch();
  else if (match.over) { match.events = []; endMatch(); }
  else { match.running = !match.running; match.last = null; updateMatchUI(); }
});
document.getElementById("speed").addEventListener("click", () => {
  match.speed = match.speed === 4 ? 1 : match.speed * 2; updateMatchUI();
});
document.getElementById("end-match").addEventListener("click", () => {
  match.events = []; endMatch();
});

// Show the starting tactics once everything has loaded
updateMatchUI();
