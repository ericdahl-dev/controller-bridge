#!/usr/bin/env python3
"""Checks the DeckBridge website (#169) before anyone looks at it or it's published:
- every page exists, and every internal link and asset resolves
- robots.txt, sitemap.xml and llms.txt are at the root; the sitemap parses, and each URL in it
  is under https://getdeckbridge.app/ and is a page in the site; llms.txt starts with "# DeckBridge"
- nothing is loaded from another site (fonts, images, styles, scripts are all local); links out are fine,
  and so are <link rel="canonical"> and <link rel="alternate">. The one exception is the PostHog loader script
  (POSTHOG_LOADER), which website/analytics.js adds to count visits; the privacy page discloses it
- every page has a title and a meta description
- every <img> has an alt attribute (alt="" for a decorative one)
- every <script type="application/ld+json"> block parses as JSON
- no page title or main heading uses another company's name as the product's
- the privacy page says the app collects no data, and discloses the website's PostHog visit counts as
  showrecorder.app's does (PRIVACY_STATEMENTS)
- no other company's logo is in the site
- the whole site stays under 2 MB
Standard library only. Run: python3 -I scripts/check_site.py [website]   (exits 1 on any problem)
Tested by scripts/test_check_site.py."""
import json, os, re, sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from urllib.parse import urlsplit

PAGES = ["index.html", "support/index.html", "privacy/index.html"]
ROOT_FILES = ["robots.txt", "sitemap.xml", "llms.txt"]
SITE = "https://getdeckbridge.app/"
LLMS_HEADING = "# DeckBridge"
PRIVACY = "privacy/index.html"
PRIVACY_STATEMENTS = [
    "collects no data",  # the app
    # the website: cookieless PostHog (persistence memory, cookieless_mode always), worded as showrecorder.app's
    "posthog", "no cookies", "anonymous hash that changes every day", "does not keep the address",
    "counts clicks on a few links", "to have your visits removed, email",
]
OTHER_COMPANIES = ["Syndicate", "Denon"]
MAX_BYTES = 2_000_000
POSTHOG_LOADER = "https://us-assets.i.posthog.com/static/array.js"  # allowed only as a <script src>
LINK_RELS = {"canonical", "alternate"}  # a <link> with only these rels points somewhere; any other rel loads it


def is_external(url):
    return url.startswith(("http:", "https:", "//"))


def skip(url):
    return url == "" or url.startswith(("#", "mailto:", "tel:", "data:"))


