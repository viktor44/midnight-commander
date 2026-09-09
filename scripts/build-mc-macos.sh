#!/bin/sh
#
# Build a self-contained (statically linked dependencies) Midnight Commander
# for macOS from upstream source tarballs.
#
# Based on https://github.com/kozyilmaz/mc-on-macos/blob/main/mc.sh
#
# Everything is built into ./tmp so the runner needs no Homebrew packages.
#
set -eu

# Where the resulting mc expects to find its data files at runtime.
MC_INSTALL_DIRECTORY="${MC_INSTALL_DIRECTORY:-/usr/local}"

path_to_build="$PWD/tmp/builddir"
path_to_source="$PWD/tmp/srcdir"
path_to_install="$PWD/tmp/installdir"
path_to_stage="$PWD/tmp/stagedir"
mkdir -p "$path_to_build" "$path_to_source" "$path_to_install" "$path_to_stage"

# Absolute, because the build cds into each unpacked source tree.
path_to_patches=$(cd "$(dirname "$0")/../patches" && pwd)

export PATH="$path_to_install/bin:$PATH"

#
# Package versions
#
M4_VERSION="${M4_VERSION:-1.4.20}"
AUTOCONF_VERSION="${AUTOCONF_VERSION:-2.72}"
AUTOMAKE_VERSION="${AUTOMAKE_VERSION:-1.18.1}"
LIBTOOL_VERSION="${LIBTOOL_VERSION:-2.5.4}"
PKGCONFIG_VERSION="${PKGCONFIG_VERSION:-0.29.2}"
LIBFFI_VERSION="${LIBFFI_VERSION:-3.5.2}"
GETTEXT_VERSION="${GETTEXT_VERSION:-0.26}"
PCRE2_VERSION="${PCRE2_VERSION:-10.48}"
NCURSES_VERSION="${NCURSES_VERSION:-6.6}"
NINJA_VERSION="${NINJA_VERSION:-1.13.1}"
MESON_VERSION="${MESON_VERSION:-1.8.4}"
GLIB_MAJOR_VERSION="${GLIB_MAJOR_VERSION:-2.85}"
GLIB_MINOR_VERSION="${GLIB_MINOR_VERSION:-4}"
MC_VERSION="${MC_VERSION:-4.8.33}"

PARALLEL_JOBS="${PARALLEL_JOBS:-$(sysctl -n hw.ncpu)}"

GLIB_VERSION="$GLIB_MAJOR_VERSION.$GLIB_MINOR_VERSION"

#
# Download helper: fetch $1 into $path_to_source unless already present, trying
# each of the remaining arguments in turn. Mirrors go down; ftpmirror.gnu.org
# in particular hands CI runners 502s often enough to break the build.
#
fetch() {
  name="$1"
  shift
  [ -f "$path_to_source/$name" ] && return 0
  for url in "$@"; do
    echo "Download $name from $url"
    if curl -fL --retry 3 --connect-timeout 30 "$url" -o "$path_to_source/$name.part"; then
      mv "$path_to_source/$name.part" "$path_to_source/$name"
      return 0
    fi
    rm -f "$path_to_source/$name.part"
    echo "  mirror failed, trying next"
  done
  echo "ERROR: could not download $name" >&2
  return 1
}

#
# GNU packages: $1 = tarball name, $2 = project directory on the GNU servers.
#
gnu_fetch() {
  fetch "$1" \
    "https://ftp.gnu.org/gnu/$2/$1" \
    "https://mirrors.kernel.org/gnu/$2/$1" \
    "https://ftpmirror.gnu.org/$2/$1"
}

