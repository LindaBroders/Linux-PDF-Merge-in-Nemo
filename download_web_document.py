#!/usr/bin/env python3
"""Download a document shown page by page in a web viewer and save it as one PDF.

Two modes:

  capture  Opens a browser window. You browse to the document (log in if needed)
           and scroll/click through every page once. Every page image the viewer
           loads is recorded. Press Enter in the terminal when done, and all pages
           are combined into one PDF. If the viewer loads a real PDF file in the
           background, that file is saved directly instead.

  pattern  For viewers whose page images have numbered URLs
           (e.g. .../page_1.jpg, .../page_2.jpg). Downloads pages until the first
           missing one (or --end) and combines them into one PDF.

Only use this for documents you are allowed to download.
"""

import argparse
import hashlib
import io
import os
import re
import select
import sys
import tempfile
import urllib.error
import urllib.request

try:
    import img2pdf
    from PIL import Image
except ImportError:
    sys.exit("Missing dependencies. Install with:\n"
             "  sudo apt install python3-img2pdf python3-pil")


def natural_key(text):
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", text)]


def unique_path(path):
    """Return path, or path with 2, 3 … appended if it already exists (like Merge2.pdf)."""
    if not os.path.exists(path):
        return path
    base, ext = os.path.splitext(path)
    n = 2
    while os.path.exists(f"{base}{n}{ext}"):
        n += 1
    return f"{base}{n}{ext}"


def image_to_pdf_ready(data):
    """Return image bytes img2pdf accepts losslessly; convert formats it cannot embed."""
    img = Image.open(io.BytesIO(data))
    if img.format == "JPEG" and img.mode in ("RGB", "L", "CMYK"):
        return data
    if img.format == "PNG" and img.mode in ("RGB", "L", "P") and "transparency" not in img.info:
        return data
    # WebP, AVIF, GIF, PNG with alpha …: flatten onto white and store as PNG (lossless)
    img = img.convert("RGBA")
    flat = Image.new("RGB", img.size, "white")
    flat.paste(img, mask=img.getchannel("A"))
    out = io.BytesIO()
    flat.save(out, "PNG")
    return out.getvalue()


def write_pdf(pages, output, keep_dir=None):
    """pages: list of image bytes in page order."""
    if not pages:
        sys.exit("No pages captured – nothing to save.")
    if keep_dir:
        os.makedirs(keep_dir, exist_ok=True)
        width = len(str(len(pages)))
        for i, data in enumerate(pages, 1):
            ext = (Image.open(io.BytesIO(data)).format or "img").lower()
            with open(os.path.join(keep_dir, f"page_{i:0{width}d}.{ext}"), "wb") as f:
                f.write(data)
        print(f"Page images saved in: {keep_dir}")
    output = unique_path(output)
    with open(output, "wb") as f:
        f.write(img2pdf.convert([image_to_pdf_ready(p) for p in pages]))
    print(f"Saved {len(pages)} pages to: {output}")


# --------------------------------------------------------------------------- pattern

def run_pattern(args):
    if "{n" not in args.url:
        sys.exit("The URL must contain {n} where the page number goes, "
                 "e.g. 'https://example.org/doc/page_{n}.jpg' (or {n:03} for 001, 002 …).")
    headers = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Firefox/130.0"}
    for h in args.header or []:
        name, _, value = h.partition(":")
        headers[name.strip()] = value.strip()
    if args.referer:
        headers["Referer"] = args.referer

    pages = []
    n = args.start
    while args.end is None or n <= args.end:
        url = args.url.format(n=n)
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
                data = r.read()
        except urllib.error.HTTPError as e:
            if args.end is None and e.code in (403, 404, 410):
                print(f"Page {n}: HTTP {e.code} – assuming the document ends here.")
                break
            sys.exit(f"Page {n}: HTTP {e.code} for {url}")
        try:
            Image.open(io.BytesIO(data)).verify()
        except Exception:
            if args.end is None:
                print(f"Page {n}: not an image – assuming the document ends here.")
                break
            sys.exit(f"Page {n}: response is not an image ({url})")
        pages.append(data)
        print(f"Page {n}: OK ({len(data) // 1024} KB)")
        n += 1
    write_pdf(pages, args.output, args.keep_images)


# --------------------------------------------------------------------------- capture

def enter_pressed():
    if select.select([sys.stdin], [], [], 0)[0]:
        sys.stdin.readline()
        return True
    return False


