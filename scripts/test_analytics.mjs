// Tests for website/analytics.js, run in a fake browser (node:vm). No network.
// Run: node --test scripts/
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const SOURCE = readFileSync(new URL("../website/analytics.js", import.meta.url), "utf8");

// Runs analytics.js on a fake page. Returns the window (posthog's queue is window.posthog._i), the scripts the
// loader inserted, and the click listener it added.
function load({ hostname = "getdeckbridge.app", search = "", pathname = "/", stored = null } = {}) {
  const store = new Map(stored === null ? [] : [["deckbridge_internal", stored]]);
  const localStorage = {
    getItem: (k) => store.get(k) ?? null,
    setItem: (k, v) => void store.set(k, String(v)),
    removeItem: (k) => void store.delete(k),
  };
  const inserted = [];
  let listener = null;
  const document = {
    createElement: () => ({}),
    getElementsByTagName: () => [{ parentNode: { insertBefore: (el) => inserted.push(el) } }],
    addEventListener: (_type, handler) => { listener = handler; },
  };
  const window = { location: { hostname, search, pathname }, document, localStorage, URLSearchParams };
  window.window = window;
  vm.createContext(window);
  vm.runInContext(SOURCE, window);
  return { window, inserted, listener, stored: store.get("deckbridge_internal") ?? null };
}

const loaded = (run) => run.inserted.length === 1 && run.window.posthog !== undefined;

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

test("loads for ordinary visitors on getdeckbridge.app and stores nothing", () => {
  const run = load();
  assert.equal(loaded(run), true);
  assert.equal(run.stored, null);
});

test("never loads anywhere but getdeckbridge.app: the preview server, the gate's headless Chrome, a copy", () => {
  for (const hostname of ["127.0.0.1", "localhost", "www.getdeckbridge.app", "getdeckbridge.app.example.com"]) {
    const run = load({ hostname });
    assert.equal(run.inserted.length, 0, hostname);
    assert.equal(run.window.posthog, undefined, hostname);
  }
});

test("?internal=1 marks the owner's browser and PostHog never loads there again", () => {
  assert.deepEqual([loaded(load({ search: "?internal=1" })), load({ search: "?internal=1" }).stored], [false, "1"]);
  assert.equal(loaded(load({ stored: "1" })), false);
});

test("?internal=0 clears the mark", () => {
  const run = load({ search: "?internal=0", stored: "1" });
  assert.equal(loaded(run), true);
  assert.equal(run.stored, null);
});

test("blocked storage still counts the visit", () => {
  // a page whose localStorage throws, as in a private window with site data blocked
  const inserted = [];
  const document = { createElement: () => ({}), getElementsByTagName: () => [{ parentNode: { insertBefore: (el) => inserted.push(el) } }], addEventListener() {} };
  const window = { location: { hostname: "getdeckbridge.app", search: "?internal=1", pathname: "/" }, document, URLSearchParams };
  Object.defineProperty(window, "localStorage", { get() { throw new Error("SecurityError"); } });
  window.window = window;
  vm.createContext(window);
  vm.runInContext(SOURCE, window);
  assert.equal(inserted.length, 1);
  assert.notEqual(window.posthog, undefined);
});

// Clicks an element on a loaded page and returns what posthog.capture received.
function click(attrs, { pathname = "/", withPosthog = true } = {}) {
  const run = load({ pathname });
  const captured = [];
  run.window.posthog = withPosthog ? { capture: (name, props) => captured.push([name, { ...props }]) } : undefined;
  const el = attrs && { getAttribute: (k) => attrs[k] ?? null };
  run.listener({ target: { closest: () => el } });
  return captured;
}

test("a tagged link sends its event with the page it was on", () => {
  assert.deepEqual(click({ "data-track": "join_beta_clicked" }, { pathname: "/support/" }),
    [["join_beta_clicked", { path: "/support/" }]]);
  assert.deepEqual(click({ "data-track": "contact_email_clicked" }, { pathname: "/privacy/" }),
    [["contact_email_clicked", { path: "/privacy/" }]]);
  assert.deepEqual(click({ "data-track": "setup_guide_clicked" }), [["setup_guide_clicked", { path: "/" }]]);
  assert.deepEqual(click({ "data-track": "app_store_clicked" }), [["app_store_clicked", { path: "/" }]]);
});

test("adds the destination when the link names one", () => {
  assert.deepEqual(click({ "data-track": "join_beta_clicked", "data-track-destination": "email" }),
    [["join_beta_clicked", { path: "/", destination: "email" }]]);
});

test("ignores untagged links, other event names, clicks off a link, and a page without PostHog", () => {
  assert.deepEqual(click({ href: "support/" }), []);
  assert.deepEqual(click({ "data-track": "anything_else" }), []);
  assert.deepEqual(click(null), []);
  assert.deepEqual(click({ "data-track": "join_beta_clicked" }, { withPosthog: false }), []);
});

test("adds no click listener where PostHog doesn't load", () => {
  assert.equal(load({ hostname: "127.0.0.1" }).listener, null);
  assert.equal(load({ stored: "1" }).listener, null);
});
