chrome.storage.local.set({ optionsOpened: Date.now() }).then(() => {
  document.getElementById("state").textContent = "storage written";
});