def run_capture(args):
    try:
        from playwright.sync_api import sync_playwright, Error as PlaywrightError
    except ImportError:
        sys.exit("Capture mode needs Playwright. Install with:\n"
                 "  pip install --user playwright   (or: pipx install playwright)\n"
                 "  python3 -m playwright install chromium")

    seen = set()
    captured = []   # (order, url, bytes)
    pdfs = []       # (url, bytes)

    def on_response(response):
        try:
            ctype = (response.headers.get("content-type") or "").split(";")[0].strip().lower()
            if ctype == "application/pdf" or response.url.lower().split("?")[0].endswith(".pdf"):
                body = response.body()
                if body[:5] == b"%PDF-":
                    pdfs.append((response.url, body))
                    print(f"  Found the original PDF file ({len(body) // 1024} KB)")
                return
            if not ctype.startswith("image/") or ctype == "image/svg+xml":
                return
            body = response.body()
            if len(body) < args.min_bytes:
                return
            digest = hashlib.sha1(body).hexdigest()
            if digest in seen:
                return
            with Image.open(io.BytesIO(body)) as img:
                w, h = img.size
            if w < args.min_width:
                return
            seen.add(digest)
            captured.append((len(captured), response.url, body))
            print(f"  Page {len(captured)} captured ({w}×{h})")
        except PlaywrightError:
            pass  # response was discarded (redirect, page closed …)
        except Exception as e:
            print(f"  Skipped {response.url[:80]}: {e}")

    profile = os.path.expanduser("~/.cache/web-document-download/profile")
    os.makedirs(profile, exist_ok=True)
    with sync_playwright() as p:
        launch = {"headless": args.headless, "viewport": None}
        if args.browser_path:
            launch["executable_path"] = args.browser_path
        # Persistent profile: a login you do once is remembered next time
        context = p.chromium.launch_persistent_context(profile, **launch)
        context.on("response", on_response)
        page = context.pages[0] if context.pages else context.new_page()
        if args.url:
            page.goto(args.url)
        print("\nScroll or click through ALL pages of the document in the browser window.\n"
              "Tip: zoom in first if the viewer loads sharper images when zoomed.\n"
              "Press Enter here when you have reached the last page.\n")
        while True:
            if args.headless and args.wait is not None:
                page.wait_for_timeout(args.wait * 1000)
                break
            if enter_pressed():
                break
            try:
                context.pages[0].wait_for_timeout(300)  # lets Playwright process responses
            except (PlaywrightError, IndexError):
                print("Browser window closed.")
                break
        try:
            context.close()
        except PlaywrightError:
            pass

    if pdfs:
        url, body = max(pdfs, key=lambda x: len(x[1]))
        output = unique_path(args.output)
        with open(output, "wb") as f:
            f.write(body)
        print(f"Saved the original PDF to: {output}")
        if not args.also_images:
            return

    if args.sort == "url":
        captured.sort(key=lambda c: natural_key(c[1]))
    pages = [c[2] for c in captured]
    if args.also_images or not pdfs:
        out = args.output if not pdfs else os.path.splitext(args.output)[0] + "_images.pdf"
        write_pdf(pages, out, args.keep_images)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="mode", required=True)

    c = sub.add_parser("capture", help="record pages while you browse through the document")
    c.add_argument("url", nargs="?", help="address of the document viewer (optional)")
    c.add_argument("--min-width", type=int, default=600,
                   help="ignore images narrower than this in pixels – filters out icons/thumbnails (default 600)")
    c.add_argument("--min-bytes", type=int, default=15000,
                   help="ignore images smaller than this in bytes (default 15000)")
    c.add_argument("--sort", choices=["load", "url"], default="load",
                   help="page order: order the viewer loaded them (default) or page number in the URL")
    c.add_argument("--also-images", action="store_true",
                   help="build the image PDF even if the original PDF was found")
    c.add_argument("--browser-path", help="path to a Chromium/Chrome executable to use")
    c.add_argument("--headless", action="store_true", help=argparse.SUPPRESS)
    c.add_argument("--wait", type=int, help=argparse.SUPPRESS)

    t = sub.add_parser("pattern", help="download numbered page images directly")
    t.add_argument("url", help="image URL with {n} for the page number, e.g. 'https://…/page_{n}.jpg'")
    t.add_argument("--start", type=int, default=1, help="first page number (default 1)")
    t.add_argument("--end", type=int, help="last page number (default: until a page is missing)")
    t.add_argument("--referer", help="Referer header, needed by some sites (usually the viewer address)")
    t.add_argument("--header", action="append", help="extra header, e.g. 'Cookie: session=…' (repeatable)")

    for s in (c, t):
        s.add_argument("-o", "--output", default="Document.pdf", help="output PDF (default Document.pdf)")
        s.add_argument("--keep-images", metavar="DIR", help="also save the single page images in this folder")

    args = ap.parse_args()
    if args.mode == "capture":
        run_capture(args)
    else:
        run_pattern(args)


if __name__ == "__main__":
    main()
