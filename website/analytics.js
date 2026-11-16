/* Visit counts for getdeckbridge.app, in the PostHog project "Owned Sites" (shared with Eric's other sites; filter by
   $host). Copied from showrecorder.app's lib/analytics.ts: pageviews and a few named link clicks, no cookies or local
   storage (persistence "memory"), no autocapture, no session recordings, no surveys, no person profiles for visitors.
   cookieless_mode "always" sends no ID from the browser: PostHog derives visitor and session from a hash of IP, browser
   and a salt it rotates daily. The privacy page says so (privacy/#website), and scripts/check_site.py holds it to that.
   The key is PostHog's public project key, meant to be in page source; it can only send events.
   It loads only on getdeckbridge.app (and www.), so the preview server (127.0.0.1) and the taste-skill gate's headless Chrome never
   send events. Eric's own visits: opening any page with ?internal=1 marks that browser (one localStorage key, set only
   by that link) and PostHog never loads there again; ?internal=0 clears it. Ordinary visitors get nothing stored. If
   storage is blocked, the visit is simply counted.
   Tested by scripts/test_analytics.mjs. */
(function () {
  var HOSTS = ["getdeckbridge.app", "www.getdeckbridge.app"];  // www: the host still serves it, not only a redirect
  var INTERNAL_KEY = "deckbridge_internal";
  var KEY = "phc_uzsUUTbN2k3EJVDvtTGBtrRgPmdWrRxzxbLZcsw7Vvm4";
  var OPTIONS = {
    api_host: "https://us.i.posthog.com",
    persistence: "memory",
    cookieless_mode: "always",
    autocapture: false,
    capture_pageview: true,
    capture_pageleave: false,
    disable_session_recording: true,
    disable_surveys: true,
    person_profiles: "identified_only",
    // "Owned Sites" turns these on at the project level for the other sites; off here.
    enable_heatmaps: false,
    capture_heatmaps: false,
    capture_dead_clicks: false,
    capture_performance: false,
    capture_exceptions: false
  };

  if (HOSTS.indexOf(window.location.hostname) < 0) return;
  var internal = false;
  try {
    var flag = new URLSearchParams(window.location.search).get("internal");
    if (flag === "1") window.localStorage.setItem(INTERNAL_KEY, "1");
    if (flag === "0") window.localStorage.removeItem(INTERNAL_KEY);
    internal = window.localStorage.getItem(INTERNAL_KEY) === "1";
  } catch (e) {}
  if (internal) return;

  // PostHog's standard loader snippet: it queues calls until https://us-assets.i.posthog.com/static/array.js loads.
  !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]);t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com"),p.src+="/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString()+" (stub)"},n="capture identify alias on off once set_config people.set people.set_once unset increment append union track_links track_forms track_pageview register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags addEarlyAccessFeatureCallback updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys getNextSurveyStep".split(" "),o=0;o<n.length;o++)g(u,n[o]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
  window.posthog.init(KEY, OPTIONS);

  // Named click events (autocapture stays off). A link with data-track="<event>" sends posthog.capture(event, { path }),
  // plus { destination } when it has data-track-destination. Only these events; check_site makes every mailto link carry one.
  var EVENTS = ["join_beta_clicked", "contact_email_clicked", "setup_guide_clicked", "app_store_clicked"];
  document.addEventListener("click", function (e) {
    var el = e.target && e.target.closest ? e.target.closest("a[data-track]") : null;
    if (!el || !window.posthog) return;
    var name = el.getAttribute("data-track");
    if (EVENTS.indexOf(name) < 0) return;
    var props = { path: window.location.pathname };
    var destination = el.getAttribute("data-track-destination");
    if (destination) props.destination = destination;
    try { window.posthog.capture(name, props); } catch (err) {}
  }, true);
})();