class Page(HTMLParser):
    """The parts of a page the checks need, in document order."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title, self.h1, self.description = None, None, None
        self.text = []
        self.refs = []  # (url, loaded): loaded is "script" for a <script src>, True for other resources, False for links
        self.no_alt = []  # src of every <img> without an alt attribute
        self.json_ld = []  # the text of each <script type="application/ld+json">
        self._in = None
        self._ld = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ("title", "h1"):
            self._in = tag
            setattr(self, tag, getattr(self, tag) or "")
        if tag == "meta" and (attrs.get("name") or "").lower() == "description":
            self.description = (attrs.get("content") or "").strip()
        if tag == "a" and attrs.get("href") is not None:
            self.refs.append((attrs["href"], False))
        if tag == "link" and attrs.get("href") is not None:
            rels = (attrs.get("rel") or "").lower().split()
            self.refs.append((attrs["href"], not rels or not set(rels) <= LINK_RELS))
        if tag == "script" and (attrs.get("type") or "").strip().lower() == "application/ld+json":
            self._ld = []
        if tag == "img" and "alt" not in attrs:
            self.no_alt.append(attrs.get("src") or "")
        if attrs.get("src") is not None:
            self.refs.append((attrs["src"], "script" if tag == "script" else True))

    def handle_endtag(self, tag):
        if tag == self._in:
            self._in = None
        if tag == "script" and self._ld is not None:
            self.json_ld.append("".join(self._ld))
            self._ld = None

    def handle_data(self, data):
        if self._ld is not None:
            self._ld.append(data)
            return
        self.text.append(data)
        if self._in:
            setattr(self, self._in, getattr(self, self._in) + data)


CSS_REFS = re.compile(r"""url\(\s*['"]?([^'")\s]+)['"]?\s*\)|@import\s+['"]([^'"]+)['"]""")
CSS_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
CSS_DATA_URI = re.compile(r"""url\(\s*(['"])data:.*?\1\s*\)""", re.DOTALL)  # an inline picture, with its own url(#id)s


def css_refs(css):
    """The url() and @import references a stylesheet makes, leaving out its comments and inline data: pictures."""
    return [a or b for a, b in CSS_REFS.findall(CSS_DATA_URI.sub("", CSS_COMMENT.sub("", css)))]


def resolves(root, file, url):
    path = urlsplit(url).path
    if path == "":
        return True
    target = os.path.normpath(os.path.join(os.path.dirname(os.path.join(root, file)), path))
    if not target.startswith(os.path.normpath(root)):
        return False
    if os.path.isdir(target):
        target = os.path.join(target, "index.html")
    return os.path.isfile(target)


def check_refs(root, file, refs):
    out = []
    for url, loaded in refs:
        if skip(url):
            continue
        if is_external(url):
            if loaded and not (loaded == "script" and url == POSTHOG_LOADER):
                out.append(f"{file}: loads {url} from another site")
        elif not resolves(root, file, url):
            out.append(f"{file}: link to {url} doesn't resolve")
    return out


def check_page(root, file, text):
    page = Page()
    page.feed(text)
    out = []
    if not (page.title or "").strip():
        out.append(f"{file}: no <title>")
    if not page.description:
        out.append(f"{file}: no meta description")
    for part, words in (("title", page.title), ("h1", page.h1)):
        for name in OTHER_COMPANIES:
            if words and re.search(rf"\b{name}\b", words, re.IGNORECASE):
                out.append(f"{file}: the <{part}> names {name}")
    out += [f'{file}: <img src="{src}"> has no alt' for src in page.no_alt]
    for n, block in enumerate(page.json_ld, 1):
        try:
            json.loads(block)
        except ValueError as e:
            out.append(f"{file}: JSON-LD block {n} doesn't parse: {e}")
    out += check_refs(root, file, page.refs)
    if file == PRIVACY:
        said = " ".join(" ".join(page.text).split()).lower()
        out += [f'{file}: doesn\'t say "{words}"' for words in PRIVACY_STATEMENTS if words not in said]
    return out


def check_sitemap(root, files):
    try:
        tree = ET.parse(os.path.join(root, "sitemap.xml"))
    except ET.ParseError as e:
        return [f"sitemap.xml: doesn't parse as XML: {e}"]
    locs = [(el.text or "").strip() for el in tree.iter() if el.tag.rsplit("}", 1)[-1] == "loc"]
    if not locs:
        return ["sitemap.xml: lists no pages"]
    out = []
    for loc in locs:
        if not loc.startswith(SITE):
            out.append(f"sitemap.xml: {loc} isn't under {SITE}")
            continue
        path = urlsplit(loc).path.lstrip("/")
        if path == "" or path.endswith("/"):
            path += "index.html"
        if not (path.endswith(".html") and path in files):
            out.append(f"sitemap.xml: {loc} isn't a page in the site")
    return out


def problems(root):
    files = sorted(os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/")
                   for d, _, names in os.walk(root) for f in names)
    out = [f"{page}: missing" for page in PAGES + ROOT_FILES if page not in files]
    size = 0
    for file in files:
        path = os.path.join(root, file)
        size += os.path.getsize(path)
        lower = os.path.basename(file).lower()
        if "logo" in lower and any(name.lower() in lower for name in OTHER_COMPANIES):
            out.append(f"{file}: looks like another company's logo")
        if file.endswith(".html"):
            with open(path, encoding="utf-8") as f:
                out += check_page(root, file, f.read())
        elif file.endswith(".css"):
            with open(path, encoding="utf-8") as f:
                css = f.read()
            out += check_refs(root, file, [(url, True) for url in css_refs(css)])
    if "llms.txt" in files:
        with open(os.path.join(root, "llms.txt"), encoding="utf-8") as f:
            if f.readline().rstrip() != LLMS_HEADING:
                out.append(f'llms.txt: doesn\'t start with "{LLMS_HEADING}"')
    if "sitemap.xml" in files:
        out += check_sitemap(root, files)
    if size > MAX_BYTES:
        out.append(f"the site is {size / 1_000_000:.1f} MB, over 2 MB")
    return out


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "website")
    found = problems(root)
    for problem in found:
        print("FAIL:", problem)
    print("== Site check passed" if not found else f"== {len(found)} site problem(s)")
    sys.exit(1 if found else 0)


if __name__ == "__main__":
    main()
