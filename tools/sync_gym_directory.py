#!/usr/bin/env python3
"""Sync public climbing-gym discovery data into reviewable local JSON files.

This tool deliberately has two outputs:

* ``data/gyms.public-verified.json`` contains entries that have a city and
  street address, so they can be seeded into the application database.
* ``data/gym-directory.candidates.json`` contains sitemap discoveries with
  incomplete addresses.  They are *not* seeded and must be reviewed first.

Only public endpoints are used.  The crawler honours the source's public
``robots.txt`` policy, uses a small bounded request set, and never bypasses
authentication, CAPTCHAs, or a map provider's private API.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DIRECTORY_FILE = ROOT / "data" / "gyms.public-verified.json"
CANDIDATES_FILE = ROOT / "data" / "gym-directory.candidates.json"
USER_AGENT = "WanpanDiaryGymDirectoryBot/1.0 (+https://github.com/guoba/wanpan-diary)"
BANANA_ENDPOINT = "https://climbing-mcp.mx5.cn/api/climbing/mcp"
DUSTS_ROBOTS = "https://climbing.dusts.me/robots.txt"
DUSTS_SITEMAP = "https://climbing.dusts.me/sitemap.xml"
DUSTS_GYMS_API = "https://climbing.dusts.me/api/gyms"

PROVINCES = {
    "北京": "北京市", "上海": "上海市", "重庆": "重庆市", "天津": "天津市",
    "广州": "广东省", "深圳": "广东省", "佛山": "广东省", "东莞": "广东省", "珠海": "广东省",
    "杭州": "浙江省", "成都": "四川省", "武汉": "湖北省", "长沙": "湖南省",
    "南京": "江苏省", "苏州": "江苏省", "西安": "陕西省", "昆明": "云南省",
    "青岛": "山东省", "大连": "辽宁省", "厦门": "福建省", "合肥": "安徽省",
    "郑州": "河南省", "石家庄": "河北省", "沈阳": "辽宁省", "长春": "吉林省",
    "太原": "山西省", "保定": "河北省", "常州": "江苏省", "宁波": "浙江省",
}


def request_bytes(url: str, *, method: str = "GET", body: bytes | None = None) -> bytes:
    request = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json, text/xml, */*"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.read()


def request_json_rpc(endpoint: str, tool: str, arguments: dict[str, Any]) -> dict[str, Any]:
    payload = json.dumps({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": tool, "arguments": arguments},
    }).encode("utf-8")
    raw = request_bytes(endpoint, method="POST", body=payload)
    response = json.loads(raw)
    content = response.get("result", {}).get("content", [])
    if not content or not isinstance(content[0], dict) or not isinstance(content[0].get("text"), str):
        raise RuntimeError("香蕉攀岩公开服务返回了无法识别的内容")
    return json.loads(content[0]["text"])


def clean_text(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()


def banana_gyms() -> list[dict[str, Any]]:
    response = request_json_rpc(BANANA_ENDPOINT, "listStores", {"limit": 100})
    stores = response.get("stores")
    if not isinstance(stores, list):
        raise RuntimeError("香蕉攀岩公开服务缺少 stores 列表")

    gyms: list[dict[str, Any]] = []
    for store in stores:
        if not isinstance(store, dict):
            continue
        name = clean_text(store.get("name"))
        city = clean_text(store.get("city_name"))
        address = clean_text(store.get("address"))
        if not name or not city or not address:
            continue
        latitude, longitude = store.get("lat"), store.get("lng")
        gym: dict[str, Any] = {
            "name": name,
            "province": PROVINCES.get(city, "待核验"),
            "city": city,
            "district": "待核验",
            "address": address,
            "description": "香蕉攀岩公开门店服务同步；等待场馆认领核验。",
            "source": {
                "name": "香蕉攀岩公开门店服务（climbing-go）",
                "url": "https://github.com/betly-ai/climbing-go",
                "external_id": clean_text(store.get("id")),
                "opening_date": clean_text(store.get("opening_date")),
                "fetched_at": datetime.now(timezone.utc).isoformat(),
            },
        }
        if isinstance(latitude, (int, float)) and isinstance(longitude, (int, float)):
            gym["latitude"] = latitude
            gym["longitude"] = longitude
        gyms.append(gym)
    return gyms


def slug_to_name(url: str) -> str:
    slug = urllib.parse.unquote(urllib.parse.urlparse(url).path.rsplit("/", 1)[-1])
    slug = re.sub(r"^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}-", "", slug, flags=re.I)
    return clean_text(slug.replace("-", " "))


def dusts_candidates(limit: int) -> list[dict[str, str]]:
    robots = request_bytes(DUSTS_ROBOTS).decode("utf-8", errors="replace")
    if re.search(r"(?im)^\s*disallow:\s*/\s*$", robots):
        raise RuntimeError("攀岩么 robots.txt 当前不允许抓取，已停止")

    xml = request_bytes(DUSTS_SITEMAP)
    root = ET.fromstring(xml)
    namespace = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    candidates: list[dict[str, str]] = []
    for item in root.findall("sm:url", namespace):
        location = item.findtext("sm:loc", default="", namespaces=namespace)
        if "/gyms/" not in location:
            continue
        candidates.append({
            "name": slug_to_name(location),
            "source": {"name": "攀岩么公开 sitemap", "url": location},
            "last_modified": item.findtext("sm:lastmod", default="", namespaces=namespace),
            "status": "needs_address_review",
            "note": "公开 sitemap 发现；需补充城市和详细地址后才可导入数据库。",
        })
        if len(candidates) >= limit:
            break
    return candidates


def number_or_none(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if -180 <= number <= 180 else None


def dusts_gyms() -> list[dict[str, Any]]:
    """Fetch complete public records exposed by the site's own browse API."""
    robots = request_bytes(DUSTS_ROBOTS).decode("utf-8", errors="replace")
    if re.search(r"(?im)^\s*disallow:\s*/\s*$", robots):
        raise RuntimeError("攀岩么 robots.txt 当前不允许抓取，已停止")
    records = json.loads(request_bytes(DUSTS_GYMS_API))
    if not isinstance(records, list):
        raise RuntimeError("攀岩么公开岩馆接口没有返回列表")

    fetched_at = datetime.now(timezone.utc).isoformat()
    gyms: list[dict[str, Any]] = []
    for record in records:
        if not isinstance(record, dict):
            continue
        name = clean_text(record.get("name"))
        city = clean_text(record.get("city"))
        address = clean_text(record.get("address"))
        if not name or not city or not address:
            continue
        gym: dict[str, Any] = {
            "name": name,
            "province": PROVINCES.get(city, "待核验"),
            "city": city,
            "district": "待核验",
            "address": address,
            "description": clean_text(record.get("description")) or "公开攀岩目录同步；等待场馆认领核验。",
            "source": {
                "name": "攀岩么公开岩馆接口",
                "url": DUSTS_GYMS_API,
                "external_id": clean_text(record.get("id")),
                "updated_at": clean_text(record.get("updated_at")),
                "route_reset_cycle_days": record.get("route_reset_cycle_days"),
                "fetched_at": fetched_at,
            },
        }
        latitude, longitude = number_or_none(record.get("latitude")), number_or_none(record.get("longitude"))
        if latitude is not None and longitude is not None and -90 <= latitude <= 90:
            gym["latitude"] = latitude
            gym["longitude"] = longitude
        gyms.append(gym)
    return gyms


