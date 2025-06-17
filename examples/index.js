// Renderer side for examples – tweak liquid glass
const { ipcRenderer } = require("electron");
const liquidGlass = require("../dist/index").default;

let viewId = null;

ipcRenderer.on("glass-ready", (_event, { viewId: id }) => {
  viewId = id;
});

function send(type, value) {
  if (viewId == null) return;
  ipcRenderer.send("glass-set", { type, value });
}

function buildButtons(containerId, type, values) {
  const container = document.getElementById(containerId);
  values.forEach((v) => {
    const btn = document.createElement("button");
    btn.textContent = typeof v === "object" && v.name !== undefined ? v.name : String(v);
    btn.addEventListener("click", () => {
      const value = typeof v === "object" && v.value !== undefined ? v.value : v;
      send(type, value);
      [...container.children].forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
    });
    container.appendChild(btn);
  });
}
console.log(liquidGlass);

// Only expose production-safe settings
buildButtons(
  "variant-buttons",
  "variant",
  Object.entries(liquidGlass.GlassMaterialVariant).map(([name, value]) => {
    return { name, value };
  })
);
buildButtons("scrim-buttons", "scrim", [0, 1]);
buildButtons("subdued-buttons", "subdued", [0, 1]);
