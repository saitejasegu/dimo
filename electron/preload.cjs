const { contextBridge } = require("electron");

contextBridge.exposeInMainWorld("dimoDesktop", {
  isElectron: true,
  platform: process.platform,
});
