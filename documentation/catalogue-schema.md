# Catalogue Schema

Reference for the four JSON files in `remote-data/`. Every rule listed as
**required** or **must** is enforced by `scripts/validate_catalogue.py` in CI and
again on device by `CatalogueValidator.swift` before a download is allowed to
replace the working catalogue.

All timestamps are ISO 8601 with a timezone (`2026-07-20T09:00:00Z`). Fractional
seconds are accepted. All money values are JSON numbers — never strings.

---

## version.json

The small file the app fetches on every launch. If `catalogueVersion` is not
newer than the copy already on the device, nothing else is downloaded.

```json
{
  "schemaVersion": 1,
  "catalogueVersion": 12,
  "environment": "production",
  "publishedAt": "2026-07-20T09:00:00Z",
  "minimumAppBuild": 1,
  "files": {
    "catalogue": "catalogue.json",
    "bundles": "bundles.json",
    "announcements": "announcements.json"
  },
  "notes": "Q3 delivery kit pricing."
}
```

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `schemaVersion` | int | no (default 1) | Rejected if greater than the app's supported version. Bump only for breaking shape changes. |
| `catalogueVersion` | int | **yes** | Monotonically increasing. **Increment this on every content change** or devices will not download it. |
| `environment` | string | no | `production` on `main`, `staging` on `staging`. CI enforces the match. |
| `publishedAt` | timestamp | no | Shown on the Catalogue Status screen. |
| `minimumAppBuild` | int | no | Reserved for forcing an app update. |
| `files` | object | no | Lets content files be renamed without an app release. Defaults to the standard names. |
| `notes` | string | no | Free text shown to staff on Catalogue Status. Use it to say what changed. |

---

## catalogue.json

Vehicles, categories and products.

```json
{
  "schemaVersion": 1,
  "environment": "production",
  "generatedAt": "2026-07-20T09:00:00Z",
  "currency": "USD",
  "vehicles": [ ... ],
  "categories": [ ... ],
  "products": [ ... ]
}
```

### vehicles[]

The **approved vehicle list**. A product may only reference an id published
here; this is what stops a typo silently hiding stock.

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | **yes** | Unique, lowercase snake_case, e.g. `model_y`. Referenced by products and bundles. |
| `name` | string | **yes** | Display name, e.g. `Model Y`. |
| `order` | int | no | Sort order in the vehicle filter. |

The id `universal` is reserved: a product listing `universal` fits every
vehicle. It is published as a vehicle (named "All Vehicles") but is never
offered as a filter choice.

Current approved ids: `model_s`, `model_3`, `model_x`, `model_y`, `cybertruck`,
`universal`.

### categories[]

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | **yes** | Unique, e.g. `interior`. |
| `name` | string | **yes** | Display name, e.g. `Interior`. |
| `order` | int | no | Sort order in the category filter row. |

### products[]

```json
{
  "id": "p_my_int_liners",
  "sku": "TSL-MY-INT-0142",
  "name": "Model Y All-Weather Interior Liners",
  "summary": "Front, rear and trunk liners moulded to the Model Y floor pan.",
  "description": "Laser-measured thermoplastic liners covering …",
  "price": 235.00,
  "categoryId": "interior",
  "compatibleVehicles": ["model_y"],
  "imageName": "p_my_int_liners.png",
  "status": "active",
  "featured": true,
  "fitNotes": "Fits 5-seat and 7-seat configurations.",
  "tags": ["liners", "floor mats", "weather"]
}
```

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `id` | string | **yes** | **Unique across the catalogue.** Stable forever — favourites and carts on staff devices reference it. Never reuse an id for a different product. |
| `sku` | string | **yes** | **Unique across the catalogue.** Must match `^[A-Z0-9]{2,5}(-[A-Z0-9]{1,6}){1,4}$` and be Code 128-encodable. This is what the barcode encodes. |
| `name` | string | **yes** | Non-empty. Shown in rows, cards and scan mode. |
| `summary` | string | no | One line, shown under the name on product detail. Not shown in rows. |
| `description` | string | no | Long form. Decoded into `Product.detail` in Swift. Product detail screen only. |
| `price` | number | **yes** | Non-negative. A zero price on an active product is a warning. Decoded as `Decimal` — exact, never floating-point drift. |
| `categoryId` | string | **yes** | Must exist in `categories`. |
| `compatibleVehicles` | string[] | **yes** | Non-empty. Every entry must exist in `vehicles`. Use `["universal"]` for fit-all. |
| `imageName` | string | **yes** | Bare file name (no path) that **must exist** in `remote-data/images/`. `.png`, `.jpg`, `.jpeg`, `.heic` or `.webp`. |
| `status` | string | no (default `active`) | `active`, `discontinued` or `upcoming`. Only `active` products are sellable, appear in filters by default, or may sit in an active bundle. Unrecognised values decode as "unknown" on device (an old build keeps working) but are **rejected at publish time**. |
| `featured` | bool | no | Appears in the Home "Featured Accessories" row. |
| `fitNotes` | string | no | Fitment warning shown prominently on product detail. Use for "confirm build year", "installation not included" and similar. |
| `tags` | string[] | no | Extra search terms. Searchable alongside name, SKU and summary. |

