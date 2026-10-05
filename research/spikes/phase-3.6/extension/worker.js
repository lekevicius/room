// Phase 3.6a fixture: the service worker answers the content script with
// what chrome.tabs sees (Room's tabs through the Browser's TabStripModel) and
// shows the count as the action's badge.
chrome.runtime.onInstalled.addListener(() => {
  console.log("room 3.6 fixture worker installed");
  chrome.action.setBadgeBackgroundColor({ color: "#2f7de1" });
});
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message && message.q === "tabs") {
    chrome.tabs.query({}).then(async (tabs) => {
      const windows = await chrome.windows.getAll();
      const text = String(tabs.length);
      await chrome.action.setBadgeText({ text });
      if (sender.tab && sender.tab.id >= 0) {
        await chrome.action.setBadgeText({ tabId: sender.tab.id, text: "T" + text });
      }
      reply({ tabs: tabs.length, windows: windows.length, urls: tabs.map((t) => t.url || "") });
    });
    return true;
  }
  return false;
});
