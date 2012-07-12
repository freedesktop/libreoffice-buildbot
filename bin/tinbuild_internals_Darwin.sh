#!/usr/bin/env bash
#
#
#    Copyright (c) 2012 Robinson Tryon <qubit@runcibility.com>
#    License: GPLv3+

# Do we have timeout? If yes, guard git pull with that - which has a
# tendency to hang forever, when connection is flaky
if which gtimeout > /dev/null 2>&1 ; then
	# MacPorts/self-built - timeout is two hours
	timeout="`which gtimeout` 2h"
fi

do_flock()
{
    if [ "$LOCK" = "1" ] ; then
        if [ ${BIN_DIR?}/flock ] ; then
            [ $V ] && echo "locking..."
            ${BIN_DIR?}/flock $@
        else
            echo "no flock implementation, please build it from buildbot/flock or use -e" 2>&1
            exit 1;
        fi
    fi
}

epoch_from_utc()
{
    date -juf '%Y-%m-%d %H:%M:%S' "$1 $2" '+%s'
}

epoch_to_utc()
{
    date -juf '%s' $1
}

print_date()
{
    date -u '+%Y-%m-%d %H:%M:%S'
}

# Copy the build into the bibisect repository (given the opt/
# directory and the bibisect repository's directory)
copy_build_into_bibisect_repository()
{
    echo "Bibisect: WARNING: Prototype code for Darwin/OSX. Run at your own risk!"

    [ $V ] && echo "Bibisect: copy_build_into_bibisect_repository()"
    # If OPTDIR or ARTIFACTDIR are not set, error-out.
    if [ -z $OPTDIR ] ||
       [ -z $ARTIFACTDIR ] ; then
        report_log=tb_${B}_bibisect.log
        report_msgs="Bibisect: OPTDIR '$OPTDIR' and ARTIFACTDIR '$ARTIFACTDIR' must both be non-null."
        retval=1
        return;
    fi

    DMG_PATH=`find ${OPTDIR} -name \*.dmg -type f`

    if [ -n "`echo ${DMG_PATH} | grep ' '`" ]; then
        echo "Bibisect: WARNING: Multiple dmg files: '${DMG_PATH}'"
    fi

    # Get the "attach point" from hdiutil through various contortions.
    MOUNTPOINT=`hdiutil attach ${DMG_PATH} | tail -n1 | cut -f3`
    # Nerfing the copy step until someone can confirm that MOUNTPOINT
    # actually contains something vaguely reasonable on darwin/OSX,
    # and confirms the structure of what's inside the dmg created by
    # the build process.
    echo cp -R ${MOUNTPOINT} ${ARTIFACTDIR}/opt
    hdiutil detach ${MOUNTPOINT}
}
