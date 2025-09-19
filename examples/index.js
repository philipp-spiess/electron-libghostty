const { ipcRenderer } = require("electron");

const TARGET_SELECTOR = "#overlay-target";
const LOG_SELECTOR = "#keyboard-log";
const LOG_MAX_ENTRIES = 20;

function getTargetRect() {
  const target = document.querySelector(TARGET_SELECTOR);
  if (!target) {
    return null;
  }

  const rect = target.getBoundingClientRect();
  const scale = window.devicePixelRatio || 1;

  return {
    x: rect.x,
    y: rect.y,
    width: rect.width,
    height: rect.height,
    scale,
  };
}

let pending = false;

function flushRect() {
  pending = false;
  const rect = getTargetRect();
  if (rect) {
    ipcRenderer.send("native-overlay:update", rect);
  } else {
    ipcRenderer.send("native-overlay:hide");
  }
}

function scheduleRectUpdate() {
  if (pending) return;
  pending = true;
  queueMicrotask(flushRect);
}

window.addEventListener("DOMContentLoaded", () => {
  const target = document.querySelector(TARGET_SELECTOR);
  const logContainer = document.querySelector(LOG_SELECTOR);

  if (logContainer) {
    logContainer.textContent = "Keyboard events will appear here.";

    const appendLog = (event) => {
      if (!logContainer) return;

      if (!logContainer.dataset.hasEvents) {
        logContainer.textContent = "";
        logContainer.dataset.hasEvents = "true";
      }

      const entry = document.createElement("div");
      entry.textContent = `${new Date().toLocaleTimeString()} key=${event.key} code=${event.code} target=${event.target?.tagName?.toLowerCase()}`;

      // Prepend newest entries to keep recent events visible.
      logContainer.prepend(entry);
      while (logContainer.childNodes.length > LOG_MAX_ENTRIES) {
        logContainer.removeChild(logContainer.lastChild);
      }
    };

    window.addEventListener(
      "keydown",
      (event) => {
        appendLog(event);
      },
      true
    );
  }

  if (target && window.ResizeObserver) {
    const resizeObserver = new ResizeObserver(() => scheduleRectUpdate());
    resizeObserver.observe(target);
  }

  window.addEventListener("scroll", scheduleRectUpdate, { passive: true });
  window.addEventListener("resize", scheduleRectUpdate);

  ipcRenderer.on("native-overlay:request-bounds", () => scheduleRectUpdate());

  scheduleRectUpdate();
});
