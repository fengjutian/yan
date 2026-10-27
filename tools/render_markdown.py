"""把 docs 下的 Markdown 协议渲染成可直接托管的静态 HTML。

只支持协议文档实际用到的语法：标题、段落、无序/有序列表、引用、表格、
行内加粗与行内代码。不引入第三方依赖，方便在任意机器上重跑：

    python tools/render_markdown.py
"""

from __future__ import annotations

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "publish"

SOURCES = {
    "privacy.html": ("privacy-policy.md", "颜 Studio 隐私政策"),
    "terms.html": ("user-agreement.md", "颜 Studio 用户协议"),
}

TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>{title}</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{
    margin: 0 auto; padding: 32px 20px 64px; max-width: 760px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
      "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    font-size: 16px; line-height: 1.75; color: #1f2328; background: #fff;
  }}
  h1 {{ font-size: 26px; margin: 0 0 8px; }}
  h2 {{ font-size: 20px; margin: 32px 0 12px; padding-top: 8px; border-top: 1px solid #eee; }}
  h3 {{ font-size: 17px; margin: 24px 0 8px; }}
  p {{ margin: 12px 0; }}
  ul, ol {{ margin: 12px 0; padding-left: 22px; }}
  li {{ margin: 6px 0; }}
  blockquote {{
    margin: 16px 0; padding: 12px 16px; border-left: 4px solid #c9b79c;
    background: #faf7f1; color: #444;
  }}
  table {{ border-collapse: collapse; width: 100%; margin: 16px 0; font-size: 15px; }}
  th, td {{ border: 1px solid #e3e3e3; padding: 8px 10px; text-align: left; vertical-align: top; }}
  th {{ background: #f6f3ee; }}
  code {{ background: #f3f3f3; padding: 1px 5px; border-radius: 4px; font-size: 14px; }}
  a {{ color: #7b5152; }}
  footer {{ margin-top: 48px; font-size: 13px; color: #888; }}
  @media (prefers-color-scheme: dark) {{
    body {{ background: #17181a; color: #e6e6e6; }}
    h2 {{ border-top-color: #2c2d30; }}
    blockquote {{ background: #222326; border-left-color: #7b5152; }}
    th {{ background: #232427; }}
    th, td {{ border-color: #333; }}
    code {{ background: #26272a; }}
  }}
</style>
</head>
<body>
{body}
<footer>本页面由项目内 Markdown 生成，内容与 App 内说明一致。</footer>
</body>
</html>
"""


def inline(text: str) -> str:
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"`(.+?)`", r"<code>\1</code>", escaped)
    return escaped


def render(markdown: str) -> str:
    lines = markdown.splitlines()
    out: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()

        if not stripped:
            index += 1
            continue

        heading = re.match(r"^(#{1,3})\s+(.*)$", stripped)
        if heading:
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            index += 1
            continue

        if re.match(r"^(-{3,}|\*{3,}|_{3,})$", stripped):
            out.append("<hr />")
            index += 1
            continue

        # 表格：当前行以 | 开头，下一行是分隔行
        if stripped.startswith("|") and index + 1 < len(lines) and re.match(
            r"^\|[\s:\-|]+\|$", lines[index + 1].strip()
        ):
            header_cells = [c.strip() for c in stripped.strip("|").split("|")]
            index += 2
            rows: list[list[str]] = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                rows.append(
                    [c.strip() for c in lines[index].strip().strip("|").split("|")]
                )
                index += 1
            out.append("<table><thead><tr>")
            out.extend(f"<th>{inline(c)}</th>" for c in header_cells)
            out.append("</tr></thead><tbody>")
            for row in rows:
                out.append("<tr>")
                out.extend(f"<td>{inline(c)}</td>" for c in row)
                out.append("</tr>")
            out.append("</tbody></table>")
            continue

        if stripped.startswith(">"):
            quote: list[str] = []
            while index < len(lines) and lines[index].strip().startswith(">"):
                quote.append(lines[index].strip().lstrip(">").strip())
                index += 1
            out.append(f"<blockquote>{inline(' '.join(quote))}</blockquote>")
            continue

        if re.match(r"^[-*]\s+", stripped):
            items: list[str] = []
            while index < len(lines) and re.match(r"^[-*]\s+", lines[index].strip()):
                items.append(re.sub(r"^[-*]\s+", "", lines[index].strip()))
                index += 1
            out.append("<ul>")
            out.extend(f"<li>{inline(i)}</li>" for i in items)
            out.append("</ul>")
            continue

        if re.match(r"^\d+\.\s+", stripped):
            items = []
            while index < len(lines) and re.match(r"^\d+\.\s+", lines[index].strip()):
                items.append(re.sub(r"^\d+\.\s+", "", lines[index].strip()))
                index += 1
            out.append("<ol>")
            out.extend(f"<li>{inline(i)}</li>" for i in items)
            out.append("</ol>")
            continue

        # 普通段落：连续非空行合并
        paragraph: list[str] = []
        while index < len(lines) and lines[index].strip():
            current = lines[index].strip()
            if (
                re.match(r"^(#{1,3})\s", current)
                or current.startswith("|")
                or current.startswith(">")
                or re.match(r"^[-*]\s+", current)
                or re.match(r"^\d+\.\s+", current)
                or re.match(r"^(-{3,}|\*{3,}|_{3,})$", current)
            ):
                break
            paragraph.append(current)
            index += 1
        out.append(f"<p>{inline(' '.join(paragraph))}</p>")

    return "\n".join(out)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for output_name, (source_name, title) in SOURCES.items():
        source = ROOT / "docs" / source_name
        body = render(source.read_text(encoding="utf-8"))
        target = OUT_DIR / output_name
        target.write_text(
            TEMPLATE.format(title=html.escape(title), body=body), encoding="utf-8"
        )
        print(f"generated {target.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
