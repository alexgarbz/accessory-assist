#!/usr/bin/env python3
"""Validate the remotely managed catalogue before it is published.

This is the authoritative gate. It runs in CI on every change to remote-data/
and can be run locally before committing:

    python3 scripts/validate_catalogue.py            # validates remote-data/
    python3 scripts/validate_catalogue.py some/dir   # validates another copy

Checks performed:
  * JSON parses and required top-level keys are present
  * every product has a unique id
  * every product has a valid, unique SKU (duplicates are rejected)
  * every SKU is encodable as a Code 128 barcode
  * every referenced image exists in images/
  * every bundle references product ids that exist and are sellable
  * prices are numeric and non-negative
  * compatible vehicle values come from the published vehicle list
  * categories referenced by products exist
  * announcement windows are the right way round

`AccessoryAssist/Services/CatalogueValidator.swift` implements the same rules
on device, so content that somehow bypasses CI is still rejected before it can
replace a working catalogue.
"""

import json
import os
import re
import sys

# Accepts Tesla part numbers as printed on the item (1529454-42-H, 2048569-RH-A)
# and the internal scheme used by sample content (TSL-MY-INT-0142).
SKU_PATTERN = re.compile(r"^[A-Z0-9]{2,10}(-[A-Z0-9]{1,6}){1,4}$")
ALLOWED_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".heic", ".webp"}
ALLOWED_STATUSES = {"active", "discontinued", "upcoming"}
ALLOWED_SEVERITIES = {"info", "warning", "critical"}
SUPPORTED_SCHEMA_VERSION = 1
UNIVERSAL_VEHICLE_ID = "universal"

RESET = "\033[0m"
RED = "\033[31m"
YELLOW = "\033[33m"
GREEN = "\033[32m"


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def error(self, path, message):
        self.errors.append((path, message))

    def warn(self, path, message):
        self.warnings.append((path, message))

    @property
    def ok(self):
        return not self.errors


def load_json(path, report):
    if not os.path.exists(path):
        report.error(os.path.basename(path), "File is missing.")
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except json.JSONDecodeError as exc:
        report.error(os.path.basename(path), "Invalid JSON: %s" % exc)
        return None


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def can_encode_code128(text):
    """Code 128 Subset B covers printable ASCII 32-126."""
    return bool(text) and all(32 <= ord(character) <= 126 for character in text)


def validate_version(version, report):
    if version is None:
        return
    schema = version.get("schemaVersion", 1)
    if not isinstance(schema, int) or schema > SUPPORTED_SCHEMA_VERSION:
        report.error("version.json", "schemaVersion %r is not supported (max %d)."
                     % (schema, SUPPORTED_SCHEMA_VERSION))
    catalogue_version = version.get("catalogueVersion")
    if not isinstance(catalogue_version, int) or catalogue_version < 0:
        report.error("version.json", "catalogueVersion must be a non-negative integer.")
    files = version.get("files", {})
    for key in ("catalogue", "bundles", "announcements"):
        name = files.get(key)
        if name is not None and not isinstance(name, str):
            report.error("version.json", "files.%s must be a string." % key)


