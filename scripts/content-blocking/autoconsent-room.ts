// Room's entry for DuckDuckGo's autoconsent (MPL-2.0): cookie banners are
// answered with an opt-out (Settings ▸ Privacy ▸ Cookie banners: Reject).
// Runs in Room's isolated world from document start in every frame
// (room/core/content_blocking/cosmetic_filter_agent.cc). Messages go to the
// native roomCookieSend(json); main-world evals come back through
// roomCookieReceive(message). Built by scripts/content-blocking-assets.sh
// into App/Resources/ContentBlocking/autoconsent-room.js.
import AutoConsent from '../lib/web';
import { filterCompactRules, type IndexedCMPRuleset } from '../lib/encoding';
import type { BackgroundMessage, ContentScriptMessage } from '../lib/messages';
import type { Config } from '../lib/types';
import compactRules from '../rules/compact-rules.json';

declare const roomCookieSend: (json: string) => void;

const scope = globalThis as unknown as {
    roomCookieReceive?: (message: BackgroundMessage) => Promise<void>;
};

if (typeof roomCookieSend === 'function' && !scope.roomCookieReceive) {
    const config: Partial<Config> = {
        enabled: true,
        autoAction: 'optOut',
        disabledCmps: [],
        enablePrehide: true,
        enableCosmeticRules: true,
        enableGeneratedRules: true,
        enableHeuristicDetection: true,
        detectRetries: 20,
        isMainWorld: false,
        prehideTimeout: 2000,
        enablePopupMutationObserver: false,
        visualTest: false,
        logs: {
            lifecycle: false,
            rulesteps: false,
            detectionsteps: false,
            evals: false,
            errors: false,
            messages: false,
            waits: false,
        },
    };
    const send = async (message: ContentScriptMessage) => {
        roomCookieSend(JSON.stringify(message));
    };
    const consent = new AutoConsent(send, config, {
        autoconsent: [],
        compact: filterCompactRules(compactRules as IndexedCMPRuleset, {
            url: window.location.href,
            mainFrame: window.top === window,
        }),
    });
    scope.roomCookieReceive = (message: BackgroundMessage) => consent.receiveMessageCallback(message);
}