gnu_fetch "m4-$M4_VERSION.tar.gz" m4
gnu_fetch "autoconf-$AUTOCONF_VERSION.tar.gz" autoconf
gnu_fetch "automake-$AUTOMAKE_VERSION.tar.gz" automake
gnu_fetch "libtool-$LIBTOOL_VERSION.tar.gz" libtool
gnu_fetch "gettext-$GETTEXT_VERSION.tar.gz" gettext
gnu_fetch "ncurses-$NCURSES_VERSION.tar.gz" ncurses
fetch "pkg-config-$PKGCONFIG_VERSION.tar.gz" \
  "https://pkgconfig.freedesktop.org/releases/pkg-config-$PKGCONFIG_VERSION.tar.gz" \
  "https://distfiles.macports.org/pkgconfig/pkg-config-$PKGCONFIG_VERSION.tar.gz"
fetch "libffi-$LIBFFI_VERSION.tar.gz" \
  "https://github.com/libffi/libffi/releases/download/v$LIBFFI_VERSION/libffi-$LIBFFI_VERSION.tar.gz"
fetch "pcre2-$PCRE2_VERSION.tar.gz" \
  "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VERSION/pcre2-$PCRE2_VERSION.tar.gz"
fetch "ninja-$NINJA_VERSION.tar.gz" \
  "https://github.com/ninja-build/ninja/archive/refs/tags/v$NINJA_VERSION.tar.gz"
fetch "meson-$MESON_VERSION.tar.gz" \
  "https://github.com/mesonbuild/meson/releases/download/$MESON_VERSION/meson-$MESON_VERSION.tar.gz"
fetch "glib-$GLIB_VERSION.tar.xz" \
  "https://download.gnome.org/sources/glib/$GLIB_MAJOR_VERSION/glib-$GLIB_VERSION.tar.xz" \
  "https://ftp.gnome.org/pub/gnome/sources/glib/$GLIB_MAJOR_VERSION/glib-$GLIB_VERSION.tar.xz"
fetch "mc-$MC_VERSION.tar.bz2" \
  "http://ftp.midnight-commander.org/mc-$MC_VERSION.tar.bz2" \
  "https://ftp.osuosl.org/pub/midnightcommander/mc-$MC_VERSION.tar.bz2"
echo "Download complete!"

#
# Unpack helper: extract $1 into the build dir, replacing any previous copy,
# and leave the shell inside the unpacked directory.
#
unpack() {
  rm -rf "$path_to_build/${1%%.tar.*}"
  tar xf "$path_to_source/$1" -C "$path_to_build"
  cd "$path_to_build/${1%%.tar.*}"
}

#
# M4
#
unpack "m4-$M4_VERSION.tar.gz"
./configure --prefix="$path_to_install"
make -j "$PARALLEL_JOBS"
make install

#
# Autoconf
#
unpack "autoconf-$AUTOCONF_VERSION.tar.gz"
./configure --prefix="$path_to_install"
make -j "$PARALLEL_JOBS"
make install

#
# Automake
#
unpack "automake-$AUTOMAKE_VERSION.tar.gz"
./configure --prefix="$path_to_install"
make -j "$PARALLEL_JOBS"
make install

#
# Libtool
#
unpack "libtool-$LIBTOOL_VERSION.tar.gz"
./configure --prefix="$path_to_install" --enable-static --disable-shared
make -j "$PARALLEL_JOBS"
make install

#
# Pkg-config
#
unpack "pkg-config-$PKGCONFIG_VERSION.tar.gz"
CFLAGS="-Wno-int-conversion" ./configure --prefix="$path_to_install" \
  --with-internal-glib --disable-host-tool \
  --with-system-include-path="$path_to_install/include:/usr/include" \
  --with-system-library-path="$path_to_install/lib:/usr/lib:/lib" \
  LIBS="-Wl,-framework -Wl,CoreFoundation -Wl,-framework -Wl,Cocoa"
make -j "$PARALLEL_JOBS"
make install

#
# LibFFI
#
unpack "libffi-$LIBFFI_VERSION.tar.gz"
./configure --prefix="$path_to_install" --enable-static --disable-shared
make -j "$PARALLEL_JOBS"
make install

