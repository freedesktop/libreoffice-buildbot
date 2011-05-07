#!/usr/bin/env bash

do_flock()
{
    if [ "$LOCK" = "1" ] ; then
        if [ ${bin_dir?}/flock ] ; then
            [ $VERBOSE -gt 0 ] && echo "locking..."
            ${bin_dir?}/flock $@
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
