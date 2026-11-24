(() => {
  const hud = document.getElementById("hud");
  const tiles = document.getElementById("tiles");
  const MAX_ICONS = 4; // a tile shows a 2x2 grid, the 4th slot becomes "+N" on overflow
  let outTimer = null;
  let lastActiveLeft = null;

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

  function renderTiles(data) {
    tiles.innerHTML = "";
    const active = document.createElement("div");
    active.className = "tile-active";
    tiles.appendChild(active);

    let activeTile = null;
    data.workspaces.forEach(ws => {
      const isActive = ws.name === data.workspace;
      const tile = document.createElement("div");
      tile.className = "tile" + (ws.occupied ? " occupied" : "") + (isActive ? " active" : "");

      const icons = document.createElement("div");
      icons.className = "tile-icons";
      renderIcons(icons, ws, data, isActive);
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

  window.hud = {
    show(data) {
      document.body.className = `theme-${data.theme}`;

      renderTiles(data);

      hud.classList.remove("out");
      if (!hud.classList.contains("in") || hud.style.opacity === "0") {
        restart(hud, "in");
      }

      clearTimeout(outTimer);
      outTimer = setTimeout(() => {
        hud.classList.remove("in");
        restart(hud, "out");
      }, data.duration * 1000);
    },
  };
})();
