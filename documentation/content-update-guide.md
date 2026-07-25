# Content Update Guide

How to change what staff see in the app **without building or shipping a new
version of the app**.

Everything in `remote-data/` is content. Products, prices, bundles, vehicle
compatibility, images and announcements are all published by editing JSON and
merging it. The app picks the change up on its next launch or foreground.

> Prices, product names and images in this repository are invented sample
> content for a prototype. Replace them with real content before any real use.

---

## The two branches

| Branch | Serves | Use for |
| --- | --- | --- |
| `main` | **Production** — what staff sell from | Approved products, approved prices |
| `staging` | **Staging** — test content | Upcoming products, pricing tests, bundle experiments |

The app reads `main` by default. Staging is reachable only through the hidden
developer setting (see below), and any device on staging shows a permanent
`STAGING CATALOGUE` marker at the top of the screen.

**Rule: content lands on `staging` first, is checked on a device, then is
promoted to `main` by pull request.**

---

## Making a content change

### 1. Branch from `staging`

```bash
git checkout staging
git pull
git checkout -b content/q4-winter-pricing
```

### 2. Edit the JSON

Full field reference: [catalogue-schema.md](catalogue-schema.md).

Common tasks:

**Change a price** — edit `price` on the product in `remote-data/catalogue.json`.

**Add a product** — append an object to `products[]`. It needs a unique `id`, a
unique valid `sku`, a `categoryId` and `compatibleVehicles` that already exist,
and an `imageName` that exists in `remote-data/images/`.

**Retire a product** — set `"status": "discontinued"`. Do **not** delete it:
deleting breaks favourites and carts already saved on staff devices, and removes
it from SKU lookup. Discontinued products stay searchable and are shown with a
"Discontinued" pill and a disabled Add to Cart.

**Change a bundle** — edit `productIds` and `bundlePrice` in
`remote-data/bundles.json`. Every id must exist and be `active`.

**Post a notice** — add to `remote-data/announcements.json` with `pinned: true`
to put it on the Home screen. **Always set `endsAt`** or it stays there forever.

**Swap an image** — replace the file in `remote-data/images/` keeping the same
file name. No catalogue edit needed.

### 3. Increment the catalogue version

In `remote-data/version.json`:

```json
"catalogueVersion": 13,
"publishedAt": "2026-08-01T09:00:00Z",
"notes": "Q4 winter pricing. Roof rack discontinued."
```

**If you do not increment `catalogueVersion`, no device will download the
change.** The app compares versions and skips the download when its copy is not
older. CI fails a pull request that changes content without bumping it.

`notes` is shown to staff on the Catalogue Status screen — write what changed.

### 4. Validate locally

```bash
python3 scripts/validate_catalogue.py
```

Fix everything it reports before pushing. It checks unique ids, unique valid
SKUs, barcode encodability, image existence, bundle references, price types,
vehicle and category references, and announcement date windows.

### 5. Push and let CI check it

```bash
git add remote-data
git commit -m "Q4 winter pricing, retire roof rack"
git push -u origin content/q4-winter-pricing
```

Open a pull request into `staging`. The **Validate Catalogue** workflow runs the
same checks, plus the version bump and the `environment` field matching the
branch.

### 6. Test on a device against staging

1. Open the app, go to **Settings**.
2. Tap the **Version** row **seven times** to unlock developer settings.
3. **Developer → Catalogue Source → Staging**.
4. Pull to refresh, or **Settings → Refresh Catalogue**.
5. Check the change: prices, images, compatibility, and that the SKU produces a
   scannable barcode at the terminal.
6. Switch back to **Production** when finished. The staging marker disappears.

### 7. Promote to production

Open a pull request from `staging` into `main`. Set `environment` to
`production` in `version.json` (CI enforces this on `main`). Merge when
approved. Staff devices pick it up on next launch or when they next bring the
app to the foreground.

---

## How a device gets the update

1. On launch and on returning to the foreground, the app fetches `version.json`.
2. If `catalogueVersion` is not newer than the cached copy, it stops there — no
   further download.
