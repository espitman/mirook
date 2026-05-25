const { contextBridge, ipcRenderer, webUtils } = require("electron");

contextBridge.exposeInMainWorld("mirook", {
  openBook: () => ipcRenderer.invoke("book:open"),
  openBookPath: (filePath) => ipcRenderer.invoke("book:openPath", filePath),
  getPathForFile: (file) => webUtils.getPathForFile(file),
  toggleWindowZoom: () => ipcRenderer.invoke("window:toggleZoom")
});
