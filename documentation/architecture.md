# Architecture

Accessory Assist is a SwiftUI iPhone app for Tesla retail staff. It answers one
question quickly — "what accessory does this customer need, and what is its
barcode?" — from a catalogue that is managed remotely and works offline.

Minimum iOS 17.0 · Swift 5 language mode · Xcode 16+ (developed against 26.6)
· no third-party dependencies.

---

## Layers

```
App/            Composition root, tab structure, value-typed navigation
Features/       One folder per screen area, SwiftUI views only
DesignSystem/   Tokens and shared components. All visual values live here
Models/         Decodable content types + CatalogueSnapshot lookups
Services/       Catalogue sync, cache, validation, cart, favourites, settings
Utilities/      Code 128, formatting, haptics, screen brightness
Tests/          XCTest unit tests
```

Dependencies point one way: `Features` → `DesignSystem` + `Services` → `Models`
→ `Utilities`. No service imports a view; no view constructs a service.

State is held in five `ObservableObject`s created once in
`AccessoryAssistApp.init()` and injected as environment objects:

| Object | Owns |
| --- | --- |
| `AppSettings` | Catalogue source, vehicle filter, scan brightness, haptics, developer unlock |
| `CatalogueService` | The catalogue snapshot, update state machine, status |
| `ImageStore` | Product imagery, memory + disk cache |
| `CartStore` | The sale in progress |
| `FavouritesStore` | Saved products |

`ObservableObject` rather than `@Observable`: the app targets iOS 17 but the
pattern is the widely-understood one, and nothing here needs fine-grained
observation.

---

## Catalogue update flow

The sequence, implemented in `CatalogueService.performRefresh(force:)`:

```
launch / foreground / pull-to-refresh / Refresh Catalogue
        │
        ├─ 0. publish cached (or bundled) catalogue immediately  ← UI is usable now
        │
        ├─ 1. GET version.json
        │       └─ decode fails → CatalogueError.malformed, keep previous
        │
        ├─ 2. remote catalogueVersion <= cached, and not forced?
        │       └─ stop. Outcome .upToDate. No content downloaded.
        │
        ├─ 3. GET catalogue.json + bundles.json + announcements.json (concurrently)
        │
        ├─ 4. decode each → validate the whole set
        │       └─ any error → CatalogueError.rejected, keep previous,
        │                       record the issues for Catalogue Status
        │
        ├─ 5. write all four files to a staging directory, then swap atomically
        │
        └─ 6. prefetch product images in bounded batches (offline readiness)
```

Every failure path keeps the last catalogue that passed validation. There is no
state in which the app has partially-applied content.

### Why cache raw bytes

`CatalogueCacheStore` stores the exact response bytes, not re-encoded models.
What replays on the next launch is byte-identical to what was validated, and the
model types only need `Decodable`.

The swap is: write to `staging/` → move `current/` to `previous/` → move
`staging/` to `current/` → delete `previous/`. If the promotion throws, the
previous directory is moved back. A crash mid-write cannot corrupt the live copy.

Each `CatalogueSource` gets its own cache directory (`cacheKey`), so production,
staging and custom content can never mix, and switching back to production
restores the last approved catalogue with no download.

### Three tiers of content

1. **Network** — the published catalogue.
2. **Device cache** — the last catalogue that passed validation.
3. **Bundled seed** — `Resources/Seed/`, a copy of `remote-data/` at build time.

The seed guarantees a first launch with no network is still usable. The UI
always labels it ("Using bundled catalogue"), because its prices are as old as
the build. Refresh it with `./scripts/sync_seed_resources.sh`.

### Images

Content points at an image one of two ways, modelled by `CatalogueImageRef`:

* `imageURL` — an absolute https URL to photography hosted elsewhere. This is
  what the current catalogue uses: products carry Tesla's own asset URLs, so
  real product photography appears without this repository redistributing any of
  it, and the image is always the publisher's current one.
* `imageName` — a bare file name served from `<base URL>/images/`, for imagery
  published alongside the catalogue.

An absolute URL wins when both are present. Either way the lookup order is the
same — memory → device cache → network → an image bundled with the app — and
anything fetched is written to disk, so a store that has loaded the catalogue
once keeps its photography with no connection.

