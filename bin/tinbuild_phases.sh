#!/usr/bin/env bash
#
#    Copyright (C) 2011 Norbert Thiebaud
#    License: GPLv3
#

do_autogen()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ./autogen.sh ${DISTRO_CONFIG:+ --with-distro=${DISTRO_CONFIG}} >tb_${B}_autogen.log 2>&1 ; then
            report_log=tb_${B}_autogen.log
            report_msgs="autogen/configure failed - error is:"
			retval=1
		fi
	fi
}

do_clean()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ${MAKE?} clean >tb_${B}_clean.log 2>&1 ; then
            report_log=tb_${B}_clean.log
            report_msgs="cleaning up failed - error is:"
			retval=1
		fi
	fi
}

do_make()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ${MAKE?} >tb_${B}_build.log 2>&1 ; then
            report_log=tb_${B}_build.log
            report_msgs="build failed - error is:"
			retval=1
		fi
	fi
}

do_push()
{
	local curr_day=

	#upload new daily build?
	if [ "$PUSH_NIGHTLIES" = "1" ] ; then
		curr_day=$(date -u '+%Y%j')
		last_day_upload="$(cat tb_${B}_last-upload-day.txt 2>/dev/null)"
        if [ -z "$last_day_upload" ] ; then
            last_day_upload=0
        fi
        echo "curr_day=$curr_day"
        echo "last_day_upload=$last_day_upload"
		if [ $last_day_upload -lt $curr_day ] ; then
			${bin_dir?}/push_nightlies.sh -a -t "$(cat tb_${B}_current-git-timestamp.log)" -n "$TINDER_NAME" -l "$BANDWIDTH"
			if [ "$?" == "0" ] ; then
				echo "$curr_day" > tb_${B}_last-upload-day.txt
			fi
		fi
	fi
    return 0;
}





