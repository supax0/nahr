// Progressive enhancement: every page works without JavaScript. With it, the
// live numbers refresh from /api/status (the GET /api/status lines in the
// server log, every 5 seconds while the tab is visible) and the like button
// posts to /api/like without reloading the page.
const lang = document.documentElement.lang || "en";
const numbers = new Intl.NumberFormat(lang);
const $ = (id) => document.getElementById(id);

function duration(seconds) {
  const unit = seconds < 60 ? "second" : seconds < 3600 ? "minute" : "hour";
  const value = unit === "second" ? seconds : unit === "minute" ? seconds / 60 : seconds / 3600;
  return new Intl.NumberFormat(lang, { style: "unit", unit, unitDisplay: "long", maximumFractionDigits: 0 })
    .format(Math.floor(value));
}

function show(status) {
  if ($("visits")) $("visits").textContent = numbers.format(status.visits);
  if ($("likes")) $("likes").textContent = numbers.format(status.likes);
  if ($("uptime")) $("uptime").textContent = duration(status.uptime_seconds);
}

async function refresh() {
  try {
    const response = await fetch("/api/status", { headers: { accept: "application/json" } });
    if (response.ok) show(await response.json());
  } catch (_) {
    // Offline or server stopped: keep the last numbers.
  }
}

const like = $("like");
if (like) {
  like.addEventListener("click", async () => {
    like.disabled = true;
    try {
      const response = await fetch("/api/like", { method: "POST" });
      if (response.ok) {
        const body = await response.json();
        $("likes").textContent = numbers.format(body.likes);
      }
    } finally {
      like.disabled = false;
    }
  });
}

// Poll every 5 seconds only while the page is visible; a hidden tab sends
// nothing, and coming back refreshes at once.
let timer = null;
function start() {
  if (timer === null) {
    refresh();
    timer = setInterval(refresh, 5000);
  }
}
function stop() {
  if (timer !== null) {
    clearInterval(timer);
    timer = null;
  }
}
document.addEventListener("visibilitychange", () => (document.hidden ? stop() : start()));
if (!document.hidden) start();
