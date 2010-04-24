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

# *HACK - bash doesn't know how to pass real pathnames to native windows python
if [ "$OSTYPE" == 'cygwin' ] ; then
	autobuild="$(cygpath -u $autobuild.cmd)"
fi

# load autbuild provided shell functions and variables
set +x
eval "$("$autobuild" source_environment)"
set -x

"$autobuild" build

"$autobuild" package

ZLIB_INSTALLABLE_PACKAGE_FILENAME="$(ls -1 zlib-$ZLIB_VERSION-$AUTOBUILD_PLATFORM-$(date +%Y%m%d)*.tar.bz2)"
#"$autobuild" upload "$ZLIB_INSTALLABLE_PACKAGE_FILENAME"
upload_item installer "$ZLIB_INSTALLABLE_PACKAGE_FILENAME" application/octet-stream

ZLIB_INSTALLABLE_PACKAGE_MD5="$(calc_md5 "$ZLIB_INSTALLABLE_PACKAGE_FILENAME")"
echo "{'md5':'$ZLIB_INSTALLABLE_PACKAGE_MD5', 'url':'http://s3.amazonaws.com/viewer-source-downloads/install_pkgs/$ZLIB_INSTALLABLE_PACKAGE_FILENAME'}" > "output.json"

upload_item docs "output.json" text/plain

pass