#
# Gettext (libintl, needed statically by both glib and mc)
#
# Only gettext-runtime is built: gettext-tools drags in libtextstyle, which
# does not compile with current clang (incompatible-function-pointer-types is
# an error now), and mc needs nothing from it.
#
unpack "gettext-$GETTEXT_VERSION.tar.gz"
cd gettext-runtime
./configure --prefix="$path_to_install" --enable-static --disable-shared \
  --disable-java --disable-csharp --disable-libasprintf
make -j "$PARALLEL_JOBS"
make install

#
# Ncurses (wide-character build)
#
# macOS ships ncurses.h from 6.0 but only /usr/lib/libncurses.5.4.dylib, so a
# binary compiled against the SDK headers writes 6.x-shaped structs into a 5.4
# library and segfaults on the first curses call. There is also no ncursesw at
# all, which loses UTF-8. Build our own and link it statically.
#
# Deliberately no --with-termlib: it splits the terminfo half out into
# libtinfow, and mc's configure probes for has_colors with a bare -lncursesw,
# which then fails to link.
#
unpack "ncurses-$NCURSES_VERSION.tar.gz"
./configure --prefix="$path_to_install" \
  --without-shared --with-normal --without-debug --without-ada --without-tests \
  --without-manpages --without-cxx-binding \
  --enable-widec --enable-ext-colors --enable-ext-mouse \
  --enable-pc-files --with-pkg-config-libdir="$path_to_install/lib/pkgconfig" \
  --with-default-terminfo-dir="$MC_INSTALL_DIRECTORY/share/terminfo" \
  --with-terminfo-dirs="$MC_INSTALL_DIRECTORY/share/terminfo:/usr/share/terminfo:/opt/homebrew/share/terminfo" \
  --enable-symlinks --disable-stripping
make -j "$PARALLEL_JOBS"
# The compiled-in default terminfo directory doubles as the install target, and
# it has to name where mc will finally live so a /usr/local install just works.
# Override TICDIR at install time so the database actually lands in our own
# prefix rather than in the runner's unwritable /usr/local.
make install TICDIR="$path_to_install/share/terminfo"

# Compiling terminfo entries into the library (--with-fallbacks) would need a
# working tic before ncurses is built, and the tic macOS ships is 5.4: it dies
# on the modern terminfo.src with "error writing .../scrt". Keep the database
# on disk instead - install put it under share/terminfo, built by the tic from
# this very tree - and let the packaged launcher point TERMINFO_DIRS at it.

#
# PCRE2 (mc's search engine)
#
unpack "pcre2-$PCRE2_VERSION.tar.gz"
./configure --prefix="$path_to_install" --enable-static --disable-shared \
  --enable-pcre2-8 --enable-unicode
make -j "$PARALLEL_JOBS"
make install

#
# Ninja
#
unpack "ninja-$NINJA_VERSION.tar.gz"
./configure.py --bootstrap
cp -a ninja "$path_to_install/bin"

#
# Meson
#
unpack "meson-$MESON_VERSION.tar.gz"
./packaging/create_zipapp.py --outfile meson.pyz --interpreter '/usr/bin/env python3'
cp -a meson.pyz "$path_to_install/bin"

#
# Glib
#
unpack "glib-$GLIB_VERSION.tar.xz"
CFLAGS="-I$path_to_install/include" \
CXXFLAGS="-I$path_to_install/include" \
LDFLAGS="-L$path_to_install/lib" \
meson.pyz setup --prefix="$path_to_install" --default-library=static \
  -D nls=disabled -D glib_debug=disabled -D tests=false -D sysprof=disabled _build
meson.pyz compile -C _build
meson.pyz install -C _build

#
# Midnight Commander
#
unpack "mc-$MC_VERSION.tar.bz2"

# Without this, only the config directory follows MC_DATADIR, so a relocated
# tree finds its skins but not its syntax files, help or keymaps. See the
# patch header for the details.
patch -p1 < "$path_to_patches/mc-datadir-relocatable.patch"

