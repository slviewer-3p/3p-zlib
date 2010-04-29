#!/bin/sh

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

ZLIB_VERSION="1.2.3"
ZLIB_SOURCE_DIR="zlib-$ZLIB_VERSION"
ZLIB_ARCHIVE="$ZLIB_SOURCE_DIR.tar.gz"
ZLIB_URL="http://downloads.sourceforge.net/project/libpng/zlib/$ZLIB_VERSION/$ZLIB_ARCHIVE"
ZLIB_MD5="debc62758716a169df9f62e6ab2bc634" # for zlib-1.2.3.tar.gz

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

fetch_archive "$ZLIB_URL" "$ZLIB_ARCHIVE" "$ZLIB_MD5"
extract "$ZLIB_ARCHIVE"

top="$(pwd)"
cd "$ZLIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            build_sln "contrib/vstudio/vc8/zlibvc.sln" "Debug|Win32"
            build_sln "contrib/vstudio/vc8/zlibvc.sln" "Release|Win32"
            mkdir -p stage/lib/debug
            mkdir -p stage/lib/release
            cp "contrib/vstudio/vc8/x86/ZlibStatDebug/zlibstat.lib" \
                "stage/lib/debug/zlibd.lib"
            cp "contrib/vstudio/vc8/x86/ZlibStatRelease/zlibstat.lib" \
                "stage/lib/release/zlib.lib"
            mkdir -p "stage/include/zlib"
            cp {zlib.h,zconf.h} "stage/include/zlib"
        ;;
        *)
            ./configure --prefix="$(pwd)/stage"
            make
            make install
        ;;
    esac
    mkdir -p stage/LICENSES
    tail -n 31 README > stage/LICENSES/zlib.txt
cd "$top"

pass