def validate_catalogue(catalogue, image_names, report):
    """Returns (products_by_id, vehicle_ids)."""
    products_by_id = {}
    vehicle_ids = set()
    category_ids = set()

    if catalogue is None:
        return products_by_id, vehicle_ids

    vehicles = catalogue.get("vehicles", [])
    if not vehicles:
        report.error("catalogue.json", "At least one vehicle must be published.")
    for index, vehicle in enumerate(vehicles):
        path = "catalogue.json vehicles[%d]" % index
        vehicle_id = vehicle.get("id")
        if not vehicle_id:
            report.error(path, "Vehicle id is missing.")
            continue
        if vehicle_id in vehicle_ids:
            report.error(path, "Duplicate vehicle id %r." % vehicle_id)
        vehicle_ids.add(vehicle_id)
        if not vehicle.get("name"):
            report.error(path, "Vehicle %r has no name." % vehicle_id)

    categories = catalogue.get("categories", [])
    if not categories:
        report.error("catalogue.json", "At least one category must be published.")
    for index, category in enumerate(categories):
        path = "catalogue.json categories[%d]" % index
        category_id = category.get("id")
        if not category_id:
            report.error(path, "Category id is missing.")
            continue
        if category_id in category_ids:
            report.error(path, "Duplicate category id %r." % category_id)
        category_ids.add(category_id)
        if not category.get("name"):
            report.error(path, "Category %r has no name." % category_id)

    products = catalogue.get("products")
    if not products:
        report.error("catalogue.json", "Catalogue contains no products.")
        return products_by_id, vehicle_ids

    skus = {}
    for index, product in enumerate(products):
        product_id = product.get("id", "<missing id>")
        path = "catalogue.json products[%d] %s" % (index, product_id)

        # Unique id
        if not product.get("id"):
            report.error(path, "Product id is missing.")
        elif product_id in products_by_id:
            report.error(path, "Duplicate product id %r." % product_id)
        else:
            products_by_id[product_id] = product

        # SKU
        sku = product.get("sku")
        if not sku:
            report.error(path, "SKU is missing.")
        else:
            if not SKU_PATTERN.match(sku):
                report.error(path, "SKU %r does not match the required format "
                                   "(uppercase alphanumeric groups separated by hyphens)." % sku)
            if not can_encode_code128(sku):
                report.error(path, "SKU %r cannot be encoded as a Code 128 barcode." % sku)
            if sku in skus:
                report.error(path, "Duplicate SKU %r, already used by %r." % (sku, skus[sku]))
            else:
                skus[sku] = product_id

        # Name
        if not (product.get("name") or "").strip():
            report.error(path, "Product name is empty.")

        # Price
        price = product.get("price")
        if not is_number(price):
            report.error(path, "Price must be a number, found %r." % (price,))
        elif price < 0:
            report.error(path, "Price must not be negative.")
        elif price == 0 and product.get("status", "active") == "active":
            report.warn(path, "Active product is priced at zero.")

        # Status
        status = product.get("status", "active")
        if status not in ALLOWED_STATUSES:
            report.error(path, "Unknown status %r. Allowed: %s."
                         % (status, ", ".join(sorted(ALLOWED_STATUSES))))

        # Category
        category_id = product.get("categoryId")
        if category_id not in category_ids:
            report.error(path, "Unknown category %r." % category_id)

        # Vehicle compatibility
        compatible = product.get("compatibleVehicles") or []
        if not compatible:
            report.error(path, "No compatible vehicles listed. Use %r for fit-all accessories."
                         % UNIVERSAL_VEHICLE_ID)
        for vehicle_id in compatible:
            if vehicle_id not in vehicle_ids:
                report.error(path, "Unknown vehicle %r. Allowed: %s."
                             % (vehicle_id, ", ".join(sorted(vehicle_ids))))

        validate_image(product.get("imageName"), path, image_names, report)

    return products_by_id, vehicle_ids


def validate_image(image_name, path, image_names, report):
    if not image_name:
        report.error(path, "imageName is missing.")
        return
    if "/" in image_name or ".." in image_name:
        report.error(path, "imageName must be a bare file name inside images/.")
        return
    extension = os.path.splitext(image_name)[1].lower()
    if extension not in ALLOWED_IMAGE_EXTENSIONS:
        report.error(path, "Image %r uses an unsupported file type." % image_name)
    if image_name not in image_names:
        report.error(path, "Image %r does not exist in images/." % image_name)