---

## bundles.json

```json
{
  "schemaVersion": 1,
  "environment": "production",
  "bundles": [
    {
      "id": "b_delivery_my",
      "name": "Model Y Delivery Day Kit",
      "summary": "The four accessories most often added at handover.",
      "description": "Everything a new Model Y owner needs on day one …",
      "productIds": ["p_my_int_liners", "p_my_crg_cargo_liner"],
      "bundlePrice": 480.00,
      "imageName": "b_delivery_my.png",
      "compatibleVehicles": ["model_y"],
      "status": "active",
      "featured": true
    }
  ]
}
```

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `id` | string | **yes** | Unique across bundles. |
| `name` | string | **yes** | Non-empty. |
| `summary` / `description` | string | no | `description` decodes into `detail`. |
| `productIds` | string[] | **yes** | Non-empty. **Every id must exist** in `catalogue.json`. An `active` bundle may not reference a non-active product. |
| `bundlePrice` | number | **yes** | Non-negative. Pricing above the sum of contents is a warning, not an error. |
| `imageName` | string | **yes** | Same rules as products. |
| `compatibleVehicles` | string[] | no | Entries must exist in `vehicles`. Empty means it fits everything. |
| `status` | string | no (default `active`) | Same values as products. |
| `featured` | bool | no | Appears in the Home "Bundles" row. |

The bundle price is a **merchandising price, not a discount code**. Each SKU is
still scanned individually at the mPOS terminal — scan mode walks the component
products, one barcode per item.

---

## announcements.json

Operational notices for staff. Never marketing copy.

```json
{
  "schemaVersion": 1,
  "announcements": [
    {
      "id": "a_ccs_eligibility",
      "title": "Check CCS adapter eligibility before sale",
      "body": "Confirm retrofit eligibility in the service portal …",
      "severity": "warning",
      "startsAt": "2026-07-01T00:00:00Z",
      "endsAt": "2026-09-30T23:59:59Z",
      "pinned": true
    }
  ]
}
```

| Field | Type | Required | Rules |
| --- | --- | --- | --- |
| `id` | string | **yes** | Unique. |
| `title` | string | **yes** | Non-empty. Shown in bold on the banner. |
| `body` | string | no | Supporting line. |
| `severity` | string | no (default `info`) | `info`, `warning`, `critical`. Unrecognised values fall back to `info` on device. |
| `startsAt` / `endsAt` | timestamp | no | Live window. `endsAt` must not precede `startsAt`. Outside the window the announcement is not shown — **set an end date**, or it stays on the Home screen forever. |
| `pinned` | bool | no | Pinned announcements appear on Home. Unpinned ones are counted on Catalogue Status but do not take Home space. |

---

## images/

One image per referenced `imageName`, flat — no subdirectories. Served from
`<base URL>/images/<imageName>`.

* Referenced images **must** exist. A missing image fails CI.
* Unreferenced images are reported as a warning (they cost bandwidth, nothing else).
* Placeholders in this repository are generated by
  `scripts/generate_placeholder_images.py`. Replace them with real photography
  using the same file names — no catalogue change is needed.
* Recommended: 4:3, at least 1200px wide, product on a plain light background.

---

## Validating before you publish

```bash
python3 scripts/validate_catalogue.py
```

Exits non-zero and lists every problem with its exact path
(`catalogue.json products[4] p_my_int_sunshade: Image 'missing.png' does not
exist in images/.`). The same checks run automatically in CI on every change to
`remote-data/`.
