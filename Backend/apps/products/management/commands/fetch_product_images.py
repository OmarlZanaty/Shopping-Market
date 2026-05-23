"""
Management command: fetch_product_images
========================================
Auto-fetches product images from free sources and stores the URL directly
in `image_url_s3` (no file download / S3 upload needed).

Sources (tried in priority order for each product):
  1. Open Food Facts  – barcode lookup, completely free, no API key needed
  2. Pixabay          – name_en keyword search, free 5 000 req/hour (needs PIXABAY_API_KEY)
  3. Pexels           – name_en keyword search, free 200 req/hour   (needs PEXELS_API_KEY)

Get free API keys:
  Pixabay → https://pixabay.com/api/   (register, key shown on API page)
  Pexels  → https://www.pexels.com/api/

Add to .env:
  PIXABAY_API_KEY=your_key_here
  PEXELS_API_KEY=your_key_here

Usage
-----
# Real run – all products missing an image, 10 parallel workers:
    python manage.py fetch_product_images

# Use only Open Food Facts (no API key required):
    python manage.py fetch_product_images --source openfoodfacts

# Use only Pixabay:
    python manage.py fetch_product_images --source pixabay

# Dry-run (print what would happen, touch nothing):
    python manage.py fetch_product_images --dry-run

# Limit to first 500 products (test batch):
    python manage.py fetch_product_images --limit 500

# Overwrite products that already have an image:
    python manage.py fetch_product_images --overwrite

# Tune concurrency (default 10):
    python manage.py fetch_product_images --workers 20
"""

from __future__ import annotations

import os
import time
import random
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional

import requests
from django.core.management.base import BaseCommand, CommandError

from apps.products.models import Product

logger = logging.getLogger(__name__)

# ── API config ────────────────────────────────────────────────────────────────

OFF_API    = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
OFF_FIELDS = "image_url,image_front_url,image_front_small_url"

PIXABAY_API = "https://pixabay.com/api/"
PIXABAY_KEY = os.getenv("PIXABAY_API_KEY", "")

PEXELS_API = "https://api.pexels.com/v1/search"
PEXELS_KEY = os.getenv("PEXELS_API_KEY", "")

HEADERS = {
    "User-Agent": (
        "ShoppingMarketBot/1.0 "
        "(product-image-fetcher; contact=admin@shopping-market.com)"
    )
}

# Pixabay: 5 000 req/hr → 1 req per 0.72 s across all workers
# Use 0.08 s per worker with 10 workers ≈ 1.25 req/s total → well under limit
POLITENESS_DELAY = 0.08


# ── fetch helpers ─────────────────────────────────────────────────────────────

def _off_fetch(barcode: str, timeout: int = 8) -> Optional[str]:
    """Open Food Facts barcode lookup — exact product photo or None."""
    if not barcode:
        return None
    try:
        r = requests.get(
            OFF_API.format(barcode=barcode),
            params={"fields": OFF_FIELDS},
            headers=HEADERS,
            timeout=timeout,
        )
        if r.status_code != 200:
            return None
        data = r.json()
        if data.get("status") != 1:
            return None
        p = data.get("product", {})
        return (
            p.get("image_front_url")
            or p.get("image_url")
            or p.get("image_front_small_url")
            or None
        )
    except Exception:
        return None


def _pixabay_fetch(query: str, timeout: int = 8) -> Optional[str]:
    """Pixabay keyword search — 5 000 req/hr free tier."""
    if not PIXABAY_KEY or not query:
        return None
    try:
        r = requests.get(
            PIXABAY_API,
            params={
                "key":         PIXABAY_KEY,
                "q":           query,
                "image_type":  "photo",
                "orientation": "vertical",
                "per_page":    3,
                "safesearch":  "true",
            },
            headers=HEADERS,
            timeout=timeout,
        )
        if r.status_code != 200:
            return None
        hits = r.json().get("hits", [])
        if not hits:
            return None
        # webformatURL ≈ 640 px wide — good balance of quality vs size
        return hits[0].get("webformatURL") or hits[0].get("largeImageURL") or None
    except Exception:
        return None


def _pexels_fetch(query: str, timeout: int = 8) -> Optional[str]:
    """Pexels keyword search — 200 req/hr free tier (fallback)."""
    if not PEXELS_KEY or not query:
        return None
    try:
        r = requests.get(
            PEXELS_API,
            params={"query": query, "per_page": 1, "orientation": "square"},
            headers={**HEADERS, "Authorization": PEXELS_KEY},
            timeout=timeout,
        )
        if r.status_code != 200:
            return None
        photos = r.json().get("photos", [])
        if not photos:
            return None
        src = photos[0].get("src", {})
        return src.get("medium") or src.get("original") or None
    except Exception:
        return None


# ── per-product worker ────────────────────────────────────────────────────────

