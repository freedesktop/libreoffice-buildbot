#!/usr/bin/env bash
#
#    Copyright (C) 2011-2012 Norbert Thiebaud, Robinson Tryon
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
    optdir=""
    current_timestamp=$(sed -e "s/ /_/" "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log")
    EXTRA_BUILDID="TinderBox: $TINDER_NAME, Branch:${B}, Time: $current_timestamp"
    if [ "${retval}" = "0" ] ; then
        if ! $NICE $WATCHDOG ${MAKE?} EXTRA_BUILDID="$EXTRA_BUILDID" -s $target >tb_${B}_build.log 2>&1 ; then
            report_log=tb_${B}_build.log
            report_msgs="build failed - error is:"
            retval=1
        else
	    # if we want to populate bibisect we need to 'install'
	    if [ "${build_type}" = "tb" -a $PUSH_TO_BIBISECT_REPO != "0" ] ; then
		if ! $NICE $WATCHDOG ${MAKE?} EXTRA_BUILDID="$EXTRA_BUILDID" -s install-tb >>tb_${B}_build.log 2>&1 ; then
		    report_log=tb_${B}_build.log
		    report_msgs="build failed - error is:"
		    retval=1
		else
		    optdir="$(find_dev_install_location)"
		fi
	    fi
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
    [ $V ] && echo "Push: phase starting"

    if [ "${retval}" != "0" ] ; then
        return 0;
    fi

    # Push nightly build if needed
    push_nightly

    # Push bibisect to remote bibisect if needed
    push_bibisect

    return 0;
}

tb_call()
{
    [ $V ] && declare -F "$1" > /dev/null && echo "call $1"
    declare -F "$1" > /dev/null && $1
}

phase()
{
    local f=${1}
    for x in {pre_,do_,post_}${f} ; do
	tb_call ${x}
    done
}


do_build()
{
    build_type="${1:-tb}"

    [ $V ] && echo "do_build ($build_type) PHASE_LIST=$PHASE_LIST"

    for p in ${PHASE_LIST?} ; do
        [ $V ] && echo "phase $p"
	phase $p
    done
    PHASE_LIST=

}
