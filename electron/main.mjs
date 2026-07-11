import { app, BrowserWindow, shell } from "electron";
import path from "node:path";
import { fileURLToPath } from "node:url";
import serve from "electron-serve";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ELECTRON_DEV=1 → load the Next.js dev server.
// Otherwise serve the static export from out/ (preview + packaged builds).
const useDevServer = process.env.ELECTRON_DEV === "1";
const DEV_URL = process.env.ELECTRON_START_URL || "http://localhost:3000";

// Must be registered before app is ready.
const loadProductionURL = useDevServer
  ? null
  : serve({ directory: "out" });

/** @type {import('electron').BrowserWindow | null} */
let mainWindow = null;

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 840,
    minWidth: 960,
    minHeight: 640,
    title: "Dimo",
    show: false,
    backgroundColor: "#f5f8f6",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.once("ready-to-show", () => {
    mainWindow?.show();
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });

  if (useDevServer) {
    mainWindow.loadURL(DEV_URL);
    mainWindow.webContents.on("did-fail-load", () => {
      // Next may still be booting when Electron starts.
      setTimeout(() => mainWindow?.loadURL(DEV_URL), 750);
    });
  } else {
    await loadProductionURL(mainWindow);
  }

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

app.whenReady().then(async () => {
  await createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      void createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
