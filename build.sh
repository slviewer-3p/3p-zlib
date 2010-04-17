#!/bin/sh -x

autobuild="$(which autobuild)"

autobuild_installed ()
{
    if [ -z "$autobuild" ] || [ ! -x "$autobuild" ] ; then
        echo "looking for autobuild in ../autobuild/bin"
        autobuild="$(dirname $0)/../autobuild/bin/autobuild"
        if [ -z "$autobuild" ] || [ ! -x "$autobuild" ] ; then
            echo "failed to find executable autobuild $autobuild" >&2
            # *TODO - potentially fetch and use autobuild in sandbox here
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

pushd "$FOO_SOURCE_DIR"
    ./configure
    make
popd

"$autobuild" package

upload_item "installable" "$FOO_INSTALLABLE_PACKAGE_FILENAME"

pass

