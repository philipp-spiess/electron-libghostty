import { app, BrowserWindow, screen, ipcMain } from "electron";
import myAddon from "../dist/index.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

let mainWindow: BrowserWindow;

let viewId: number | null = null;

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
    frame: false,
    transparent: true,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, "../examples/index.html"));

  // Once the DOM/renderer is ready show the glass effect
  mainWindow.webContents.once("did-finish-load", () => {
    try {
      if (!myAddon) {
        console.error("myAddon is not loaded");
        return;
      }

      viewId = myAddon.addView(mainWindow.getNativeWindowHandle(), {
        // opaque: true, // Add opaque background behind glass effect
        // cornerRadius: 24,
      });
      mainWindow.setWindowButtonVisibility(true); // restore traffic lights

      // Inform renderer that glass view is ready
      mainWindow.webContents.send("glass-ready", { viewId });
    } catch (err) {
      console.error("addView failed:", err);
    }
  });
});

// Listen for renderer tweaks
ipcMain.on("glass-set", (_event, { type, value }) => {
  if (viewId === null) return;
  try {
    switch (type) {
      case "variant":
        myAddon.unstable_setVariant(viewId, value ?? 0);
        break;
      case "scrim":
        myAddon.unstable_setScrim(viewId, value);
        break;
      case "subdued":
        myAddon.unstable_setSubdued(viewId, value);
        break;
    }
  } catch (err) {
    console.error("glass-set failed", err);
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
    /* re-create */
    mainWindow = new BrowserWindow({ width: 800, height: 600 });
    mainWindow.loadFile(path.join(__dirname, "index.html"));
  }
});