def normalized_key(gym: dict[str, Any]) -> tuple[str, str, str]:
    def normalize(value: Any) -> str:
        return "".join(
            char for char in unicodedata.normalize("NFKC", clean_text(value)).lower()
            if char.isalnum() or "\u4e00" <= char <= "\u9fff"
        )
    return normalize(gym.get("name")), normalize(gym.get("city")), normalize(gym.get("address"))


def source_identity(gym: dict[str, Any]) -> tuple[str, str] | None:
    source = gym.get("source")
    if not isinstance(source, dict):
        return None
    source_name = clean_text(source.get("name"))
    external_id = clean_text(source.get("external_id"))
    if not source_name or not external_id:
        return None
    return source_name, external_id


def merge_records(
    existing: list[dict[str, Any]],
    new_gyms: list[dict[str, Any]],
) -> tuple[int, int]:
    """Merge a refresh without duplicating records whose address was edited.

    Stable source identities update in place. Explicit review decisions stay on
    the record even when a public source refreshes its name, address or point.
    """
    by_source = {
        identity: index
        for index, item in enumerate(existing)
        if (identity := source_identity(item)) is not None
    }
    by_exact = {normalized_key(item): index for index, item in enumerate(existing)}
    added = 0
    updated = 0
    for gym in new_gyms:
        identity = source_identity(gym)
        existing_index = by_source.get(identity) if identity is not None else None
        if existing_index is not None:
            previous = existing[existing_index]
            replacement = dict(gym)
            for reviewed_field in ("brandName", "canonicalVenueId"):
                if reviewed_field in previous:
                    replacement[reviewed_field] = previous[reviewed_field]
            previous_key = normalized_key(previous)
            if by_exact.get(previous_key) == existing_index:
                del by_exact[previous_key]
            existing[existing_index] = replacement
            by_exact[normalized_key(replacement)] = existing_index
            updated += 1
            continue

        key = normalized_key(gym)
        if key in by_exact:
            continue
        existing.append(gym)
        new_index = len(existing) - 1
        by_exact[key] = new_index
        if identity is not None:
            by_source[identity] = new_index
        added += 1
    return added, updated


