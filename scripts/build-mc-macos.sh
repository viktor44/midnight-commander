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
unpack "gettext-$GETTEXT_VERSION.tar.gz"
./configure --prefix="$path_to_install" --enable-static --disable-shared \
  --disable-java --disable-csharp --disable-c++ --without-emacs \
  --disable-openmp --with-included-libxml --with-included-libunistring
make -j "$PARALLEL_JOBS"
make install

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
MC_FRAMEWORKS="-framework Foundation -framework CoreFoundation -framework AppKit -framework Carbon"
MC_GLIB_LIBS="$path_to_install/lib/libglib-2.0.a $path_to_install/lib/libintl.a -liconv -lm $MC_FRAMEWORKS -lpcre2-8"
CFLAGS="-I$path_to_install/include" \
LDFLAGS="-L$path_to_install/lib" \
./configure --prefix="$MC_INSTALL_DIRECTORY" \
  --disable-nls \
  --with-libintl-prefix="$path_to_install" \
  --with-pcre2="$path_to_install" \
  --enable-static \
  --with-screen=ncurses \
  --with-glib-static=yes \
  GLIB_LIBDIR="$path_to_install/lib" \
  GLIB_LIBS="$MC_GLIB_LIBS" \
  GMODULE_LIBS="$path_to_install/lib/libgmodule-2.0.a" \
  LIBS="$path_to_install/lib/libgmodule-2.0.a $path_to_install/lib/libintl.a $MC_GLIB_LIBS"
make -j "$PARALLEL_JOBS"

#
# Stage the install tree so CI can archive it without touching the runner's
# system directories. DESTDIR keeps the compiled-in --prefix paths intact.
#
rm -rf "$path_to_stage"
make install DESTDIR="$path_to_stage"

echo
echo "Built mc $MC_VERSION, staged under $path_to_stage$MC_INSTALL_DIRECTORY"
"$path_to_stage$MC_INSTALL_DIRECTORY/bin/mc" --version
otool -L "$path_to_stage$MC_INSTALL_DIRECTORY/bin/mc"
