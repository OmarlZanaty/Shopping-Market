"""
Management command: fetch_product_images
========================================
Auto-fetches product images from two free sources and stores the URL directly
in `image_url_s3` (no file download / S3 upload needed).

Sources (tried in order for each product):
  1. Open Food Facts  – barcode lookup, completely free, no API key
  2. Pexels           – name_en keyword search, free (needs PEXELS_API_KEY in .env)

Usage
-----
# Dry-run (print what would happen, touch nothing):
    python manage.py fetch_product_images --dry-run

# Real run – all products missing an image, 10 parallel workers:
    python manage.py fetch_product_images

# Use only Open Food Facts (no Pexels key required):
    python manage.py fetch_product_images --source openfoodfacts

# Limit to first 500 products (useful for a test batch):
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
from django.db import transaction

from apps.products.models import Product

logger = logging.getLogger(__name__)

# ── constants ─────────────────────────────────────────────────────────────────

OFF_API = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
OFF_FIELDS = "image_url,image_front_url,image_front_small_url,product_name"

PEXELS_API = "https://api.pexels.com/v1/search"
PEXELS_KEY = os.getenv("PEXELS_API_KEY", "")

HEADERS = {
    "User-Agent": (
        "ShoppingMarketBot/1.0 "
        "(product-image-fetcher; contact=admin@shopping-market.com)"
    )
}

# seconds to wait between batches to avoid hammering the free APIs
POLITENESS_DELAY = 0.10   # per-request sleep inside worker
PEXELS_RATE_LIMIT = 200   # requests / hour → ≈ 18s per request max; we use delay


# ── helpers ───────────────────────────────────────────────────────────────────

def _off_fetch(barcode: str, timeout: int = 8) -> Optional[str]:
    """Return the best image URL from Open Food Facts for this barcode, or None."""
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
        # prefer full-size front image, fall back to any image_url
        return (
            p.get("image_front_url")
            or p.get("image_url")
            or p.get("image_front_small_url")
            or None
        )
    except Exception:
        return None


def _pexels_fetch(query: str, timeout: int = 8) -> Optional[str]:
    """Return the first Pexels photo URL for `query`, or None."""
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
        # medium ≈ 350 px square – good thumbnail without huge download
        return src.get("medium") or src.get("original") or None
    except Exception:
        return None


def _process_product(
    product: Product,
    source: str,
    dry_run: bool,
) -> dict:
    """
    Attempt to find an image for one product.
    Returns a result dict:
        {id, name, status, url, source}
    where status is one of: 'found', 'not_found', 'skipped', 'error'
    """
    time.sleep(POLITENESS_DELAY + random.uniform(0, 0.05))

    url: Optional[str] = None
    used_source: str = ""

    try:
        # 1. Open Food Facts (barcode-based – exact match)
        if source in ("openfoodfacts", "all"):
            url = _off_fetch(product.barcode)
            if url:
                used_source = "openfoodfacts"

        # 2. Pexels (name-based – semantic match)
        if not url and source in ("pexels", "all") and PEXELS_KEY:
            query = product.name_en or product.name_ar or ""
            url = _pexels_fetch(query)
            if url:
                used_source = "pexels"

        if not url:
            return {
                "id": str(product.id),
                "name": product.name_en or product.name_ar,
                "status": "not_found",
                "url": None,
                "source": None,
            }

        # Save
        if not dry_run:
            Product.objects.filter(pk=product.pk).update(image_url_s3=url)

        return {
            "id": str(product.id),
            "name": product.name_en or product.name_ar,
            "status": "found",
            "url": url,
            "source": used_source,
        }

    except Exception as exc:
        return {
            "id": str(product.id),
            "name": product.name_en or product.name_ar,
            "status": "error",
            "url": None,
            "source": None,
            "error": str(exc),
        }


# ── command ───────────────────────────────────────────────────────────────────

class Command(BaseCommand):
    help = "Fetch product images from Open Food Facts and/or Pexels."

    def add_arguments(self, parser):
        parser.add_argument(
            "--source",
            choices=["openfoodfacts", "pexels", "all"],
            default="all",
            help="Which source(s) to query (default: all).",
        )
        parser.add_argument(
            "--workers",
            type=int,
            default=10,
            help="Number of parallel HTTP workers (default: 10).",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help="Process at most N products (0 = unlimited).",
        )
        parser.add_argument(
            "--overwrite",
            action="store_true",
            default=False,
            help="Also update products that already have an image.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            default=False,
            help="Print results without saving anything.",
        )
        parser.add_argument(
            "--store-id",
            type=int,
            default=None,
            help="Restrict to a specific store ID.",
        )

    def handle(self, *args, **options):
        source    = options["source"]
        workers   = options["workers"]
        limit     = options["limit"]
        overwrite = options["overwrite"]
        dry_run   = options["dry_run"]
        store_id  = options["store_id"]

        # ── sanity checks ────────────────────────────────────────────────────
        if source in ("pexels", "all") and not PEXELS_KEY:
            if source == "pexels":
                raise CommandError(
                    "PEXELS_API_KEY is not set in .env. "
                    "Get a free key at https://www.pexels.com/api/ "
                    "then add PEXELS_API_KEY=<key> to your .env file."
                )
            self.stdout.write(
                self.style.WARNING(
                    "PEXELS_API_KEY not set — Pexels fallback disabled. "
                    "Only Open Food Facts will be used."
                )
            )

        # ── build queryset ───────────────────────────────────────────────────
        qs = Product.objects.all()
        if store_id:
            qs = qs.filter(store_id=store_id)
        if not overwrite:
            qs = qs.filter(image_url_s3="", main_image="")
        if limit:
            qs = qs[:limit]

        products = list(qs.values_list(
            "id", "barcode", "name_en", "name_ar"
        ))

        total = len(products)
        if total == 0:
            self.stdout.write(self.style.SUCCESS(
                "No products to process — all already have images. "
                "Use --overwrite to re-fetch."
            ))
            return

        mode_label = "[DRY RUN] " if dry_run else ""
        self.stdout.write(
            f"\n{mode_label}Fetching images for {total:,} products "
            f"| source={source} | workers={workers}\n"
            + ("─" * 60)
        )

        # Build lightweight product-like objects for the worker
        # (avoid passing ORM objects across threads)
        class _P:
            __slots__ = ("id", "barcode", "name_en", "name_ar", "pk")
            def __init__(self, row):
                self.id = self.pk = row[0]
                self.barcode = row[1]
                self.name_en = row[2]
                self.name_ar = row[3]

        p_list = [_P(r) for r in products]

        # ── run concurrently ─────────────────────────────────────────────────
        found      = 0
        not_found  = 0
        errors     = 0
        done       = 0
        t_start    = time.time()

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
                    marker = self.style.SUCCESS("✓")
                elif result["status"] == "not_found":
                    not_found += 1
                    marker = self.style.WARNING("–")
                else:
                    errors += 1
                    marker = self.style.ERROR("✗")

                # progress line every 50 products or at the end
                if done % 50 == 0 or done == total:
                    elapsed = time.time() - t_start
                    rate = done / elapsed if elapsed > 0 else 0
                    eta  = (total - done) / rate if rate > 0 else 0
                    self.stdout.write(
                        f"  {done:>{len(str(total))}}/{total}  "
                        f"✓{found}  –{not_found}  ✗{errors}  "
                        f"{rate:.1f}/s  ETA {eta:.0f}s"
                    )
                else:
                    # verbose per-product line (only print failures/found so log isn't swamped)
                    name_short = (result["name"] or "")[:40]
                    if result["status"] == "found":
                        self.stdout.write(
                            f"  {marker} [{result['source']:>13}] {name_short}"
                        )
                    elif result["status"] == "error":
                        self.stdout.write(
                            f"  {marker} {name_short}  ERROR: {result.get('error')}"
                        )

        # ── summary ──────────────────────────────────────────────────────────
        elapsed = time.time() - t_start
        self.stdout.write("\n" + ("─" * 60))
        self.stdout.write(self.style.SUCCESS(
            f"\nDone in {elapsed:.1f}s\n"
            f"  Found      : {found:,}\n"
            f"  Not found  : {not_found:,}\n"
            f"  Errors     : {errors:,}\n"
            + (f"  (DRY RUN — nothing saved)" if dry_run else "")
        ))

        if not_found > 0:
            self.stdout.write(self.style.WARNING(
                f"\nTip: {not_found:,} products had no image found. "
                "Try --source pexels with a PEXELS_API_KEY for better name-search coverage."
            ))
