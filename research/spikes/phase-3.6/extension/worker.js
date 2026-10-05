// Phase 3.6 fixture: the service worker answers the content script with
// what chrome.tabs sees (Room's tabs through the Browser's TabStripModel) and
// shows the count as the action's badge; on request it opens the action's
// popup (action.openPopup, 3.6b); its named command calls sidePanel.open and
// reports both in the action's title, which the host reads.
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
  if (message && message.q === "openPopup") {
    chrome.action.openPopup().then(() => reply("opened"), (error) => reply("error: " + error.message));
    return true;
  }
  return false;
});
chrome.commands.onCommand.addListener(async (command, tab) => {
  let panel = "not tried";
  try {
    await chrome.sidePanel.open({ tabId: tab.id });
    panel = "opened";
  } catch (error) {
    panel = "error: " + error.message;
  }
  await chrome.storage.local.set({ lastCommand: command, sidePanel: panel });
  await chrome.action.setTitle({ title: "command:" + command + " | sidePanel:" + panel });
});