MC_FRAMEWORKS="-framework Foundation -framework CoreFoundation -framework AppKit -framework Carbon"
MC_GLIB_LIBS="$path_to_install/lib/libglib-2.0.a $path_to_install/lib/libintl.a -liconv -lm $MC_FRAMEWORKS -lpcre2-8"
# Our static ncursesw, not the 5.4 stub in /usr/lib.
MC_CURSES_LIBS="$path_to_install/lib/libncursesw.a"
CFLAGS="-I$path_to_install/include" \
LDFLAGS="-L$path_to_install/lib" \
./configure --prefix="$MC_INSTALL_DIRECTORY" \
  --disable-nls \
  --with-libintl-prefix="$path_to_install" \
  --with-pcre2="$path_to_install" \
  --enable-static \
  --with-screen=ncursesw \
  --with-glib-static=yes \
  GLIB_LIBDIR="$path_to_install/lib" \
  GLIB_LIBS="$MC_GLIB_LIBS" \
  GMODULE_LIBS="$path_to_install/lib/libgmodule-2.0.a" \
  LIBS="$path_to_install/lib/libgmodule-2.0.a $path_to_install/lib/libintl.a $MC_GLIB_LIBS $MC_CURSES_LIBS"
make -j "$PARALLEL_JOBS"

#
# Stage the install tree so CI can archive it without touching the runner's
# system directories. DESTDIR keeps the compiled-in --prefix paths intact.
#
rm -rf "$path_to_stage"
make install DESTDIR="$path_to_stage"

# Ship the terminfo database we compiled, so the binary is not at the mercy of
# whatever entries the target machine happens to have.
cp -R "$path_to_install/share/terminfo" "$path_to_stage$MC_INSTALL_DIRECTORY/share/terminfo"

echo
echo "Built mc $MC_VERSION, staged under $path_to_stage$MC_INSTALL_DIRECTORY"
# mc bails out with "The TERM environment variable is unset!" before it gets
# as far as printing --version, and CI runners have no TERM.
TERM="${TERM:-xterm}" "$path_to_stage$MC_INSTALL_DIRECTORY/bin/mc" --version
otool -L "$path_to_stage$MC_INSTALL_DIRECTORY/bin/mc"

# --version never touches curses, so it would not have caught the 5.4/6.x
# header-vs-library mismatch that used to segfault on startup. Drive the real
# UI for a moment instead: start mc on a pty and quit it with F10.
echo
if ! command -v expect >/dev/null 2>&1; then
  echo "Smoke test: skipped, expect is not installed"
  exit 0
fi
echo "Smoke test: starting the full-screen UI"
TERM=xterm \
MC_DATADIR="$path_to_stage$MC_INSTALL_DIRECTORY/share/mc" \
MC_SYSCONFDIR="$path_to_stage$MC_INSTALL_DIRECTORY/etc/mc" \
TERMINFO_DIRS="$path_to_stage$MC_INSTALL_DIRECTORY/share/terminfo:/usr/share/terminfo" \
  expect -c "
    set timeout 30
    spawn $path_to_stage$MC_INSTALL_DIRECTORY/bin/mc --nomouse
    expect {
      -re {Left|File|Command} { }
      timeout { puts \"\nUI did not appear\"; exit 1 }
      eof     { puts \"\nmc exited or crashed at startup\"; exit 1 }
    }
    # F10, then confirm the quit dialog if this build asks.
    send \"\033\[21~\"
    expect {
      -re {[Yy]es} { send \"\r\" ; expect eof }
      eof          { }
      timeout      { puts \"\nmc did not quit\"; exit 1 }
    }
    catch wait result
    set status [lindex \$result 3]
    if { [lindex \$result 2] != 0 || \$status > 1 } {
      puts \"\nmc terminated abnormally: \$result\"
      exit 1
    }
  " > /dev/null
echo "UI started and exited cleanly"
