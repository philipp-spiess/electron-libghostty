import { app, BrowserWindow, screen, ipcMain } from "electron";
import type { WebContents } from "electron";
import nativeOverlay from "../dist/index.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

type OverlayPayload = {
  x: number;
  y: number;
  width: number;
  height: number;
  scale?: number;
};

let mainWindow: BrowserWindow;
let overlayId: number | null = null;

const __dirname = path.dirname(fileURLToPath(import.meta.url));

app.whenReady().then(() => {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    x:
      screen.getPrimaryDisplay().workArea.x +
      screen.getPrimaryDisplay().workArea.width -
      800,
    y: screen.getPrimaryDisplay().workArea.y + 100,
    frame: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, "../examples/index.html"));

  mainWindow.webContents.once("did-finish-load", () => {
    mainWindow.webContents.send("native-overlay:request-bounds");
  });
});

const toOverlayFrame = (rect: OverlayPayload, webContents: WebContents) => {
  const zoom = webContents.getZoomFactor() || 1;
  return {
    x: rect.x / zoom,
    y: rect.y / zoom,
    width: rect.width / zoom,
    height: rect.height / zoom,
    scale: rect.scale,
  };
};

ipcMain.on("native-overlay:update", (_event, rect: OverlayPayload) => {
  if (!mainWindow) return;
  if (!rect) return;

  try {
    const frame = toOverlayFrame(rect, mainWindow.webContents);

    if (overlayId === null) {
      overlayId = nativeOverlay.create(
        mainWindow.getNativeWindowHandle(),
        frame
      );
      return;
    }

    nativeOverlay.update(overlayId, frame);
  } catch (err) {
    console.error("native-overlay:update failed", err);
  }
});

ipcMain.on("native-overlay:hide", () => {
  if (overlayId === null) {
    return;
  }

  try {
    nativeOverlay.remove(overlayId);
  } catch (err) {
    console.error("native-overlay:hide failed", err);
  } finally {
    overlayId = null;
  }
});

// Standard quit handling
app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    mainWindow = new BrowserWindow({ width: 800, height: 600 });
    mainWindow.loadFile(path.join(__dirname, "index.html"));
  }
});