Cache entries for external photography are keyed by product id rather than by
the remote file name: two products can reference files that collide once the
URL path is dropped, and their cache entries must not.

---

## Validation

The same rules exist twice, deliberately:

* `scripts/validate_catalogue.py` — runs in CI on every change to
  `remote-data/`, and can enumerate `images/`, so it is the authority on image
  existence. This is the gate that stops bad content being published at all.
* `Services/CatalogueValidator.swift` — runs on device before any download
  replaces the cache. It cannot enumerate remote storage, so it checks
  everything except image existence.

The device-side copy is not redundant. It defends against content published by
another route, a partially-deployed CDN, or a stale file served from an
intermediate cache — and it is what makes "invalid updates do not replace the
working local copy" true rather than merely intended.

Rules are listed in [catalogue-schema.md](catalogue-schema.md). Errors block a
publish; warnings (zero price, bundle priced above contents, unreferenced image)
are reported and allowed.

---

## Barcodes

`Utilities/Code128.swift` implements Code 128 Subset B from the specification.
It has no UIKit or Core Image dependency: it turns a string into `[Bool]`
modules and nothing else, which is what makes it directly testable and
resolution-independent.

**Why Code 128:** SKUs are alphanumeric with hyphens (`TSL-MY-INT-0142`).
Subset B covers printable ASCII 32–126, so any SKU the content team can type
encodes without transformation, and Code 128 is read by default by every mPOS
scanner in the field. Numeric-only symbologies (EAN/UPC) cannot represent this
SKU format at all.

`Features/BarcodeScan/BarcodeView.swift` draws the modules with antialiasing
**disabled** via `GraphicsContext.withCGContext`, so every module edge lands on
a hard pixel boundary — a softened edge is the usual reason a screen-displayed
barcode reads slowly. Adjacent bar modules are coalesced into single rectangles
so the rasteriser sees whole bars. Colours are fixed black-on-white in both
appearances; scanner contrast is not something to theme.

Barcode images are never stored, in the repository or on the device. They are
generated from the SKU on demand.

Scan mode (`ScanModeView`) takes over two system-wide settings and gives both
back: screen brightness (raised to the configured level, restored on exit) and
the idle timer (disabled so the display cannot sleep mid-transaction). The
restore path runs on dismissal and again in `deinit`.

Verification: the unit tests decode generated symbols with an independently
written reader (`Code128Reader` in `Code128Tests.swift`) and check the symbol
table's structural invariants, so a mistyped pattern cannot ship. During
development, rendered screens were also decoded with Apple's Vision barcode
detector, which read them as Code 128 at ~0.96 confidence.

---

## Design system

`DesignSystem/` holds every visual value: `Palette`, `TypeScale`, `Spacing`,
`Radius`, `Stroke`, `IconSize`, `TouchTarget`, `Motion`, `ImageRatio`. No view
hard-codes a colour, a font size, or a corner radius.

Interpretation of the supplied Tesla design guidance, and where it was adapted:

| Guideline | How it is applied |
| --- | --- |
| One chromatic colour, Electric Blue `#3E6AE1`, for primary action only | `Palette.accent`. Used for the primary button, selected chips, links. Never decorative. |
| White canvas, Carbon Dark `#171A20` text, three grey text tiers | `Palette.canvas` / `textPrimary` / `textSecondary` / `textTertiary`. |
| No shadows, no gradients, no borders on cards | `CardSurface` is a fill and a radius. There is no shadow anywhere in the app. |
| 4px radius on interactive elements, ~12px on large image surfaces | `Radius.control` = 4, `Radius.card` = 12. Nothing is a pill. |
| Weights 400/500 only, default letter-spacing | `TypeScale` uses `.regular` and `.medium` only. Tracking is default everywhere except the wordmark. |
| 0.33s transitions | `Motion.duration` = 0.33, and it collapses to no animation under Reduce Motion. |
| 8px spacing base | `Spacing` = 4/8/12/16/24/32/48. |
| Photography carries the weight | Fixed-ratio image containers, minimal chrome, product imagery is the largest element on Home cards and detail. |

Two deliberate departures:

