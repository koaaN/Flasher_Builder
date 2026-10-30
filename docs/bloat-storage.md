# Bloat asset audit

Audited the extensionless URL stubs from Daniel210191/Build_Tools at
`ceb218aaecaab9302633faf63e028f6781aee0e3`.

- 65 stubs resolve to 42 unique URLs. All 42 downloads completed successfully.
- SHA-256 checksums identify 34 distinct image contents.
- 20 downloads (28 target paths) fit normal Git's 100 MiB per-file limit.
- 22 downloads (37 target paths) require Git LFS.
- Normal Git content is 0.950 GiB before Git compression and history.
- LFS content is 24.270 GiB after content deduplication and the compression described below.

`bloat-upload-plan.json` and `.csv` list every source stub, target image path,
size and checksum. The `.gitattributes` rules reserve the exact large asset paths
for LFS; existing URL stubs are retained until migration.

## Ace 6T ODM

The raw ODM image is 2,168,594,432 bytes, above the 2 GiB Free/Pro LFS file limit.
A losslessly compressed `.img.gz` is 1,823,779,125 bytes and fits the limit.
Its decompressed SHA-256 was verified against the original image.
The staging script can now decompress `.img.gz` assets to `.img` automatically.
The plan uses this compressed object for all three Ace 6T ODM target paths.

## Storage and downloads

GitHub Free and Pro include 10 GiB LFS storage and 10 GiB monthly download
bandwidth, shared across the account. This complete asset set exceeds that
included storage allowance. Uploading assets is pending a storage/budget decision;
this commit only adds the audit, LFS rules and compressed-image support.

LFS duplicates with the same SHA-256 share an object. Every changed version of a
large image adds another full LFS object. Builds and clones that download LFS
assets consume the repository owner's download bandwidth.

A complete checkout with all region aliases also needs substantially more local
disk space than the unique LFS objects. For per-device work, clone with smudging
skipped and fetch only the required device:

```sh
GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/koaaN/Flasher_Builder.git
git -C Flasher_Builder lfs pull --include="bloat/13/**" --exclude=""
```

References:
- https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage
- https://docs.github.com/en/billing/concepts/product-billing/git-lfs
