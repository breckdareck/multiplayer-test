#!/usr/bin/env python3
"""Render a GDD Markdown file into a styled standalone HTML preview.

Usage:
    python render_html.py <input.md> <output.html>

Self-contained: CSS is inlined, scripts are loaded from CDN. The output HTML
file can be opened directly in a browser with no other files.
"""
from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

try:
    import markdown
except ImportError:
    sys.stderr.write(
        "Missing dependency: `markdown`.\n"
        "Install with: pip install markdown pygments\n"
    )
    sys.exit(2)


SCRIPT_DIR = Path(__file__).resolve().parent
STYLES_PATH = SCRIPT_DIR.parent / "assets" / "styles.css"


def _read_css() -> str:
    if not STYLES_PATH.exists():
        sys.stderr.write(f"Stylesheet not found at {STYLES_PATH}\n")
        sys.exit(2)
    return STYLES_PATH.read_text(encoding="utf-8")


_MERMAID_BLOCK = re.compile(r"```mermaid\n(.*?)```", re.DOTALL)


def _extract_mermaid(md_text: str) -> tuple[str, list[str]]:
    """Pull mermaid fenced blocks out before markdown parsing.

    Returns the modified markdown (with placeholders) and the list of
    diagram bodies, indexed so they can be reinserted as <div class="mermaid">
    after the markdown -> HTML pass.
    """
    diagrams: list[str] = []

    def _capture(match: re.Match[str]) -> str:
        diagrams.append(match.group(1).strip())
        idx = len(diagrams) - 1
        return f"\n\n<!--MERMAID-{idx}-->\n\n"

    return _MERMAID_BLOCK.sub(_capture, md_text), diagrams


def _restore_mermaid(html_text: str, diagrams: list[str]) -> str:
    for idx, body in enumerate(diagrams):
        placeholder = f"<!--MERMAID-{idx}-->"
        replacement = f'<div class="mermaid">\n{html.escape(body)}\n</div>'
        html_text = html_text.replace(placeholder, replacement)
        # markdown wraps adjacent text in <p>; the placeholder may have ended
        # up inside a <p>. Handle that case too.
        html_text = html_text.replace(f"<p>{placeholder}</p>", replacement)
    return html_text


_HEADING_RE = re.compile(r"<h([23])[^>]*?>(.*?)</h\1>", re.DOTALL)
_ID_RE = re.compile(r'id="([^"]+)"')


def _slugify(text: str) -> str:
    text = re.sub(r"<[^>]+>", "", text)  # strip any inline tags
    text = html.unescape(text)  # decode &amp; etc. before slugging
    text = text.strip().lower()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_-]+", "-", text)
    return text.strip("-")


def _inject_heading_ids_and_build_toc(html_text: str) -> tuple[str, str]:
    """Ensure every h2/h3 has an id, build a nested TOC HTML."""
    toc_entries: list[tuple[int, str, str]] = []  # (level, id, text)

    def _process(match: re.Match[str]) -> str:
        level = int(match.group(1))
        inner = match.group(2)
        existing = _ID_RE.search(match.group(0))
        if existing:
            heading_id = existing.group(1)
            tag = match.group(0)
        else:
            heading_id = _slugify(inner) or f"section-{len(toc_entries)}"
            tag = f'<h{level} id="{heading_id}">{inner}</h{level}>'
        toc_entries.append((level, heading_id, re.sub(r"<[^>]+>", "", inner)))
        return tag

    new_html = _HEADING_RE.sub(_process, html_text)

    # Build nested TOC. Each H2 opens an <li>; H3 children go in a nested
    # <ul>. We track whether the current H2's <li> is still open and whether
    # a nested <ul> is open inside it, so we can close them in the right
    # order when the next sibling appears or the list ends.
    toc_lines = ['<nav class="gdd-toc"><h2>Contents</h2><ul>']
    h2_open = False
    sub_open = False
    for level, hid, text in toc_entries:
        clean = html.escape(html.unescape(text))
        if level == 2:
            if sub_open:
                toc_lines.append("</ul>")
                sub_open = False
            if h2_open:
                toc_lines.append("</li>")
            toc_lines.append(f'<li><a href="#{hid}">{clean}</a>')
            h2_open = True
        elif level == 3:
            if not h2_open:
                # Stray H3 with no preceding H2 — open a wrapper <li>.
                toc_lines.append("<li>")
                h2_open = True
            if not sub_open:
                toc_lines.append("<ul>")
                sub_open = True
            toc_lines.append(f'<li><a href="#{hid}">{clean}</a></li>')
    if sub_open:
        toc_lines.append("</ul>")
    if h2_open:
        toc_lines.append("</li>")
    toc_lines.append("</ul></nav>")
    return new_html, "".join(toc_lines)


