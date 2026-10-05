// Phase 3.6b fixture: the popup resizes itself 400 ms after loading (the
// host's popover follows the page's auto-resize) and records that it opened.
const opened = Date.now();
chrome.storage.local.set({ popupOpened: opened });
document.getElementById("state").textContent = "popup open " + location.search;
setTimeout(() => {
  document.body.style.width = "360px";
  document.getElementById("grow").style.height = "220px";
  document.getElementById("state").textContent = "popup grown";
}, 400);
