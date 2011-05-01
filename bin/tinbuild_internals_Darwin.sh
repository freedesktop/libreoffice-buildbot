#!/usr/bin/env bash

epoch_from_utc()
{
    date -juf '%Y-%m-%d %H:%M:%S' "${1}" '+%s'
}

epoch_to_utc()
{
	date -juf '%s' $1
}

print_date()
{
	date -u '+%Y-%m-%d %H:%M:%S'
}