def validate_bundles(bundles_doc, products_by_id, vehicle_ids, image_names, report):
    if bundles_doc is None:
        return
    bundles = bundles_doc.get("bundles", [])
    seen = set()
    for index, bundle in enumerate(bundles):
        bundle_id = bundle.get("id", "<missing id>")
        path = "bundles.json bundles[%d] %s" % (index, bundle_id)

        if not bundle.get("id"):
            report.error(path, "Bundle id is missing.")
        elif bundle_id in seen:
            report.error(path, "Duplicate bundle id %r." % bundle_id)
        seen.add(bundle_id)

        if not (bundle.get("name") or "").strip():
            report.error(path, "Bundle name is empty.")

        status = bundle.get("status", "active")
        if status not in ALLOWED_STATUSES:
            report.error(path, "Unknown status %r." % status)

        product_ids = bundle.get("productIds") or []
        if not product_ids:
            report.error(path, "Bundle contains no products.")

        list_price = 0
        for product_id in product_ids:
            product = products_by_id.get(product_id)
            if product is None:
                report.error(path, "References unknown product %r." % product_id)
                continue
            if status == "active" and product.get("status", "active") != "active":
                report.error(path, "Active bundle references %s product %r."
                             % (product.get("status"), product_id))
            if is_number(product.get("price")):
                list_price += product["price"]

        price = bundle.get("bundlePrice")
        if not is_number(price):
            report.error(path, "bundlePrice must be a number, found %r." % (price,))
        elif price < 0:
            report.error(path, "bundlePrice must not be negative.")
        elif list_price and price > list_price:
            report.warn(path, "Bundle price %.2f exceeds the sum of its products (%.2f)."
                        % (price, list_price))

        for vehicle_id in bundle.get("compatibleVehicles") or []:
            if vehicle_id not in vehicle_ids:
                report.error(path, "Unknown vehicle %r." % vehicle_id)

        validate_image(bundle.get("imageName"), path, image_names, report)


def validate_announcements(doc, report):
    if doc is None:
        return
    seen = set()
    for index, announcement in enumerate(doc.get("announcements", [])):
        announcement_id = announcement.get("id", "<missing id>")
        path = "announcements.json announcements[%d] %s" % (index, announcement_id)

        if not announcement.get("id"):
            report.error(path, "Announcement id is missing.")
        elif announcement_id in seen:
            report.error(path, "Duplicate announcement id %r." % announcement_id)
        seen.add(announcement_id)

        if not (announcement.get("title") or "").strip():
            report.error(path, "Announcement title is empty.")

        severity = announcement.get("severity", "info")
        if severity not in ALLOWED_SEVERITIES:
            report.error(path, "Unknown severity %r." % severity)

        starts = announcement.get("startsAt")
        ends = announcement.get("endsAt")
        if starts and ends and ends < starts:
            report.error(path, "Announcement ends before it starts.")


def validate_orphan_images(image_names, referenced, report):
    for name in sorted(image_names - referenced):
        report.warn("images/%s" % name, "Image is not referenced by any product or bundle.")


def main():
    data_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "remote-data"
    )
    data_dir = os.path.abspath(data_dir)

    print("Validating catalogue in %s" % data_dir)
    report = Report()

    images_dir = os.path.join(data_dir, "images")
    image_names = set()
    if os.path.isdir(images_dir):
        image_names = {
            name for name in os.listdir(images_dir)
            if not name.startswith(".")
        }
    else:
        report.error("images/", "Images directory is missing.")

    version = load_json(os.path.join(data_dir, "version.json"), report)
    catalogue = load_json(os.path.join(data_dir, "catalogue.json"), report)
    bundles = load_json(os.path.join(data_dir, "bundles.json"), report)
    announcements = load_json(os.path.join(data_dir, "announcements.json"), report)

    validate_version(version, report)
    products_by_id, vehicle_ids = validate_catalogue(catalogue, image_names, report)
    validate_bundles(bundles, products_by_id, vehicle_ids, image_names, report)
    validate_announcements(announcements, report)

    referenced = set()
    if catalogue:
        referenced |= {p.get("imageName") for p in catalogue.get("products", []) if p.get("imageName")}
    if bundles:
        referenced |= {b.get("imageName") for b in bundles.get("bundles", []) if b.get("imageName")}
    validate_orphan_images(image_names, referenced, report)

    for path, message in report.warnings:
        print("%swarning%s %s: %s" % (YELLOW, RESET, path, message))
    for path, message in report.errors:
        print("%serror%s   %s: %s" % (RED, RESET, path, message))

    product_count = len(products_by_id)
    bundle_count = len(bundles.get("bundles", [])) if bundles else 0
    print("")
    print("%d products, %d bundles, %d images checked" % (product_count, bundle_count, len(image_names)))

    if report.ok:
        print("%sCatalogue is valid%s (%d warnings)" % (GREEN, RESET, len(report.warnings)))
        return 0

    print("%sCatalogue is invalid%s: %d errors, %d warnings"
          % (RED, RESET, len(report.errors), len(report.warnings)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
