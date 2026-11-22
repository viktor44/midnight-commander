# Midnight Commander for macOS

Build scripts that produce a self-contained, relocatable
[Midnight Commander](https://midnight-commander.org/) (`mc`) for macOS from the
upstream source tarballs. The result needs no Homebrew packages: the libraries
mc depends on are compiled from source and linked statically.

The repository holds only the build recipe, not mc itself:

| Path | What it is |
|---|---|
| `scripts/build-mc-macos.sh` | Downloads and builds everything, stages the install tree, runs a smoke test. |
| `patches/mc-relocatable-dirs.patch` | Lets the archive be unpacked anywhere (see below). |
| `.github/workflows/build-macos.yml` | Builds on a macOS runner and publishes the archive. |

Based on [kozyilmaz/mc-on-macos](https://github.com/kozyilmaz/mc-on-macos).

## Using a build

Download `mc-<version>-macos-arm64.tar.gz` from the workflow run's artifacts, or
from the release page for tagged versions, and check it against the `.sha256`
file next to it:

```sh
shasum -a 256 -c mc-4.8.33-macos-arm64.tar.gz.sha256
mkdir -p ~/opt/mc && tar xzf mc-4.8.33-macos-arm64.tar.gz -C ~/opt/mc
~/opt/mc/bin/mc
```

Put `~/opt/mc/bin` on your `PATH` to get `mc`, `mcedit`, `mcview` and `mcdiff`.

The archive can be unpacked anywhere. `bin/mc` and its siblings are symlinks to
one launcher script that finds the archive's own directory and points mc at its
skins, syntax files, help and helper scripts through `MC_DATADIR`,
`MC_SYSCONFDIR`, `MC_LIBEXECDIR` and `MC_BINDIR`. mc itself is compiled with
`/usr/local` as its prefix, and `mc-relocatable-dirs.patch` is what makes those
variables work for the data and helper directories, not just the config one.

## Building

On a Mac with the Xcode command line tools and `curl`:

```sh
sh scripts/build-mc-macos.sh
```

Everything is built under `./tmp`: sources in `tmp/srcdir`, build trees in
`tmp/builddir`, and the finished tree in `tmp/stagedir`. Downloaded tarballs are
reused on later runs. At the end the script starts the real UI on a pty with
`expect` (skipped if `expect` is missing) and quits it again, so a binary that
crashes on startup fails the build.

The script builds its own m4, autoconf, automake, libtool, pkg-config, libffi,
gettext, S-Lang, PCRE2, Ninja, Meson and GLib first, then mc.

Settings, all optional environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `MC_VERSION` | `4.8.33` | mc release to build. |
| `MC_INSTALL_DIRECTORY` | `/usr/local` | Prefix compiled into mc. Install under it, or use the launcher. |
| `PARALLEL_JOBS` | CPU count | Parallelism for `make`. |
| `SLANG_VERSION`, `GLIB_MAJOR_VERSION`/`GLIB_MINOR_VERSION`, `PCRE2_VERSION`, ... | pinned in the script | Versions of the dependencies. |

### CI

`build-macos.yml` runs on every push to `main` and on pull requests, and can be
started by hand with a different `mc_version`. It builds on an Apple Silicon
runner, wraps the staged tree with the launcher, and uploads
`mc-<version>-macos-<arch>.tar.gz` plus its checksum as a workflow artifact.
Pushing a `v*` tag also attaches both files to a GitHub release.
