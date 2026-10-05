// Phase 3.6a fixture: marks the page and asks the worker what chrome.tabs sees.
document.documentElement.dataset.roomFixture36 = "content-script-ran";
chrome.runtime.sendMessage({ q: "tabs" }).then((answer) => {
  document.documentElement.dataset.roomFixtureTabs = String(answer.tabs);
  document.documentElement.dataset.roomFixtureWindows = String(answer.windows);
  document.documentElement.dataset.roomFixtureUrls = JSON.stringify(answer.urls);
}).catch((error) => {
  document.documentElement.dataset.roomFixtureTabs = "error: " + error;
});
