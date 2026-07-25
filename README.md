# Accessory Assist

An internal iPhone app for Tesla retail staff: find an accessory, confirm it
fits the customer's vehicle, and put a scannable barcode in front of the mPOS
terminal — in seconds, from a catalogue that is managed remotely and keeps
working offline.

Built with SwiftUI. No third-party dependencies. iOS 17.0+.

> **Unofficial prototype.** Not affiliated with, authorised by or endorsed by
> Tesla, Inc. See [LICENSE](LICENSE) and
> [Catalogue content](#catalogue-content) for exactly which data is real and
> which is invented.

---

## What it does

* **Search by name or SKU** from the Home screen, with results in place — no
  second screen between the query and the barcode.
* **Filter by vehicle** so nothing that does not fit the customer's car is shown.
* **Favourites** for the handful of SKUs a store sells constantly.
* **Bundles** — pre-priced accessory groups, with add-all-to-cart and a scan run
  through every SKU in the group.
* **Cart** — a running list and total for the sale in progress. No payment, no
  customer account, no checkout; the mPOS terminal takes the money.
* **Full-screen mPOS scan mode** — Code 128 barcode generated on device from the
  SKU, at full brightness with auto-lock disabled, large Previous/Next controls,
  swipe navigation, a position counter, and brightness restored on exit.
* **Remotely managed catalogue** — products, prices, bundles, compatibility,
  images and staff announcements are all published without an app release.
* **Offline first** — the last catalogue that passed validation, and its images,
  stay on the device. The app says when data is stale and when an update failed.

## Screens

Home · Vehicle selection · Catalogue · Search results · Product detail · Bundle
detail · Cart · mPOS scan mode · Favourites · Settings · Catalogue status ·
Offline and failed-sync states.

---

## Catalogue content

The catalogue holds **52 products across 8 categories and 6 vehicle lines**, in
**AUD**. It is a mix, and the difference matters if anyone is tempted to quote
from it:

| Part of the catalogue | Provenance |
| --- | --- |
| 33 products — charging, Model Y and Model Y L interior/cargo, apparel, lifestyle | Names, **real Tesla part numbers** and AUD prices observed on Tesla's public Australian store (`shop.tesla.com/en_au`) on **25 July 2026** |
| Home and Mobile Connector Bundle | Real bundle at its listed price (A$1,200) |
| 19 remaining products (Model S/X liners, roof rack, aero covers, vehicle care, Cybertruck items) | **Invented** sample content |
| All other bundle groupings and their prices | **Invented** merchandising, priced 10% under the sum of contents |
| Every image in `remote-data/images/` | **Generated placeholders**, not Tesla photography |

The real entries are factual reference data, not authorised by Tesla, and go out
of date the moment a price changes. **Confirm against Tesla's own systems before
any operational use.**

Four all-weather liner part numbers (`2048569-RH-A`, `-TS-A`, `-WL-A`, `-FT-A`)
are taken from Tesla's asset references rather than a published SKU field; each
carries a fitment note telling staff to confirm the part number at the counter.

SKUs are the barcode payload, so both formats are accepted and validated: Tesla
part numbers as printed on the item (`1529454-42-H`, `2048569-RH-A`) and the
internal scheme used by the sample entries (`TSL-MY-INT-0142`).

## Repository layout

```
accessory-assist/
├── AccessoryAssist.xcodeproj
├── AccessoryAssist/
│   ├── App/            Composition root, tabs, navigation
│   ├── Features/       Home, Catalogue, ProductDetail, Cart, BarcodeScan,
│   │                   Bundles, Favourites, Settings
│   ├── Models/         Decodable catalogue types
│   ├── Services/       Sync, cache, validation, cart, favourites, settings
│   ├── DesignSystem/   Tokens and shared components
│   ├── Utilities/      Code 128, formatting, haptics, brightness
│   ├── Resources/      Assets + catalogue seeded at build time
│   └── Tests/          74 unit tests
├── remote-data/        The remotely managed catalogue (the content layer)
│   ├── version.json    Polled on launch; drives whether anything downloads
│   ├── catalogue.json  Vehicles, categories, products
│   ├── bundles.json
│   ├── announcements.json
│   └── images/
├── documentation/
│   ├── catalogue-schema.md      Every field and every rule
│   ├── content-update-guide.md  How to publish without shipping an app
│   └── architecture.md          How it fits together, and why
├── scripts/
│   ├── validate_catalogue.py         Publishing gate, also run by CI
│   ├── generate_placeholder_images.py
│   └── sync_seed_resources.sh
└── .github/workflows/               Catalogue validation + iOS tests
```

---

## Getting started

```bash
git clone https://github.com/alexgarbz/accessory-assist.git
cd accessory-assist
open AccessoryAssist.xcodeproj
```

Select an iPhone simulator and run. No configuration, no keys, no package
resolution — the app launches with the catalogue bundled at build time and then
tries to refresh.

From the command line:

```bash
xcodebuild test -project AccessoryAssist.xcodeproj -scheme AccessoryAssist -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

## Branches

| Branch | Serves | Contains |
| --- | --- | --- |
| `main` | **Production** catalogue | Approved products and pricing |
| `staging` | **Staging** catalogue | Upcoming products, pricing and bundle tests |

The app reads `main`. Staging is reachable only through the hidden developer
setting, and any device on staging carries a permanent `STAGING CATALOGUE`
marker.

**To switch a device:** Settings → tap **Version** seven times → Developer →
Catalogue Source. Production, Staging, or any custom base URL.

Each source keeps its own cache, so switching never mixes content.

---

## Updating the catalogue

Full instructions: [content-update-guide.md](documentation/content-update-guide.md).

The short version:

1. Branch from `staging`, edit the JSON in `remote-data/`.
2. **Increment `catalogueVersion` in `version.json`** — without this, no device
   downloads the change.
3. `python3 scripts/validate_catalogue.py`
4. Open a PR into `staging`. CI validates it.
5. Check it on a device pointed at staging.
6. PR `staging` → `main` to publish to staff.

Devices pick the change up on next launch or foreground.

### Validation

Before any publish, and again on device before any download replaces the working
catalogue:

* every active product has a unique id
* every product has a valid, unique SKU (duplicates rejected)
* every SKU is encodable as a Code 128 barcode
* every referenced image exists
* every bundle references products that exist and are sellable
* prices are numeric and non-negative
* compatible vehicles come from the approved published list
* categories referenced by products exist

An invalid publish never replaces the working local copy. The app keeps the last
good catalogue and reports exactly which rules failed on the Catalogue Status
screen.

---

## Barcodes

Code 128 Subset B, generated on device from the SKU — never stored, never
committed. Subset B covers printable ASCII, so the full alphanumeric-and-hyphen
SKU format (`TSL-MY-INT-0142`) encodes without transformation, and Code 128 is
read by default by mPOS scanners.

Bars are drawn with antialiasing disabled so module edges land on hard pixel
boundaries, in fixed black-on-white regardless of appearance. Generated symbols
are round-tripped through an independently written decoder in the test suite;
rendered screens were also verified with Apple's Vision barcode detector, which
reads them as Code 128 at ~0.96 confidence.

---

## Hosting note — read before deploying

This repository is private, so `raw.githubusercontent.com` will not serve the
catalogue to the app anonymously. The app handles this correctly — it falls back
to cached or bundled content and reports "Using Offline Data" — but it means the
remote update flow will not visibly do anything until content is served from
somewhere the app can reach.

**No GitHub token is embedded in the app, by design.** A token in an app binary
is extractable by anyone holding the device.

For a working demonstration of the update flow, serve the content locally and
point the app at it with the custom base URL:

```bash
cd remote-data && python3 -m http.server 8000
```

Before real internal deployment, catalogue delivery needs an authenticated
endpoint, per-device credentials from MDM or staff SSO, certificate pinning and
content signing. This is set out in
[architecture.md](documentation/architecture.md#authenticated-content-delivery);
only the base URL and one request header change in app code.

---

## Design

The interface follows the supplied Tesla design guidance: a white canvas, Carbon
Dark text, one chromatic colour (Electric Blue `#3E6AE1`) reserved for primary
action, 4px radii, hairline dividers, no shadows or gradients anywhere, generous
space, and 0.33s transitions. Every visual value lives in `DesignSystem/` — no
view hard-codes a colour or a size.

Two deliberate departures, with reasoning, are documented in
[architecture.md](documentation/architecture.md#design-system): SF Pro bound to
iOS text styles instead of Universal Sans at fixed pixel sizes (Dynamic Type),
and a restrained pair of status colours for warning and critical states, which
an operational tool needs and a marketing site does not.

Dynamic Type, VoiceOver, Dark Mode, Reduce Motion and 44pt+ touch targets are
supported throughout.

---

## Scope

Deliberately **not** included, because this is a staff tool and not a storefront:
customer accounts, checkout or payment, public purchasing links, marketing
onboarding, and Tesla vehicle authentication.