def _process_product(product, source: str, dry_run: bool) -> dict:
    time.sleep(POLITENESS_DELAY + random.uniform(0, 0.05))

    url: Optional[str] = None
    used_source = ""

    try:
        # 1. Open Food Facts (barcode — exact match)
        if source in ("openfoodfacts", "all"):
            url = _off_fetch(product.barcode)
            if url:
                used_source = "openfoodfacts"

        # 2. Pixabay (name search — 5 000 req/hr)
        if not url and source in ("pixabay", "all") and PIXABAY_KEY:
            query = product.name_en or product.name_ar or ""
            url = _pixabay_fetch(query)
            if url:
                used_source = "pixabay"

        # 3. Pexels (name search — 200 req/hr, last resort)
        if not url and source in ("pexels", "all") and PEXELS_KEY:
            query = product.name_en or product.name_ar or ""
            url = _pexels_fetch(query)
            if url:
                used_source = "pexels"

        if not url:
            return {"id": str(product.id), "name": product.name_en or product.name_ar,
                    "status": "not_found", "url": None, "source": None}

        if not dry_run:
            Product.objects.filter(pk=product.pk).update(image_url_s3=url)

        return {"id": str(product.id), "name": product.name_en or product.name_ar,
                "status": "found", "url": url, "source": used_source}

    except Exception as exc:
        return {"id": str(product.id), "name": product.name_en or product.name_ar,
                "status": "error", "url": None, "source": None, "error": str(exc)}


# ── command ───────────────────────────────────────────────────────────────────

class Command(BaseCommand):
    help = "Fetch product images from Open Food Facts, Pixabay, and/or Pexels."

    def add_arguments(self, parser):
        parser.add_argument(
            "--source",
            choices=["openfoodfacts", "pixabay", "pexels", "all"],
            default="all",
            help="Which source(s) to query (default: all).",
        )
        parser.add_argument("--workers",  type=int, default=10,
                            help="Parallel HTTP workers (default: 10).")
        parser.add_argument("--limit",    type=int, default=0,
                            help="Process at most N products (0 = unlimited).")
        parser.add_argument("--overwrite", action="store_true", default=False,
                            help="Also update products that already have an image.")
        parser.add_argument("--dry-run",  action="store_true", default=False,
                            help="Print results without saving anything.")
        parser.add_argument("--store-id", type=int, default=None,
                            help="Restrict to a specific store ID.")

    def handle(self, *args, **options):
        source    = options["source"]
        workers   = options["workers"]
        limit     = options["limit"]
        overwrite = options["overwrite"]
        dry_run   = options["dry_run"]
        store_id  = options["store_id"]

        # ── key warnings ─────────────────────────────────────────────────────
        if source in ("pixabay", "all") and not PIXABAY_KEY:
            self.stdout.write(self.style.WARNING(
                "PIXABAY_API_KEY not set — Pixabay disabled. "
                "Get a free key at https://pixabay.com/api/"
            ))
        if source in ("pexels", "all") and not PEXELS_KEY:
            self.stdout.write(self.style.WARNING(
                "PEXELS_API_KEY not set — Pexels disabled."
            ))
        if source in ("pixabay", "all") and not PIXABAY_KEY \
                and source in ("pexels", "all") and not PEXELS_KEY \
                and source != "openfoodfacts":
            self.stdout.write(self.style.WARNING(
                "No name-search API key found. "
                "Only Open Food Facts (barcode) will be used."
            ))

        # ── build queryset ────────────────────────────────────────────────────
        qs = Product.objects.all()
        if store_id:
            qs = qs.filter(store_id=store_id)
        if not overwrite:
            qs = qs.filter(image_url_s3="", main_image="")
        if limit:
            qs = qs[:limit]

        products = list(qs.values_list("id", "barcode", "name_en", "name_ar"))
        total = len(products)

        if total == 0:
            self.stdout.write(self.style.SUCCESS(
                "No products to process — all already have images. "
                "Use --overwrite to re-fetch."
            ))
            return

        class _P:
            __slots__ = ("id", "barcode", "name_en", "name_ar", "pk")
            def __init__(self, row):
                self.id = self.pk = row[0]
                self.barcode = row[1]
                self.name_en = row[2]
                self.name_ar = row[3]

        p_list = [_P(r) for r in products]

        mode = "[DRY RUN] " if dry_run else ""
        self.stdout.write(
            f"\n{mode}Fetching images for {total:,} products "
            f"| source={source} | workers={workers}\n" + ("─" * 60)
        )

        # ── run concurrently ──────────────────────────────────────────────────
        found = not_found = errors = done = 0
        t_start = time.time()

        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                pool.submit(_process_product, p, source, dry_run): p
                for p in p_list
            }
            for future in as_completed(futures):
                done += 1
                result = future.result()

                if result["status"] == "found":
                    found += 1
                elif result["status"] == "not_found":
                    not_found += 1
                else:
                    errors += 1

                if done % 100 == 0 or done == total:
                    elapsed = time.time() - t_start
                    rate = done / elapsed if elapsed > 0 else 0
                    eta  = (total - done) / rate if rate > 0 else 0
                    self.stdout.write(
                        f"  {done:>{len(str(total))}}/{total}  "
                        f"✓{found}  –{not_found}  ✗{errors}  "
                        f"{rate:.1f}/s  ETA {eta:.0f}s"
                    )

        # ── summary ───────────────────────────────────────────────────────────
        elapsed = time.time() - t_start
        self.stdout.write("\n" + ("─" * 60))
        self.stdout.write(self.style.SUCCESS(
            f"\nDone in {elapsed:.1f}s\n"
            f"  Found     : {found:,}\n"
            f"  Not found : {not_found:,}\n"
            f"  Errors    : {errors:,}\n"
            + ("  (DRY RUN — nothing saved)\n" if dry_run else "")
        ))
        if not_found > 0:
            self.stdout.write(self.style.WARNING(
                f"\n{not_found:,} products had no image found. "
                "Consider adding product images manually for these."
            ))
