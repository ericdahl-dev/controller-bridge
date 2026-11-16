#!/usr/bin/env python3
"""Checks the DeckBridge website (#169) before anyone looks at it or it's published:
- every page exists, and every internal link and asset resolves
- nothing is loaded from another site (fonts, images, styles, scripts are all local); links out are fine,
  and so are <link rel="canonical"> and <link rel="alternate">
- every page has a title and a meta description
- every <img> has an alt attribute (alt="" for a decorative one)
- no page title or main heading uses another company's name as the product's
- the privacy page says the app collects no data
- no other company's logo is in the site
- the whole site stays under 2 MB
Standard library only. Run: python3 -I scripts/check_site.py [website]   (exits 1 on any problem)
Tested by scripts/test_check_site.py."""
import os, re, sys
from html.parser import HTMLParser
from urllib.parse import urlsplit

PAGES = ["index.html", "support/index.html", "privacy/index.html"]
PRIVACY = "privacy/index.html"
PRIVACY_STATEMENT = "collects no data"
OTHER_COMPANIES = ["Syndicate", "Denon"]
MAX_BYTES = 2_000_000
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
        self.refs = []  # (url, loaded): loaded is True for resources, False for links
        self.no_alt = []  # src of every <img> without an alt attribute
        self._in = None

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
        if tag == "img" and "alt" not in attrs:
            self.no_alt.append(attrs.get("src") or "")
        if attrs.get("src") is not None:
            self.refs.append((attrs["src"], True))

    def handle_endtag(self, tag):
        if tag == self._in:
            self._in = None

    def handle_data(self, data):
        self.text.append(data)
        if self._in:
            setattr(self, self._in, getattr(self, self._in) + data)


CSS_REFS = re.compile(r"""url\(\s*['"]?([^'")\s]+)['"]?\s*\)|@import\s+['"]([^'"]+)['"]""")


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
            if loaded:
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
    out += check_refs(root, file, page.refs)
    if file == PRIVACY and PRIVACY_STATEMENT not in " ".join(" ".join(page.text).split()).lower():
        out.append(f'{file}: doesn\'t say "{PRIVACY_STATEMENT}"')
    return out


def problems(root):
    files = sorted(os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/")
                   for d, _, names in os.walk(root) for f in names)
    out = [f"{page}: missing" for page in PAGES if page not in files]
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
            out += check_refs(root, file, [(a or b, True) for a, b in CSS_REFS.findall(css)])
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