_CALLOUT_QUESTION = re.compile(
    r"<blockquote>\s*<p>(?:⚠|&#9888;)\s*(.*?)</p>\s*</blockquote>",
    re.DOTALL,
)


def _classify_callouts(html_text: str) -> str:
    """Tag blockquotes that start with ⚠ as question callouts."""
    return _CALLOUT_QUESTION.sub(
        r'<blockquote class="callout-question"><p>⚠ \1</p></blockquote>',
        html_text,
    )


_TITLE_RE = re.compile(r"<h1[^>]*>(.*?)</h1>", re.DOTALL)


def _extract_title(html_text: str) -> str:
    match = _TITLE_RE.search(html_text)
    if not match:
        return "Game Design Document"
    return re.sub(r"<[^>]+>", "", match.group(1)).strip() or "Game Design Document"


def render(md_path: Path, html_path: Path) -> None:
    md_text = md_path.read_text(encoding="utf-8")
    md_text, diagrams = _extract_mermaid(md_text)

    converter = markdown.Markdown(
        extensions=[
            "extra",
            "tables",
            "fenced_code",
            "codehilite",
            "sane_lists",
            "attr_list",
        ],
        extension_configs={
            "codehilite": {
                "guess_lang": False,
                "noclasses": False,
                "css_class": "highlight",
            },
        },
    )
    body_html = converter.convert(md_text)
    body_html = _restore_mermaid(body_html, diagrams)
    body_html, toc_html = _inject_heading_ids_and_build_toc(body_html)
    body_html = _classify_callouts(body_html)

    title = _extract_title(body_html)
    css = _read_css()

    # Pygments default CSS for code highlighting — appended after our CSS so
    # our background/foreground choices win, but token colors come through.
    try:
        from pygments.formatters import HtmlFormatter

        pygments_css = HtmlFormatter(style="friendly").get_style_defs(".highlight")
    except Exception:
        pygments_css = ""

    out = _PAGE_TEMPLATE.format(
        title=html.escape(title),
        css=css,
        pygments_css=pygments_css,
        toc=toc_html,
        body=body_html,
    )
    html_path.write_text(out, encoding="utf-8")
    print(f"Rendered {md_path} -> {html_path}")


_PAGE_TEMPLATE = """<!doctype html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
{css}
{pygments_css}
</style>
</head>
<body>
<header class="gdd-header">
  <span class="brand">Game Design Document</span>
  <button class="theme-toggle" id="themeToggle" type="button">Theme: light</button>
</header>
{toc}
<main class="gdd-main">
  <article class="gdd-content">
    {body}
  </article>
</main>

<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script>
  (function () {{
    const root = document.documentElement;
    const button = document.getElementById('themeToggle');
    const saved = localStorage.getItem('gdd-theme');
    const initial = saved || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    setTheme(initial);
    button.addEventListener('click', () => {{
      const next = root.dataset.theme === 'dark' ? 'light' : 'dark';
      setTheme(next);
    }});
    function setTheme(t) {{
      root.dataset.theme = t;
      localStorage.setItem('gdd-theme', t);
      button.textContent = 'Theme: ' + t;
      if (window.mermaid) {{
        mermaid.initialize({{
          startOnLoad: false,
          theme: t === 'dark' ? 'dark' : 'default',
          securityLevel: 'loose',
        }});
        // Re-render mermaid diagrams on theme change
        document.querySelectorAll('.mermaid').forEach((el) => {{
          if (el.dataset.original) {{
            el.innerHTML = el.dataset.original;
          }} else {{
            el.dataset.original = el.innerHTML;
          }}
          el.removeAttribute('data-processed');
        }});
        mermaid.run();
      }}
    }}
  }})();

  // TOC scrollspy
  (function () {{
    const links = Array.from(document.querySelectorAll('.gdd-toc a'));
    const targets = links
      .map(a => document.getElementById(a.getAttribute('href').slice(1)))
      .filter(Boolean);
    const observer = new IntersectionObserver((entries) => {{
      entries.forEach((entry) => {{
        if (entry.isIntersecting) {{
          links.forEach(l => l.classList.remove('active'));
          const active = links.find(l => l.getAttribute('href') === '#' + entry.target.id);
          if (active) active.classList.add('active');
        }}
      }});
    }}, {{ rootMargin: '-100px 0px -70% 0px' }});
    targets.forEach(t => observer.observe(t));
  }})();
</script>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("input", type=Path, help="Path to the GDD Markdown file.")
    parser.add_argument("output", type=Path, help="Path to write the HTML preview.")
    args = parser.parse_args()

    if not args.input.exists():
        sys.stderr.write(f"Input file not found: {args.input}\n")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    render(args.input, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
