#!/bin/sh

# turn on verbose debugging output for parabuild logs.
set -x

ZLIB_VERSION="1.2.3"
ZLIB_SOURCE_DIR="zlib-$ZLIB_VERSION"
ZLIB_ARCHIVE="$ZLIB_SOURCE_DIR.tar.gz"
ZLIB_URL="http://downloads.sourceforge.net/project/libpng/zlib/$ZLIB_VERSION/$ZLIB_ARCHIVE"
ZLIB_MD5="debc62758716a169df9f62e6ab2bc634" # for zlib-1.2.3.tar.gz

if [ -z "$autobuild" ] ; then 
    autobuild="$(which autobuild)"
fi

# *NOTE: temporary workaround until autobuild is installed on the build farm
autobuild_installed ()
{
    local hardcoded_rev="parabuild-bootstrap"
    local bootstrap_url="http://pdp47.lindenlab.com/cgi-bin/hgwebdir.cgi/brad/autobuild/archive/$hardcoded_rev.tar.bz2"

    # hg.lindenlab.com is kind of hosed right now.
    #local hardcoded_rev="c8062b08a710"
    #local boostrap_url="http://hg.lindenlab.com/brad/autobuild-trunk/get/$hardcoded_rev.bz2"

    if [ -z "$autobuild" ] || [ ! -x "$autobuild" ] ; then
        echo "failed to find executable autobuild $autobuild" >&2

        echo "fetching autobuild rev $hardcoded_rev from $bootstrap_url"
        curl "$bootstrap_url" | tar -xj
        autobuild="$(pwd)/autobuild-$hardcoded_rev/bin/autobuild"
        if [ ! -x "$autobuild" ] ; then
            echo "failed to bootstrap autobuild!"
            return 1
        fi
    fi
    echo "located autobuild tool: '$autobuild'"
}

# at this point we should know where everything is, so make errors fatal
set -e

# this fail function will either be provided by the parabuild buildscripts or
# not exist.  either way it's a fatal error
autobuild_installed || fail

# load autbuild provided shell functions and variables
eval "$("$autobuild" source_environment)"

fetch_archive "$ZLIB_URL" "$ZLIB_ARCHIVE" "$ZLIB_MD5"
extract "$ZLIB_ARCHIVE"

top="$(pwd)"
cd "$ZLIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            build_sln "contrib/vstudio/vc8/zlibvc.sln" "Debug|Win32"
            build_sln "contrib/vstudio/vc8/zlibvc.sln" "Release|Win32"
            mkdir -p stage/lib/{debug,release}
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

#"$autobuild" package

#upload_item "installable" "$ZLIB_INSTALLABLE_PACKAGE_FILENAME"

pass

