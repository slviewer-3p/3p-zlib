#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

ZLIB_VERSION="1.2.8"
ZLIB_SOURCE_DIR="zlib"

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

            # Okay, this invokes cmake then doesn't use the products.  Why?
            cmake .

            pushd contrib/masmx86
                cmd.exe /C bld_ml32.bat
            popd
            
            build_sln "contrib/vstudio/vc10/zlibvc.sln" "Debug|Win32" "zlibstat"
            build_sln "contrib/vstudio/vc10/zlibvc.sln" "Release|Win32" "zlibstat"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                build_sln "contrib/vstudio/vc10/zlibvc.sln" "Debug|Win32" "testzlib"
                ./contrib/vstudio/vc10/x86/TestZlibDebug/testzlib.exe README

                build_sln "contrib/vstudio/vc10/zlibvc.sln" "Release|Win32" "testzlib"
                ./contrib/vstudio/vc10/x86/TestZlibRelease/testzlib.exe README
            fi

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp -a "contrib/vstudio/vc10/x86/ZlibStatDebug/zlibstat.lib" \
                "$stage/lib/debug/zlibd.lib"
            cp -a "contrib/vstudio/vc10/x86/ZlibStatRelease/zlibstat.lib" \
                "$stage/lib/release/zlib.lib"
            mkdir -p "$stage/include/zlib"
            cp -a zlib.h zconf.h "$stage/include/zlib"
        ;;

        "darwin")
            opts="${TARGET_OPTS:--arch i386 -iwithsysroot /Developer/SDKs/MacOSX10.7.sdk -mmacosx-version-min=10.6}"
            # Install name for dylibs based on major version number
            install_name="@executable_path/../Resources/libz.1.dylib"

            # Debug first
            CFLAGS="$opts -O0 -gdwarf-2 -fPIC -DPIC" LDFLAGS="-install_name \"${install_name}\"" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
            make
            make install
            
            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # Build a Resources directory as a peer to the test executable directory
                # and fill it with symlinks to the dylibs.  This replicates the target
                # environment of the viewer.
                mkdir -p ../Resources
                ln -sf "${stage}/lib/debug"/*.dylib ../Resources

                make test

                # And wipe it
                rm -rf ../Resources
            fi

            make distclean

            # Now release
            CFLAGS="$opts -O3 -gdwarf-2 -fPIC -DPIC" LDFLAGS="-install_name \"${install_name}\"" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                mkdir -p ../Resources
                ln -sf "${stage}"/lib/release/*.dylib ../Resources

                make test

                rm -rf ../Resources
            fi
        ;;            
            
        "linux")
            # Prefer gcc-4.6 if available.
            if [[ -x /usr/bin/gcc-4.6 && -x /usr/bin/g++-4.6 ]]; then
                export CC=/usr/bin/gcc-4.6
                export CXX=/usr/bin/g++-4.6
            fi

            # Default target to 32-bit
            opts="${TARGET_OPTS:--m32}"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Debug first
            CFLAGS="$opts -O0 -g -fPIC -DPIC" CXXFLAGS="$opts -O0 -g -fPIC -DPIC" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            # clean the build artifacts
            make distclean

            # Release last
            CFLAGS="$opts -O3 -fPIC -DPIC" CXXFLAGS="$opts -O3 -fPIC -DPIC" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    tail -n 31 README > "$stage/LICENSES/zlib.txt"
popd

pass

