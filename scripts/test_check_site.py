#!/usr/bin/env python3
"""Tests for scripts/check_site.py on tiny sites written to a temporary folder. No network.
Run: python3 -I scripts/test_check_site.py"""
import os, sys, tempfile, unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_site


def page(title="DeckBridge", description="A bridge.", body="", head=""):
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8"><title>{title}</title>'
            f'<meta name="description" content="{description}">{head}</head><body>{body}</body></html>')


def sitemap(*locs):
    urls = "".join(f"<url><loc>{loc}</loc></url>" for loc in locs)
    return f'<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">{urls}</urlset>'


GOOD = {
    "index.html": page(head='<link rel="stylesheet" href="style.css"><link rel="icon" href="img/icon.png">',
                       body='<a href="support/">Support</a> <a href="privacy/">Privacy</a> <img src="img/icon.png" alt="">'
                            ' <a href="https://testflight.apple.com/join/XXXX">TestFlight</a>'),
    "support/index.html": page(body='<a href="../">Home</a> <a href="../privacy/#network">Network</a>'),
    "privacy/index.html": page(body='<h2 id="network">Network</h2><p>DeckBridge collects no data.</p>'),
    "style.css": '@font-face { font-family: Inter; src: url("fonts/Inter-Regular.ttf"); } body { color: #EDEDEA; }',
    "fonts/Inter-Regular.ttf": "font",
    "img/icon.png": "png",
    "robots.txt": "User-agent: *\nAllow: /\nSitemap: https://getdeckbridge.app/sitemap.xml\n",
    "sitemap.xml": sitemap("https://getdeckbridge.app/"),
    "llms.txt": "# DeckBridge\n\n> A bridge.\n",
}


