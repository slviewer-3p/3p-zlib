#!/bin/sh

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

fetch_archive "$FOO_URL" "$FOO_ARCHIVE" "$FOO_MD5"
extract "$FOO_ARCHIVE"

top="$(pwd)"
cd "$ZLIB_SOURCE_DIR"
    ./configure
    make
cd "$top"

"$autobuild" package

upload_item "installable" "$FOO_INSTALLABLE_PACKAGE_FILENAME"

pass

