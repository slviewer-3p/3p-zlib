#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

ZLIB_VERSION="1.2.5"
ZLIB_SOURCE_DIR="zlib-$ZLIB_VERSION"

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

# load autobuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

stage="$(pwd)/stage"
pushd "$ZLIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        "windows")
            load_vsvars
            
            pushd contrib/masmx86
                ./bld_ml32.bat
            popd
            
            build_sln "contrib/vstudio/vc10/zlibvc.sln" "Debug|Win32" "zlibstat"
            build_sln "contrib/vstudio/vc10/zlibvc.sln" "Release|Win32" "zlibstat"
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp "contrib/vstudio/vc10/x86/ZlibStatDebug/zlibstat.lib" \
                "$stage/lib/debug/zlibd.lib"
            cp "contrib/vstudio/vc10/x86/ZlibStatRelease/zlibstat.lib" \
                "$stage/lib/release/zlib.lib"
            mkdir -p "$stage/include/zlib"
            cp {zlib.h,zconf.h} "$stage/include/zlib"
        ;;
        "darwin")
            opts='-arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.5.sdk -mmacosx-version-min=10.5'
            CFLAGS="$opts -O3" LDFLAGS="$opts" ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install

			make distclean
			
			CFLAGS="$opts -O0 -g" LDFLAGS="$opts" ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
            make
            make install
			
        ;;            
			
        "linux")
			# do release build
            CFLAGS="-m32 -O3" CXXFLAGS="-m32 -O3" ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install

			# clean the build artifacts
			make distclean

			# do debug build
            CFLAGS="-m32 -O0 -gstabs+" CXXFLAGS="-m32 -O0 -gstabs+" ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
            make
            make install
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    tail -n 31 README > "$stage/LICENSES/zlib.txt"
popd

pass