* **Typography.** The guidance specifies Universal Sans at fixed pixel sizes.
  That typeface is not licensed for redistribution, and fixed pixel sizes would
  break Dynamic Type — which the brief also requires. The system uses SF Pro
  bound to iOS text styles, keeping what actually matters: two weights, default
  tracking, and a fixed hierarchy that scales with the user's text size.
* **Status colour.** The guidance avoids semantic colour entirely, which suits a
  marketing site. This is an operational tool where "discontinued", "using stale
  data" and "publish rejected" must be unmissable. `Palette.warning` and
  `Palette.critical` exist, desaturated, and are used only for status.

Dark appearance is built on Carbon Dark with the same contrast relationships
rather than a different mood.

### Accessibility

Dynamic Type through text styles (verified to accessibility sizes); VoiceOver
labels on every control, with SKUs spelled character-by-character via
`Format.spokenSKU` so they are not read as words; Reduce Motion respected by
`Motion`; 44pt minimum touch targets, 52pt for primary actions, 72pt for scan
mode stepping; selected states carry `.isSelected` traits, not just colour.

---

## Navigation

Five tabs (Home, Catalogue, Favourites, Cart, Settings), each with its own
`NavigationStack`. Navigation is value-typed: `NavigationLink(value: product)`
plus `.catalogueDestinations()`, a single modifier registering destinations for
`Product`, `AccessoryBundle` and `CatalogueRoute`. Any screen can link to any
other without threading bindings.

Catalogue rows are plain stacks with hairline separators rather than `List`
rows: `List` adds a disclosure chevron to every navigating row, and this design
separates rows with space, not chrome. The cart keeps `List` for swipe-to-delete.

---

## Testing

74 XCTest cases, no network:

| Suite | Covers |
| --- | --- |
| `Code128Tests` | Symbol table invariants, checksum arithmetic, quiet zones, module counts, rejection of unencodable input, and round-tripping every generated symbol back through an independent decoder |
| `CatalogueDecodingTests` | Field mapping, optional defaults, `description`→`detail`, `Decimal` exactness, ISO 8601 handling, forward-compatible unknown enum values, snapshot lookups and pricing maths, and that the bundled seed is itself valid |
| `CatalogueValidatorTests` | One test per publishing rule, in both directions — bad content rejected, good content accepted |
| `CatalogueUpdateTests` | The whole update flow against a fake fetcher: version-first probing, skipping unchanged downloads, forced refresh, and that rejected, malformed and offline updates all retain the previous working catalogue across a simulated relaunch |

```bash
xcodebuild test -project AccessoryAssist.xcodeproj -scheme AccessoryAssist \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## Authenticated content delivery

**The prototype hosts the catalogue on GitHub raw URLs and embeds no
credentials.** The repository is public, so those URLs are readable by the app
without authentication of any kind, and product photography comes from a public
asset CDN. Nothing needs configuring to run it.

No personal access token is embedded in the app, and none should be — including
if this content moves back behind authentication. A token in an app binary is
extractable by anyone with the device and grants repository access far beyond
reading a catalogue. Authentication belongs in a credential the device is
provisioned with, not in the binary.

Before internal deployment, catalogue delivery needs:

1. **An authenticated endpoint.** A CDN or internal service fronting the content
   — not `raw.githubusercontent.com`. Publishing stays a git merge; a deploy
   step copies `remote-data/` to that origin.
2. **Per-device credentials from MDM**, or short-lived tokens obtained through
   the existing staff SSO — never a shared secret compiled into the app.
3. **Certificate pinning** on the catalogue host, since prices drive what staff
   quote to customers.
4. **Content signing.** Sign `version.json` (or a manifest of file digests) and
   verify the signature on device before validation. This closes the gap that
   transport security alone leaves: it proves the content came from the
   publishing pipeline, not merely from a host with a valid certificate.
5. **Staged rollout and rollback** — publish to a percentage of devices first,
   and be able to re-publish a previous `catalogueVersion` quickly.

Only step 1 and step 2 change app code, and both are contained: the source of
the base URL and the addition of an `Authorization` header in
`CatalogueRemoteClient`. Caching, validation, fallback and the UI are unaffected.

Nothing else about this app needs to change to be deployed internally: it holds
no customer data, takes no payment, requires no login, and reads no vehicle.
