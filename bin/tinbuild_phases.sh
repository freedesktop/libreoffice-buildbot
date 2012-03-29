#!/usr/bin/env bash
#
#    Copyright (C) 2011 Norbert Thiebaud
#    License: GPLv3
#

pre_autogen()
{
    if [ "${retval}" = "0" ] ; then
        if [ -f $HOME/.tinbuild/autogen/${PROFILE_NAME?}.autogen ] ; then
            if [ ! -f autogen.lastrun -o "$KEEP_AUTOGEN" != "YES" ] ; then
                cp $HOME/.tinbuild/autogen/${PROFILE_NAME?}.autogen autogen.lastrun
            fi
        fi
    fi
}

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

pre_clean()
{
    if [ "${retval}" = "0" ] ; then
        rm -f build_error.log
    fi
}

do_clean()
{
    if [ "${retval}" = "0" ] ; then
        if ! $NICE $WATCHDOG ${MAKE?} clean >tb_${B}_clean.log 2>&1 ; then
            report_log=tb_${B}_clean.log
            report_msgs="cleaning up failed - error is:"
            retval=1
        fi
    fi
}

do_make()
{
    if [ "${retval}" = "0" ] ; then
        if ! $NICE $WATCHDOG ${MAKE?} -s $target >tb_${B}_build.log 2>&1 ; then
            report_log=tb_${B}_build.log
            report_msgs="build failed - error is:"
            retval=1
        fi
    fi
}

do_test()
{
    if [ "${retval}" = "0" ] ; then
        if [ "$DO_TESTS" = "1" ] ; then
            if ! $NICE $WATCHDOG ${MAKE?} check >tb_${B}_tests.log 2>&1 ; then
                report_log=tb_${B}_tests.log
                report_msgs="check failed - error is:"
                retval=1
            fi
	fi
    fi
}

post_make()
{
    if [ "${retval}" != "0" ] ; then
        if [ -f build_error.log ] ; then
            if [ -f $HOME/.tinbuild/config/${PROFILE_NAME?}.false_negatives ] ; then
                grep -F "$(cat $HOME/.tinbuild/config/${PROFILE_NAME?}.false_negatives)" build_error.log && retval="false_negative"
                if [ "${retval?}" == "false_negative" ] ; then
                    log_msgs "False negative detected"
                fi
            fi
        fi
    fi
}

do_push()
{
    local curr_day=

    if [ "${retval}" = "0" ] ; then
        #upload new daily build?
        if [ "$PUSH_NIGHTLIES" = "1" ] ; then
            curr_day=$(date -u '+%Y%j')
            last_day_upload="$(cat "${METADATA_DIR?}/tb_${B}_last-upload-day.txt" 2>/dev/null)"
            if [ -z "$last_day_upload" ] ; then
                last_day_upload=0
            fi
            [ $V ] && echo "curr_day=$curr_day"
            [ $V ] && echo "last_day_upload=$last_day_upload"
            if [ $last_day_upload -lt $curr_day ] ; then
                prepare_upload_manifest
                ${BIN_DIR?}/push_nightlies.sh $push_opts -t "$(cat "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log")" -n "$TINDER_NAME" -l "$BANDWIDTH"
                if [ "$?" == "0" ] ; then
                    echo "$curr_day" > "${METADATA_DIR?}/tb_${B}_last-upload-day.txt"
                fi
            fi
        fi
    fi
    return 0;
}
