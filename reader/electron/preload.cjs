const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("mirook", {
  openBook: () => ipcRenderer.invoke("book:open"),
  openBookPath: (filePath) => ipcRenderer.invoke("book:openPath", filePath)
});
