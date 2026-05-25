const { contextBridge, ipcRenderer, webUtils } = require("electron");

contextBridge.exposeInMainWorld("mirook", {
  openBook: () => ipcRenderer.invoke("book:open"),
  openBookPath: (filePath) => ipcRenderer.invoke("book:openPath", filePath),
  getPathForFile: (file) => webUtils.getPathForFile(file),
  toggleWindowZoom: () => ipcRenderer.invoke("window:toggleZoom"),
  saveReadingPosition: (position) => ipcRenderer.invoke("reader:savePosition", position),
  exportBookData: (bookId) => ipcRenderer.invoke("reader:exportBookData", bookId),
  saveAnnotation: (annotation) => ipcRenderer.invoke("reader:saveAnnotation", annotation),
  deleteAnnotation: (id) => ipcRenderer.invoke("reader:deleteAnnotation", id),
  getAiSettings: () => ipcRenderer.invoke("settings:getAi"),
  saveAiSettings: (settings) => ipcRenderer.invoke("settings:saveAi", settings)
});
