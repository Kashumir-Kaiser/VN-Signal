#!/usr/bin/env python3
"""Capture GDW's 2019 HNX disclosure index and any annual-report attachment."""

from __future__ import annotations

import hashlib
import html
import json
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "gdw_hnx_2019_annual_report_capture_20261101"
INDEX_URL = "https://www.hnx.vn/ModuleIssuer/List/ThongTinCongBo"
DETAIL_URL = "https://www.hnx.vn/ModuleArticles/ArticlesCPEtfs/PopupTinCongBoDetail"
PROFILE_URL = "https://www.hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-ny-gdw.html"
USER_AGENT = "VN-Signal-evidence-capture/1.0"
MAX_HTML = 10_485_760
MAX_PDF = 31_457_280


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(url: str, *, body: bytes | None, referer: str, max_bytes: int) -> tuple[bytes, dict[str, object]]:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/json,text/html,application/pdf,*/*",
        "Referer": referer,
    }
    if body is not None:
        headers.update({
            "Content-Type": "application/x-www-form-urlencoded",
            "X-Requested-With": "XMLHttpRequest",
        })
    request = urllib.request.Request(
        url,
        data=body,
        method="POST" if body is not None else "GET",
        headers=headers,
    )
    started = now_utc()
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(max_bytes + 1)
        record = {
            "url": url,
            "final_url": response.geturl(),
            "http_status": response.status,
            "content_type": response.headers.get_content_type(),
            "started_at_utc": started,
            "completed_at_utc": now_utc(),
            "bytes": len(data),
            "sha256": digest(data),
        }
    if record["http_status"] != 200 or not data or len(data) > max_bytes:
        raise RuntimeError(f"invalid, empty, or oversized response: {url}")
    return data, record


def save(name: str, data: bytes) -> None:
    target = OUT / name
    if target.exists() and digest(target.read_bytes()) != digest(data):
        raise RuntimeError(f"refusing to overwrite different captured bytes: {name}")
    if not target.exists():
        target.write_bytes(data)


def summarize_rows(page: str) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for row in re.findall(r"(?is)<tr\b[^>]*>(.*?)</tr>", page):
        id_match = re.search(r"XemChiTietDetailArticlesByID\((\d+),\s*\d+\)", row)
        if not id_match:
            continue
        cells = re.findall(r"(?is)<td\b[^>]*>(.*?)</td>", row)
        texts = [" ".join(html.unescape(re.sub(r"<[^>]*>", " ", cell)).split()) for cell in cells]
        out.append({
            "article_id": id_match.group(1),
            "published_display": texts[1] if len(texts) > 1 else "",
            "title": texts[2] if len(texts) > 2 else "",
        })
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    index_name = "GDW_NY_18-03-2019_05-04-2019_p1.html"
    index_path = OUT / index_name
    manifest_path = OUT / "capture_manifest.json"
    params = {
        "pToDate": "05/04/2019",
        "pNumPage": "1",
        "pStockCode": "GDW",
        "pTieuDeTin": "",
        "pAction": "1",
        "pFromDate": "18/03/2019",
        "pMarketCode": "NY",
        "pOrderBy": "",
        "pNhomTin": "",
        "pNumRecord": "50",
    }
    if index_path.exists() and manifest_path.exists():
        prior = json.loads(manifest_path.read_text(encoding="utf-8"))
        index_bytes = index_path.read_bytes()
        index_meta = prior["index_capture"]
        if digest(index_bytes) != index_meta["sha256"] or len(index_bytes) != index_meta["bytes"]:
            raise RuntimeError("existing HNX index capture fails its stored hash/length check")
    else:
        index_bytes, index_meta = fetch(
            INDEX_URL,
            body=urllib.parse.urlencode(params).encode(),
            referer=PROFILE_URL,
            max_bytes=MAX_HTML,
        )
        save(index_name, index_bytes)
    index_html = index_bytes.decode("utf-8", errors="replace")
    articles = summarize_rows(index_html)
    manifest: dict[str, object] = {
        "schema_version": 1,
        "scope": "Read-only HNX listed-market disclosure search for GDW's 2018 annual report and prior-venue endpoint clues.",
        "capture_method": "HTTPS POST with normal certificate validation; no vnstock route or database write.",
        "symbol": "GDW",
        "market_code": "NY",
        "query_parameters": params,
        "index_capture": {"file": "GDW_NY_18-03-2019_05-04-2019_p1.html", **index_meta},
        "articles": articles,
        "attachments": [],
        "limitations": [],
    }
    candidates = [
        a for a in articles
        if "báo cáo thường niên" in a["title"].lower() and a["title"].strip().endswith("2018")
    ]
    if len(candidates) == 1:
        article = candidates[0]
        detail_bytes, detail_meta = fetch(
            DETAIL_URL,
            body=urllib.parse.urlencode({"pArticlesID": article["article_id"], "pFileAttach": "1"}).encode(),
            referer=PROFILE_URL,
            max_bytes=MAX_HTML,
        )
        detail_name = f"GDW_article_{article['article_id']}_detail.html"
        save(detail_name, detail_bytes)
        detail_html = detail_bytes.decode("utf-8", errors="replace")
        links = []
        for href, label_html in re.findall(r'(?is)<a[^>]+href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', detail_html):
            href = html.unescape(href).replace("&amp;", "&").strip()
            label = " ".join(html.unescape(re.sub(r"<[^>]*>", " ", label_html)).split())
            parsed = urllib.parse.urlparse(href)
            if parsed.scheme == "https" and parsed.hostname == "owa.hnx.vn" and parsed.path.lower().endswith(".pdf"):
                links.append((href, label))
        manifest["article_detail"] = {"article": article, "file": detail_name, **detail_meta}
        for idx, (url, label) in enumerate(links, start=1):
            pdf_bytes, pdf_meta = fetch(url, body=None, referer=PROFILE_URL, max_bytes=MAX_PDF)
            if not pdf_bytes.startswith(b"%PDF-"):
                raise RuntimeError("HNX annual-report attachment did not return PDF bytes")
            filename = f"GDW_annual_report_2018_attachment_{idx:02d}.pdf"
            save(filename, pdf_bytes)
            manifest["attachments"].append({"file": filename, "url": url, "label": label, **pdf_meta})
        if not links:
            manifest["limitations"].append("The official HNX annual-report detail has no PDF attachment hosted on owa.hnx.vn.")
    else:
        manifest["limitations"].append(
            f"Expected one HNX annual-report-2018 article in the date range; found {len(candidates)}."
        )

    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    manifest_path.write_bytes(manifest_bytes)
    print(json.dumps({
        "articles": articles,
        "attachment_count": len(manifest["attachments"]),
        "manifest_sha256": digest(manifest_bytes),
    }, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