3. Otherwise it downloads `catalogue.json`, `bundles.json` and
   `announcements.json`.
4. Every file is decoded and validated.
5. Only if all of it passes are the files written to the device cache
   atomically and swapped in.
6. Product images are then fetched in the background so the catalogue works
   offline.

If **anything** fails — no network, a 404, malformed JSON, a validation error —
the previous working catalogue is kept and the app shows the reason. Staff keep
selling from the last good data.

Staff can always check state at **Settings → Catalogue Status**: source, branch,
version, last updated, last checked, and any validation problems from a rejected
publish.

---

## Changing the catalogue URL

There are three ways, from most permanent to most temporary.

### A. Change the built-in default (needs an app build)

Edit `AccessoryAssist/Services/CatalogueSource.swift`:

```swift
enum RemoteCatalogueConfiguration {
    static let repositoryOwner = "alexgarbz"
    static let repositoryName = "accessory-assist"
    static let productionBranch = "main"
    static let stagingBranch = "staging"
    static let contentDirectory = "remote-data"
}
```

Production and staging URLs are derived from these:

```
https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<contentDirectory>/
```

To point at something other than GitHub entirely — a CDN, an internal server —
replace `rawBaseURL(branch:)` with the URL you need. Everything downstream
(caching, validation, fallback) is unchanged. The base URL must serve:

```
<base>/version.json
<base>/catalogue.json
<base>/bundles.json
<base>/announcements.json
<base>/images/<imageName>
```

### B. Point one device at any URL (no build)

1. Settings → tap **Version** seven times.
2. **Developer → Catalogue Source → Custom Base URL**.
3. Enter the base URL and tap **Use This URL**. A trailing slash is added if
   missing; `http` and `https` are accepted.

Each source keeps its own cache directory, so switching between production,
staging and custom never mixes content, and switching back is instant.

### C. Serve the catalogue from your own machine (for development)

```bash
cd accessory-assist/remote-data
python3 -m http.server 8000
```

Then set the custom base URL to `http://<your-mac-ip>:8000/` (use the machine's
LAN address, not `localhost`, if testing on a physical device; the simulator can
use `http://localhost:8000/`).

This is the fastest way to see a content change on a device without pushing
anything, and it is how to demonstrate the full update flow while the repository
is private.

> `http://` to a non-local host will be blocked by App Transport Security. For
> anything beyond a local development server, use `https://`.

---

## Access and the private repository

This repository is private, so `raw.githubusercontent.com` will **not** serve
these files to the app anonymously — requests return 404/401 and the app falls
back to cached or bundled content, reporting "Catalogue Unavailable" or "Using
Offline Data".

No access token is embedded in the app, deliberately: a token shipped in an app
binary is extractable by anyone holding the device.

For the prototype, use one of:

* the local server in option C above (recommended for demos), or
* a temporary public repository containing only `remote-data/`, or
* making this repository public if the content is not sensitive.

Before real internal deployment, see
[architecture.md](architecture.md#authenticated-content-delivery) for what a
production content-delivery setup has to provide.

---

## Refreshing the catalogue compiled into the app

The app ships with a copy of `remote-data/` so a first launch with no network
still shows something. It is labelled as bundled data in the UI and is expected
to be stale, but it should not be wildly out of date. Before cutting a build:

```bash
./scripts/sync_seed_resources.sh
```

This validates `remote-data/`, then copies the JSON into
`AccessoryAssist/Resources/Seed/` and the images into
`AccessoryAssist/Resources/SeedImages/`.

---

## Checklist before publishing to production

- [ ] `python3 scripts/validate_catalogue.py` passes
- [ ] `catalogueVersion` incremented
- [ ] `publishedAt` and `notes` updated
- [ ] `environment` is `production`
- [ ] New images added and referenced correctly
- [ ] Tested on a device against `staging`
- [ ] Every new SKU produces a barcode that the mPOS terminal actually reads
- [ ] Discontinued items marked, not deleted
- [ ] Announcements have an `endsAt`
