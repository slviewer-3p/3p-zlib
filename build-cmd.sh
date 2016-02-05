#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for logs.
set -x
# make errors fatal
set -e

ZLIB_SOURCE_DIR="zlib"

top="$(pwd)"
stage="$top"/stage

# load autobuild provided shell functions and variables
case "$AUTOBUILD_PLATFORM" in
	windows*)
		AUTOBUILD="$(cygpath -u "$AUTOBUILD")"
	;;
esac
eval "$("$AUTOBUILD" source_environment)"

# For this library, like most third-party libraries, we only care about
# Release mode, so source build-variables up front.
build_variables="../build-variables/convenience"
[ -r "$build_variables" ] || \
fail "Please clone https://bitbucket.org/lindenlab/build-variables beside this repo."
source "$build_variables" Release

VERSION_HEADER_FILE="$ZLIB_SOURCE_DIR/zlib.h"
version=$(sed -n -E 's/#define ZLIB_VERSION "([0-9.]+)"/\1/p' "${VERSION_HEADER_FILE}")
build=${AUTOBUILD_BUILD_ID:=0}
echo "${version}.${build}" > "${stage}/VERSION.txt"

pushd "$ZLIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            # This invokes cmake only to convert zconf.h.cmakein to zconf.h.
            # Without this step, multiple compiles fail for lack of zconf.h.
            cmake -G "Visual Studio 12" . -DASM686=NO -DAMD64=NO

            build_sln "contrib/vstudio/vc12/zlibvc.sln" "ReleaseWithoutAsm|$AUTOBUILD_WIN_VSPLATFORM" "zlibstat"

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then bitdir=x86
            else bitdir=x64
            fi

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                build_sln "contrib/vstudio/vc12/zlibvc.sln" "ReleaseWithoutAsm|$AUTOBUILD_WIN_VSPLATFORM" "testzlib"
                ./contrib/vstudio/vc12/$bitdir/TestZlibReleaseWithoutAsm/testzlib.exe README
            fi

            # mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp -a "contrib/vstudio/vc12/$bitdir/ZlibStatReleaseWithoutAsm/zlibstat.lib" \
                "$stage/lib/release/zlib.lib"
            mkdir -p "$stage/include/zlib"
            cp -a zlib.h zconf.h "$stage/include/zlib"
        ;;

        # ------------------------- darwin, darwin64 -------------------------
        darwin*)
            case "$AUTOBUILD_ADDRSIZE" in
                32)
                    cc_arch="i386"
                    cfg_sw=
                    ;;
                64)
                    cc_arch="x86_64"
                    cfg_sw="--64"
                    ;;
            esac

            # Install name for dylibs based on major version number
            install_name="@executable_path/../Resources/libz.1.dylib"

            cc_opts="${TARGET_OPTS:--arch $cc_arch $LL_BUILD}"
            ld_opts="-Wl,-install_name,\"${install_name}\" -Wl,-headerpad_max_install_names"
            export CC=clang

##          # Debug first
##          CFLAGS="$cc_opts -O0" \
##              LDFLAGS="$ld_opts" \
##              sh -x ./configure $cfg_sw --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
##          make
##          make install
##          cp -a "$top"/libz_darwin_debug.exp "$stage"/lib/debug/libz_darwin.exp
##
##          # conditionally run unit tests
##          if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
##              # Build a Resources directory as a peer to the test executable directory
##              # and fill it with symlinks to the dylibs.  This replicates the target
##              # environment of the viewer.
##              mkdir -p ../Resources
##              ln -sf "${stage}/lib/debug"/*.dylib ../Resources
##
##              make test
##
##              # And wipe it
##              rm -rf ../Resources
##          fi
##
##          # minizip
##          pushd contrib/minizip
##              CFLAGS="$cc_opts -O0" make -f Makefile.Linden all
##              cp -a libminizip.a "$stage"/lib/debug/
##              if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
##                  make -f Makefile.Linden test
##              fi
##              make -f Makefile.Linden clean
##          popd
##
##          make distclean

            # Now release
            CFLAGS="$cc_opts" \
            LDFLAGS="$ld_opts" \
                ./configure $cfg_sw --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install
            cp -a "$top"/libz_darwin_release.exp "$stage"/lib/release/libz_darwin.exp

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # Build a Resources directory as a peer to the test executable directory
                # and fill it with symlinks to the dylibs.  This replicates the target
                # environment of the viewer.
                mkdir -p ../Resources
                ln -sf "${stage}"/lib/release/*.dylib ../Resources

                make test

                # And wipe it
                rm -rf ../Resources
            fi

##          # minizip
##          pushd contrib/minizip
##              CFLAGS="$cc_opts -O3" make -f Makefile.Linden all
##              cp -a libminizip.a "$stage"/lib/release/
##              if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
##                  make -f Makefile.Linden test
##              fi
##              make -f Makefile.Linden clean
##          popd

            make distclean
        ;;            

        # -------------------------- linux, linux64 --------------------------
        linux*)
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
            unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Prefer gcc-4.6 if available.
            if [[ -x /usr/bin/gcc-4.6 && -x /usr/bin/g++-4.6 ]]; then
                export CC=/usr/bin/gcc-4.6
                export CXX=/usr/bin/g++-4.6
            fi

            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD}"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

##          # Debug first
##          CFLAGS="$opts" CXXFLAGS="$opts" \
##              ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
##          make
##          make install
##
##          # conditionally run unit tests
##          if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
##              make test
##          fi
##
##          # minizip
##          pushd contrib/minizip
##              CFLAGS="$opts -O0 -g -fPIC -DPIC" make -f Makefile.Linden all
##              cp -a libminizip.a "$stage"/lib/debug/
##              # conditionally run unit tests
##              if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
##                  make -f Makefile.Linden test
##              fi
##              make -f Makefile.Linden clean
##          popd
##
##          # clean the build artifacts
##          make distclean

            # Release last
            CFLAGS="$opts" CXXFLAGS="$opts" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

##          # minizip
##          pushd contrib/minizip
##              CFLAGS="$opts -O3 -fPIC -DPIC" make -f Makefile.Linden all
##              cp -a libminizip.a "$stage"/lib/release/
##              # conditionally run unit tests
##              if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
##                  make -f Makefile.Linden test
##              fi
##              make -f Makefile.Linden clean
##          popd

            # clean the build artifacts
            make distclean
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    # The copyright info for zlib is the tail end of its README file. Tempting
    # though it is to write something like 'tail -n 31 README', that will
    # quietly fail if the length of the copyright notice ever changes.
    # Instead, look for the section header that sets off that passage and copy
    # from there through EOF. (Given that END is recognized by awk, you might
    # reasonably expect '/pattern/,END' to work, but no: END can only be used
    # to fire an action past EOF. Have to simulate by using another regexp we
    # hope will NOT match.)
    awk '/^Copyright notice:$/,/@%rest%@/' README > "$stage/LICENSES/zlib.txt"
    # In case the section header changes, ensure that zlib.txt is non-empty.
    # (With -e in effect, a raw test command has the force of an assert.)
    # Exiting here means we failed to match the copyright section header.
    # Check the README and adjust the awk regexp accordingly.
    [ -s "$stage/LICENSES/zlib.txt" ]
##  pushd contrib/minizip
##      mkdir -p "$stage"/include/minizip/
##      cp -a ioapi.h zip.h unzip.h "$stage"/include/minizip/
##      tail -n 22 MiniZip64_info.txt > "$stage/LICENSES/minizip.txt"
##  popd
popd

mkdir -p "$stage"/docs/zlib/
cp -a README.Linden "$stage"/docs/zlib/

pass