def merge_directory(new_gyms: list[dict[str, Any]], *, write: bool) -> tuple[int, int, int]:
    payload = json.loads(DIRECTORY_FILE.read_text(encoding="utf-8"))
    existing = payload.get("gyms", [])
    if not isinstance(existing, list):
        raise RuntimeError("现有岩馆目录格式错误")
    typed_existing = [item for item in existing if isinstance(item, dict)]
    if len(typed_existing) != len(existing):
        raise RuntimeError("现有岩馆目录包含非对象记录")
    added, updated = merge_records(typed_existing, new_gyms)
    payload["collectedAt"] = datetime.now().date().isoformat()
    payload["notice"] = (
        "公开资料初步核验清单。地址可能变更；这些条目默认 verified=false，"
        "只有场馆认领并由平台复核后才可标为已认证。"
    )
    payload["gyms"] = typed_existing
    if write:
        DIRECTORY_FILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return added, updated, len(typed_existing)


def main() -> int:
    parser = argparse.ArgumentParser(description="同步公开岩馆目录（仅供审核）")
    parser.add_argument("--write", action="store_true", help="写入 data/ 下的 JSON；默认仅预览")
    parser.add_argument("--sitemap-limit", type=int, default=300, help="最多读取多少条 sitemap 候选（默认 300）")
    args = parser.parse_args()
    if args.sitemap_limit < 1 or args.sitemap_limit > 1000:
        parser.error("--sitemap-limit 必须介于 1 和 1000")

    banana = banana_gyms()
    time.sleep(0.5)
    dusts = dusts_gyms()
    added, updated, total = merge_directory(banana + dusts, write=args.write)
    time.sleep(0.5)
    candidates = dusts_candidates(args.sitemap_limit)
    candidate_payload = {
        "schemaVersion": 1,
        "collectedAt": datetime.now(timezone.utc).isoformat(),
        "notice": "仅作公开来源发现与人工审核；不含完整地址的条目绝不导入数据库。",
        "candidates": candidates,
    }
    if args.write:
        CANDIDATES_FILE.write_text(json.dumps(candidate_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(json.dumps({
        "banana_public_records": len(banana),
        "dusts_public_records": len(dusts),
        "added_to_seed_directory": added,
        "updated_by_source_identity": updated,
        "seed_directory_total": total,
        "other_brand_candidates": len(candidates),
        "wrote_files": args.write,
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, ET.ParseError) as error:
        print(f"同步失败：{error}", file=sys.stderr)
        raise SystemExit(1)
