#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

ZLIB_SOURCE_DIR="zlib"

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

top="$(pwd)"
stage="$top"/stage

VERSION_HEADER_FILE="$ZLIB_SOURCE_DIR/zlib.h"
VERSION_MACRO="ZLIB_VERSION"

build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

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

            # populate version_file
            cl /DVERSION_HEADER_FILE="\"$VERSION_HEADER_FILE\"" \
               /DVERSION_MACRO="$VERSION_MACRO" \
               /Fo"$(cygpath -w "$stage/version.obj")" \
               /Fe"$(cygpath -w "$stage/version.exe")" \
               "$(cygpath -w "$top/version.c")"
            "$stage/version.exe" > "$stage/VERSION.txt"
            rm "$stage"/version.{obj,exe}

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp -a "contrib/vstudio/vc10/x86/ZlibStatDebug/zlibstat.lib" \
                "$stage/lib/debug/zlibd.lib"
            cp -a "contrib/vstudio/vc10/x86/ZlibStatRelease/zlibstat.lib" \
                "$stage/lib/release/zlib.lib"
            mkdir -p "$stage/include/zlib"
            cp -a zlib.h zconf.h "$stage/include/zlib"

            # minizip
            pushd contrib/minizip
                nmake /f Makefile.Linden.Win32.mak DEBUG=1
                cp -a minizip.lib "$stage"/lib/debug/
                nmake /f Makefile.Linden.Win32.mak DEBUG=1 clean

                nmake /f Makefile.Linden.Win32.mak
                cp -a minizip.lib "$stage"/lib/release/
                nmake /f Makefile.Linden.Win32.mak clean
            popd
        ;;

        "darwin")
            # Select SDK with full path.  This shouldn't have much effect on this
            # build but adding to establish a consistent pattern.
            sdk=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.9.sdk/
            cc_opts="${TARGET_OPTS:--arch i386 -iwithsysroot $sdk -mmacosx-version-min=10.7} -gdwarf-2 -fPIC -DPIC"
            ld_opts="-Wl,-install_name,\"${install_name}\" -Wl,-headerpad_max_install_names"
            export CC=clang

            # populate version_file
            cc -DVERSION_HEADER_FILE="\"$VERSION_HEADER_FILE\"" \
               -DVERSION_MACRO="$VERSION_MACRO" \
               -o "$stage/version" "$top/version.c"
            "$stage/version" > "$stage/VERSION.txt"
            rm "$stage/version"

            # Install name for dylibs based on major version number
            install_name="@executable_path/../Resources/libz.1.dylib"

            # Debug first
            CFLAGS="$cc_opts -O0" \
                LDFLAGS="$ld_opts" \
                sh -x ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
            make
            make install
            cp -a "$top"/libz_darwin_debug.exp "$stage"/lib/debug/libz_darwin.exp

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

            # minizip
            pushd contrib/minizip
                CFLAGS="$cc_opts -O0" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/debug/
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            make distclean

            # Now release
            CFLAGS="$cc_opts -O3" \
                LDFLAGS="$ld_opts" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install
            cp -a "$top"/libz_darwin_release.exp "$stage"/lib/release/libz_darwin.exp

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                mkdir -p ../Resources
                ln -sf "${stage}"/lib/release/*.dylib ../Resources

                make test

                rm -rf ../Resources
            fi

            # minizip
            pushd contrib/minizip
                CFLAGS="$cc_opts -O3" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/release/
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            make distclean
        ;;            
            
        "linux")
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

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

            # populate version_file
            cc -DVERSION_HEADER_FILE="\"$VERSION_HEADER_FILE\"" \
               -DVERSION_MACRO="$VERSION_MACRO" \
               -o "$stage/version" "$top/version.c"
            "$stage/version" > "$stage/VERSION.txt"
            rm "$stage/version"

            # Debug first
            CFLAGS="$opts -O0 -g -fPIC -DPIC" CXXFLAGS="$opts -O0 -g -fPIC -DPIC" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            # minizip
            pushd contrib/minizip
                CFLAGS="$opts -O0 -g -fPIC -DPIC" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/debug/
                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

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

            # minizip
            pushd contrib/minizip
                CFLAGS="$opts -O3 -fPIC -DPIC" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/release/
                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            # clean the build artifacts
            make distclean
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    tail -n 31 README > "$stage/LICENSES/zlib.txt"
    pushd contrib/minizip
        mkdir -p "$stage"/include/minizip/
        cp -a ioapi.h zip.h unzip.h "$stage"/include/minizip/
        tail -n 22 MiniZip64_info.txt > "$stage/LICENSES/minizip.txt"
    popd
popd

mkdir -p "$stage"/docs/zlib/
cp -a README.Linden "$stage"/docs/zlib/

pass

