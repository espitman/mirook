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
  summarizePages: (request) => ipcRenderer.invoke("reader:summarizePages", request),
  generateTextFromNotes: (request) => ipcRenderer.invoke("reader:generateTextFromNotes", request),
  deleteAiOutput: (id) => ipcRenderer.invoke("reader:deleteAiOutput", id),
  getAiSettings: () => ipcRenderer.invoke("settings:getAi"),
  saveAiSettings: (settings) => ipcRenderer.invoke("settings:saveAi", settings)
});
