(() => {
  const hud = document.getElementById("hud");
  const tiles = document.getElementById("tiles");
  const MAX_ICONS = 4; // a tile shows a 2x2 grid, the 4th slot becomes "+N" on overflow
  const FLIGHT_MS = 520;
  let outTimer = null;
  let flightTimer = null;
  let flight = null;     // the running icon animation, if any
  let generation = 0;    // bumped by every show/move so stale callbacks do nothing
  let lastActiveLeft = null;
  let holding = false;   // the peek key is down: stay up until release()
  let moving = false;    // a move animation hasn't finished yet

  function restart(el, cls) {
    el.classList.remove(cls);
    void el.offsetWidth; // force reflow so the animation replays
    el.classList.add(cls);
  }

  function renderIcons(el, ws, data, animate) {
    const withIcons = data.showAppIcons
      ? (ws.apps || []).filter(a => data.icons && data.icons[a.bundle])
      : [];
    if (withIcons.length === 0) {
      const empty = document.createElement("div");
      empty.className = ws.occupied ? "tile-count" : "tile-empty";
      if (ws.occupied) empty.textContent = ws.apps.length;
      el.appendChild(empty);
      return;
    }
    const overflow = withIcons.length > MAX_ICONS;
    const shown = withIcons.slice(0, overflow ? MAX_ICONS - 1 : MAX_ICONS);
    shown.forEach((a, i) => {
      const img = document.createElement("img");
      img.src = data.icons[a.bundle];
      img.title = a.name;
      img.dataset.bundle = a.bundle;
      if (animate) {
        img.className = "pop";
        img.style.animationDelay = (80 + i * 40) + "ms";
      }
      el.appendChild(img);
    });
    if (overflow) {
      const more = document.createElement("div");
      more.className = "tile-more";
      more.textContent = "+" + (withIcons.length - shown.length);
      el.appendChild(more);
    }
  }

  // animateIcons: pop in the active tile's icons. landed: name of a tile to bounce.
  function renderTiles(data, animateIcons = true, landed = null) {
    tiles.innerHTML = "";
    const active = document.createElement("div");
    active.className = "tile-active";
    tiles.appendChild(active);

    let activeTile = null;
    data.workspaces.forEach(ws => {
      const isActive = ws.name === data.workspace;
      const tile = document.createElement("div");
      tile.className = "tile" + (ws.occupied ? " occupied" : "") + (isActive ? " active" : "")
        + (ws.name === landed ? " landed" : "");
      tile.dataset.name = ws.name;

      const icons = document.createElement("div");
      icons.className = "tile-icons";
      renderIcons(icons, ws, data, animateIcons && isActive);
      tile.appendChild(icons);

      const label = document.createElement("div");
      label.className = "tile-label";
      label.textContent = ws.name;
      tile.appendChild(label);

      tiles.appendChild(tile);
      if (isActive) activeTile = tile;
    });

    if (!activeTile) { active.style.display = "none"; return; }
    const left = activeTile.offsetLeft;
    // Start from the previous position so the highlight glides.
    active.style.left = (lastActiveLeft ?? left) + "px";
    void active.offsetWidth; // commit the start position so the transition runs
    active.style.left = left + "px";
    lastActiveLeft = left;
  }

  function tileFor(name) {
    return tiles.querySelector(`.tile[data-name="${CSS.escape(name)}"]`);
  }

  function popIn(theme, quick = false) {
    document.body.className = `theme-${theme}`;
    hud.classList.toggle("quick", quick);
    hud.classList.remove("out");
    if (!hud.classList.contains("in")) restart(hud, "in");
  }

  function scheduleOut(ms) {
    clearTimeout(outTimer);
    if (holding) return;
    outTimer = setTimeout(() => {
      hud.classList.remove("in");
      restart(hud, "out");
    }, ms);
  }

  // Fly a copy of the moved app's icon from its old tile to its new one.
  function fly(moved, data, done) {
    const from = tileFor(moved.from);
    const to = tileFor(moved.to);
    const src = from && from.querySelector(`img[data-bundle="${CSS.escape(moved.bundle)}"]`);
    const icon = data.icons && data.icons[moved.bundle];
    if (!from || !to || !icon || !data.showAppIcons) { done(); return; }

    const start = (src || from.querySelector(".tile-icons")).getBoundingClientRect();
    const end = to.querySelector(".tile-icons").getBoundingClientRect();
    const size = src ? start.width : 24;
    const x0 = start.left + start.width / 2 - size / 2;
    const y0 = start.top + start.height / 2 - size / 2;
    const dx = end.left + end.width / 2 - size / 2 - x0;
    const dy = end.top + end.height / 2 - size / 2 - y0;

    const clone = document.createElement("img");
    clone.className = "flying";
    clone.src = icon;
    Object.assign(clone.style, { left: x0 + "px", top: y0 + "px", width: size + "px", height: size + "px" });
    document.body.appendChild(clone);
    if (src) src.style.visibility = "hidden";

    const anim = clone.animate([
      { transform: "translate(0, 0) scale(1)" },
      { transform: `translate(${dx / 2}px, ${dy / 2 - 26}px) scale(1.25)`, offset: 0.45 },
      { transform: `translate(${dx}px, ${dy}px) scale(0.8)` },
    ], { duration: FLIGHT_MS, easing: "cubic-bezier(0.45, 0, 0.2, 1)" });
    flight = anim;
    anim.onfinish = () => { clone.remove(); flight = null; done(); };
    anim.oncancel = () => clone.remove();
  }

  // Stop any move animation in progress. Returns the new generation number.
  function interrupt() {
    clearTimeout(flightTimer);
    moving = false;
    if (flight) { flight.cancel(); flight = null; }
    document.querySelectorAll(".flying").forEach(el => el.remove());
    return ++generation;
  }

  window.hud = {
    show(data) {
      interrupt();
      holding = !!data.hold;
      renderTiles(data, !data.quick);
      popIn(data.theme, !!data.quick);
      scheduleOut(data.duration * 1000);
    },

    // A window moved: show the old layout, fly the icon, then show the new one.
    move(data) {
      const gen = interrupt();
      holding = !!data.hold;
      moving = true;
      const wasVisible = hud.classList.contains("in");
      const before = { ...data.before, showAppIcons: data.showAppIcons };
      const after = { ...data.after, showAppIcons: data.showAppIcons };
      renderTiles(before, false);
      popIn(data.theme);
      clearTimeout(outTimer);
      // Let the HUD finish springing in before the icon takes off.
      flightTimer = setTimeout(() => {
        fly(data.moved, before, () => {
          if (gen !== generation) return; // a newer show/move took over
          moving = false;
          renderTiles(after, false, data.moved.to);
          scheduleOut(data.duration * 1000);
        });
      }, wasVisible ? 0 : 260);
    },

    // The peek key was released.
    release() {
      holding = false;
      if (!moving) scheduleOut(0);
    },
  };
})();
