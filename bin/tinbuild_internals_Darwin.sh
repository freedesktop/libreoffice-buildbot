#!/usr/bin/env bash
#
#
#    Copyright (C) 2011-2012 Norbert Thiebaud
#    License: GPLv3+

# Do we have timeout? If yes, guard git pull with that - which has a
# tendency to hang forever, when connection is flaky
if which gtimeout > /dev/null 2>&1 ; then
    # MacPorts/self-built - timeout is two hours
    timeout="`which gtimeout` 2h"
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
