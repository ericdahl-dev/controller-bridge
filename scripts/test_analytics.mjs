// Tests for website/analytics.js, run in a fake browser (node:vm). No network.
// Run: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const SOURCE = readFileSync(new URL("../website/analytics.js", import.meta.url), "utf8");

// Runs analytics.js on a fake page. Returns the window (posthog's queue is window.posthog._i), the scripts the
// loader inserted, and the click listener it added.
function load({ hostname = "getdeckbridge.app", search = "", pathname = "/" } = {}) {
  const inserted = [];
  let listener = null;
  const document = {
    createElement: () => ({}),
    getElementsByTagName: () => [{ parentNode: { insertBefore: (el) => inserted.push(el) } }],
    addEventListener: (_type, handler) => { listener = handler; },
  };
  const window = { location: { hostname, search, pathname }, document, URLSearchParams };
  window.window = window;
  vm.createContext(window);
  vm.runInContext(SOURCE, window);
  return { window, inserted, listener };
}

test("starts PostHog with the public project key and ShowRecorder's cookieless options", () => {
  const { window, inserted } = load();
  assert.equal(inserted.length, 1);
  assert.equal(inserted[0].src, "https://us-assets.i.posthog.com/static/array.js");
  assert.equal(window.posthog._i.length, 1);
  const [key, options] = window.posthog._i[0];
  assert.equal(key, "phc_uzsUUTbN2k3EJVDvtTGBtrRgPmdWrRxzxbLZcsw7Vvm4");
  assert.deepEqual({ ...options }, {
    api_host: "https://us.i.posthog.com",
    persistence: "memory",
    cookieless_mode: "always",
    autocapture: false,
    capture_pageview: true,
    capture_pageleave: false,
    disable_session_recording: true,
    disable_surveys: true,
    person_profiles: "identified_only",
    enable_heatmaps: false,
    capture_heatmaps: false,
    capture_dead_clicks: false,
    capture_performance: false,
    capture_exceptions: false,
  });
});
