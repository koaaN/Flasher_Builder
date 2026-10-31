# Bundled aria2

The app invokes these unmodified aria2 1.37.0 binaries as separate processes:

- Windows x64: official `aria2/aria2`, `release-1.37.0`, win-64bit-build1.
- Linux x64: `abcfy2/aria2-static-build`, `1.37.0`, x86_64-linux-musl_static.
  The upstream build recipe is pinned at commit
  `b2021c5a4135c994b838b101c0e70cc3bd69dbb6` and copied here for reference.

`tools/dependencies.json` pins the archive, executable and source checksums.
`scripts/fetch_tools.py` fetches and verifies the binaries and corresponding
source archives. The app does not run the upstream build script.

The license is GPL-2.0-or-later (`COPYING`). `licenses/` contains the included
dependencies' notices, license texts and applicable runtime exceptions.
SQLite is public domain. The Linux binary's exact dependency versions and
source origins are recorded in `linux-build-info.md`; Windows dependency
versions are in `README.mingw`. License origins are in `license-origins.json`.

Every platform release and the source ZIP include complete aria2 source, plus
GMP 6.3.0, libiconv 1.19 and XZ 5.8.3 source under `sources/`. These cover the
GPL/LGPL components in the distributed static builds. Other linked components
use permissive licenses; their notices are in `licenses/`.

To rebuild or relink with replacement libraries, unpack the included sources,
build the dependencies statically into a separate prefix with a compatible
musl C/C++ toolchain for Linux or mingw-w64 for Windows, then configure aria2:

```sh
PKG_CONFIG_PATH="$ARIA2_PREFIX/lib/pkgconfig" \
  ./configure --host="$ARIA2_TARGET" --prefix="$ARIA2_PREFIX" \
  --enable-static --disable-shared ARIA2_STATIC=yes
make
```

Use `x86_64-linux-musl` or `x86_64-w64-mingw32` as the target, setting `CC`,
`CXX` and `LDFLAGS` for that toolchain and replacement library prefix. The
Windows build notes are included as `README.mingw`. The upstream Linux
recipe documents its static compiler/linker flags; pin dependencies to the
versions in the build information instead of fetching the latest versions.
The rebuilt executable can replace `aria2c` or `aria2c.exe` in this directory.
