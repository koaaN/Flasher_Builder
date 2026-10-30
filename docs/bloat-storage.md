# Bloat release storage

All bloat images live together in the private `bloat-assets-v1` release of
`koaaN/Flasher_Builder`. There are 51 deduplicated image attachments covering
144 device/region image paths, plus `assets-manifest.json` and `SHA256SUMS`.

The repository's `bloat/assets-manifest.json` pins the release asset IDs,
transport sizes and SHA-256 checksums, original image sizes/checksums, and the
mapping from each image path to an attachment. Identical image contents share
an attachment. The 2.02 GiB Ace 6T ODM image is stored as a 1.70 GiB lossless gzip
attachment so that every attachment is under GitHub's 2 GiB limit.

## Builds

Install GitHub CLI (`gh`) and authenticate with read access to the private
repository. On Windows this login belongs inside the WSL build environment.
The GUI never saves authentication tokens in its settings file.

During staging, `scripts/materialize_bloat.py` selects assets for the device,
region and flasher type, including conversion/signal fixes. It checks existing
local images, downloads missing release attachments one at a time, and caches
verified objects in `.bloat-cache/`. It verifies both the downloaded object and
the final decompressed image before atomically installing it in the job folder.

The GUI keeps its cache outside each temporary job directory. For direct
staging-script invocations, `BLOAT_CACHE_DIR` overrides the cache location.
GitHub Actions supplies its read-only repository token through `GH_TOKEN` and
uses the runner temporary directory for caching.

A normal clone or source ZIP contains the manifest, not all bloat images.
Only the selected build's images are materialized. Existing local images are
reused when their exact sizes and checksums match the manifest. Fully cached
build inputs can be reused offline.

## Retention and billing

These are release attachments, not Actions artifacts or Git LFS objects.
Release assets have no automatic age-based expiration. GitHub documents a
limit of 1,000 attachments per release, each under 2 GiB, with no total release
size or download bandwidth limit. The repository and its releases remain
private. No paid Git LFS asset uploads are used.

References:
- https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository

## Download before building

The Bloat files panel in the GUI provides a remembered folder picker and a
Download bloat button for the current device/flasher/region. No OTA input is
required. SHA-256 checks run in the background to show Already downloaded or a
missing-file count. Builds reuse this folder's verified raw images. The chosen
folder's hidden `.cache` holds transport objects for repairs.
