#!/usr/bin/env bash
#
#
#    Copyright (C) 2011-2013 Norbert Thiebaud
#    License: GPLv3+
#
# Mac specific override
#

# Do we have timeout? If yes, guard git pull with that - which has a
# tendency to hang forever, when connection is flaky
if which gtimeout > /dev/null 2>&1 ; then
    # MacPorts/self-built - timeout is two hours
    tb_TIMEOUT="$(which gtimeout) 2h"
fi

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

deliver_lo_to_bibisect()
{
    rm -fr ${ARTIFACTDIR?}/opt
    mkdir ${ARTIFACTDIR?}/opt
    cp -fR ${optdir}/LibreOffice.app ${ARTIFACTDIR?}/opt/
}
