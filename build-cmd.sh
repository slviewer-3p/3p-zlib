#!/bin/sh

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

if [ "$OSTYPE" = "cygwin" ] ; then
    # *HACK windows env vars are crap -brad
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

fetch_archive "$FOO_URL" "$FOO_ARCHIVE" "$FOO_MD5"
extract "$FOO_ARCHIVE"

top="$(pwd)"
cd "$FOO_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            build_sln "foo.sln" "Debug|Win32"
            build_sln "foo.sln" "Release|Win32"
            mkdir -p stage/lib/{debug,release}
            cp "Debug/foo.lib" \
                "stage/lib/debug/foo.lib"
            cp "Release/foo.lib" \
                "stage/lib/release/foo.lib"
            mkdir -p "stage/include/foo"
            cp foo.h "stage/include/foo"
        ;;
        *)
            ./configure --prefix="$(pwd)/stage"
            make
            make install
        ;;
    esac
    mkdir -p stage/LICENSES
    cp COPYING stage/LICENSES/foo.txt
cd "$top"

pass