class CheckSiteTests(unittest.TestCase):
    def site(self, changes=None, remove=()):
        files = dict(GOOD)
        files.update(changes or {})
        for name in remove:
            files.pop(name)
        root = tempfile.mkdtemp()
        for name, text in files.items():
            path = os.path.join(root, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(text)
        return root

    def test_a_good_site_passes(self):
        self.assertEqual(check_site.problems(self.site()), [])

    def test_a_missing_page_fails(self):
        self.assertEqual(check_site.problems(self.site(remove=["privacy/index.html"])),
                         ["privacy/index.html: missing",
                          "index.html: link to privacy/ doesn't resolve",
                          "support/index.html: link to ../privacy/#network doesn't resolve"])

    def test_a_broken_link_or_asset_fails(self):
        root = self.site({"support/index.html": page(body='<a href="../faq/">FAQ</a> <img src="../img/nope.png" alt="">')})
        self.assertEqual(check_site.problems(root), ["support/index.html: link to ../faq/ doesn't resolve",
                                                     "support/index.html: link to ../img/nope.png doesn't resolve"])

    def test_a_css_url_that_doesnt_resolve_fails(self):
        root = self.site({"style.css": '@font-face { src: url("fonts/Missing.ttf"); }'})
        self.assertEqual(check_site.problems(root), ["style.css: link to fonts/Missing.ttf doesn't resolve"])

    def test_external_resources_fail_but_external_links_dont(self):
        root = self.site({
            "index.html": page(head='<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Inter">',
                               body='<img src="//cdn.example.com/a.png" alt=""> <script src="http://x.example/t.js"></script>'
                                    ' <a href="https://testflight.apple.com/join/XXXX">ok</a>'
                                    ' <a href="support/">s</a> <a href="privacy/">p</a>'),
            "style.css": '@import url("https://fonts.example/x.css"); body { background: url(https://x.example/bg.png); }',
        })
        self.assertEqual(check_site.problems(root), [
            "index.html: loads https://fonts.googleapis.com/css?family=Inter from another site",
            "index.html: loads //cdn.example.com/a.png from another site",
            "index.html: loads http://x.example/t.js from another site",
            "style.css: loads https://fonts.example/x.css from another site",
            "style.css: loads https://x.example/bg.png from another site",
        ])

    def test_canonical_and_alternate_links_are_links_not_loads(self):
        root = self.site({"index.html": GOOD["index.html"].replace(
            "</head>", '<link rel="canonical" href="https://getdeckbridge.app/">'
                       '<link rel="Alternate" type="text/markdown" href="https://getdeckbridge.app/index.md"></head>')})
        self.assertEqual(check_site.problems(root), [])

    def test_external_stylesheets_icons_and_preloads_still_fail(self):
        root = self.site({"index.html": GOOD["index.html"].replace(
            "</head>", '<link rel="alternate stylesheet" href="https://x.example/a.css">'
                       '<link rel="icon" href="https://x.example/i.png">'
                       '<link rel="preload" as="font" href="https://x.example/f.woff2">'
                       '<link href="https://x.example/norel.css"></head>')})
        self.assertEqual(check_site.problems(root), [
            "index.html: loads https://x.example/a.css from another site",
            "index.html: loads https://x.example/i.png from another site",
            "index.html: loads https://x.example/f.woff2 from another site",
            "index.html: loads https://x.example/norel.css from another site",
        ])

    def test_every_image_has_alt_text_even_if_empty(self):
        root = self.site({"support/index.html": page(
            body='<a href="../">Home</a> <img src="../img/icon.png"> <img src="../img/icon.png" alt="">'
                 ' <img src="../img/icon.png" alt="The app icon">')})
        self.assertEqual(check_site.problems(root), ["support/index.html: <img src=\"../img/icon.png\"> has no alt"])

    def test_json_ld_blocks_must_parse(self):
        good = '<script type="application/ld+json">{"@context": "https://schema.org", "@type": "SoftwareApplication"}</script>'
        bad = '<script type="Application/LD+JSON">{"@type": "FAQPage",}</script>'
        root = self.site({"support/index.html": page(head=good + bad, body='<a href="../">Home</a>')})
        found = check_site.problems(root)
        self.assertEqual(len(found), 1, found)
        self.assertTrue(found[0].startswith("support/index.html: JSON-LD block 2 doesn't parse: "), found)

    def test_valid_json_ld_passes(self):
        block = '<script type="application/ld+json">{"name": "DeckBridge &amp; <b>", "a": [1, 2]}</script>'
        root = self.site({"support/index.html": page(head=block, body='<a href="../">Home</a>')})
        self.assertEqual(check_site.problems(root), [])

    def test_robots_sitemap_and_llms_txt_must_exist(self):
        root = self.site(remove=["robots.txt", "sitemap.xml", "llms.txt"])
        self.assertEqual(check_site.problems(root), ["robots.txt: missing", "sitemap.xml: missing", "llms.txt: missing"])

    def test_a_sitemap_that_isnt_xml_fails(self):
        found = check_site.problems(self.site({"sitemap.xml": "<urlset><url><loc>https://getdeckbridge.app/</loc></urlset>"}))
        self.assertEqual(len(found), 1, found)
        self.assertTrue(found[0].startswith("sitemap.xml: doesn't parse as XML: "), found)

    def test_a_sitemap_with_no_pages_fails(self):
        self.assertEqual(check_site.problems(self.site({"sitemap.xml": sitemap()})), ["sitemap.xml: lists no pages"])

    def test_every_sitemap_url_is_on_the_site_and_is_a_page(self):
        root = self.site({"sitemap.xml": sitemap(
            "https://getdeckbridge.app/", "https://getdeckbridge.app/support/", "https://getdeckbridge.app/privacy/index.html",
            "http://getdeckbridge.app/", "https://example.com/", "https://getdeckbridge.app.evil.example/",
            "https://getdeckbridge.app/faq/", "https://getdeckbridge.app/img/nope.png")})
        self.assertEqual(check_site.problems(root), [
            "sitemap.xml: http://getdeckbridge.app/ isn't under https://getdeckbridge.app/",
            "sitemap.xml: https://example.com/ isn't under https://getdeckbridge.app/",
            "sitemap.xml: https://getdeckbridge.app.evil.example/ isn't under https://getdeckbridge.app/",
            "sitemap.xml: https://getdeckbridge.app/faq/ isn't a page in the site",
            "sitemap.xml: https://getdeckbridge.app/img/nope.png isn't a page in the site",
        ])

    def test_llms_txt_starts_with_the_product_name(self):
        root = self.site({"llms.txt": "# Controller Bridge\n\n> A bridge.\n"})
        self.assertEqual(check_site.problems(root), ['llms.txt: doesn\'t start with "# DeckBridge"'])

    def test_a_page_without_a_title_or_description_fails(self):
        root = self.site({"support/index.html": page(title="", description="", body='<a href="../">Home</a>')})
        self.assertEqual(check_site.problems(root), ["support/index.html: no <title>",
                                                     "support/index.html: no meta description"])

    def test_the_privacy_page_must_say_no_data_is_collected(self):
        root = self.site({"privacy/index.html": page(body="<p>We care about your privacy.</p>")})
        self.assertEqual(check_site.problems(root), ['privacy/index.html: doesn\'t say "collects no data"'])

    def test_a_third_party_logo_file_fails(self):
        root = self.site({"img/denon-logo.svg": "<svg/>", "img/Syndicate_logo.png": "png"})
        self.assertEqual(check_site.problems(root), ["img/Syndicate_logo.png: looks like another company's logo",
                                                     "img/denon-logo.svg: looks like another company's logo"])


    def test_titles_and_headings_dont_use_other_companies_names(self):
        root = self.site({
            "support/index.html": page(title="Syndicate Bridge Support", body='<h1>Denon <em>Controller</em> Help</h1><a href="../">Home</a>'),
            "privacy/index.html": page(body="<h1>Privacy</h1><p>Works with Syndicate. DeckBridge collects no data.</p>"),
        })
        self.assertEqual(check_site.problems(root), ['support/index.html: the <title> names Syndicate',
                                                     'support/index.html: the <h1> names Denon'])

    def test_a_site_over_two_megabytes_fails(self):
        root = self.site({"img/huge.png": "x" * 2_100_000})
        self.assertEqual(check_site.problems(root), ["the site is 2.1 MB, over 2 MB"])


if __name__ == "__main__":
    unittest.main()
