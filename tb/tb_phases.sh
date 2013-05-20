#!/usr/bin/env bash
# -*- tab-width : 4; indent-tabs-mode : nil -*-
#
#    Copyright (C) 2011-2013 Norbert Thiebaud
#    License: GPLv3
#

canonical_pre_autogen()
{
    if [ "${R}" = "0" ] ; then
        if [ ! -f autogen.lastrun -o "${tb_KEEP_AUTOGEN}" != "YES" ] ; then
            copy_autogen_config
        fi
    fi
}

pre_autogen()
{
    canonical_pre_autogen
}

canonical_do_autogen()
{
    if [ "${R}" = "0" ] ; then
        if ! ${TB_NICE} ${TB_GIT_DIR?}/autogen.sh > "tb_${P?}_autogen.log" 2>&1 ; then
            tb_REPORT_LOG=tb_${P?}_autogen.log
            tb_REPORT_MSGS="autogen/configure failed - error is:"
            [ $V ] && echo "autogen failed"
            [ $V ] && cat tb_${P?}_autogen.log
            R=1
        fi
    fi
}

do_autogen()
{
    canonical_do_autogen
}

canoncial_post_autogen()
{
    return
}

canonical_pre_clean()
{
    if [ "${R}" = "0" ] ; then
        true # log files to clean, if any
    fi
}

pre_clean()
{
    canonical_pre_clean
}

canonical_do_clean()
{
    if [ "${R}" = "0" ] ; then
        if ! ${TB_NICE} ${TB_WATCHDOG} ${MAKE?} MAKE_RESTARTS=1 -sr clean > "tb_${P?}_clean.log" 2>&1 ; then
            tb_REPORT_LOG="tb_${P?}_clean.log"
            tb_REPORT_MSGS="cleaning up failed - error is:"
            R=1
        fi
    fi
}

do_clean()
{
    canonical_do_clean
}

canonical_post_clean()
{
    return
}

canonical_do_make()
{
local current_timestamp=
local optdir=""
local extra_buildid=""

    tb_OPT_DIR=""
    if [ "${TB_TYPE?}" = "tb" ] ; then
        current_timestamp=$(sed -e "s/ /_/" "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log")
        extra_buildid="TinderBox: ${TB_NAME?}, Branch:${TB_BRANCH?}, Time: $current_timestamp"
    fi
    if [ "${R}" = "0" ] ; then
        export EXTRA_BUILDID="$extra_buildid"
        # we for MAKE_RESTARTS=1 because 1/ we know thta Makefile is up to date
        # and 2/ the 'restart' mechanism in make is messed-up by the fact that we trap SIGINT
        if ! ${TB_NICE} ${TB_WATCHDOG} ${MAKE?} MAKE_RESTARTS=1  -sr > "tb_${P?}_build.log" 2>&1 ; then
            tb_REPORT_LOG="tb_${P?}_build.log"
            tb_REPORT_MSGS="build failed - error is:"
            [ $V ] && echo "make failed :"
            [ $V ] && cat tb_${P?}_build.log
            R=1
        else
            # if we want to populate bibisect we need to 'install'
            if [ "${TB_TYPE?}" = "tb" -a ${TB_BIBISECT} != "0" ] ; then
                if ! ${TB_NICE} ${TB_WATCHDOG}  ${MAKE?} MAKE_RESTARTS=1 -sr install-tb >>"tb_${P?}_build.log" 2>&1 ; then
                    tb_REPORT_LOG="tb_${P}_build.log"
                    tb_REPORT_MSGS="build failed - error is:"
                    R=1
                else
                    tb_OPT_DIR="$(find_dev_install_location)"
                fi
            fi
        fi
    fi
}

do_make()
{
    canonical_do_make
}

canonical_post_make()
{
    if [ "${TB_TYPE?}" = "tb" ] ; then
        if [ "${R}" != "0" ] ; then
            if [ -f "${tb_REPORT_LOG?}" ] ; then
                if [ -f "${tb_CONFIG_DIR?}/profiles/${P?}false_negatives" ] ; then
                    grep -F "$(cat "${tb_CONFIG_DIR?}/profiles/${P?}/false_negatives")" "${tb_REPORT_LOG?}" && R="2"
                    if [ "${R?}" == "2" ] ; then
                        log_msgs "False negative detected"
                    fi
                fi
            fi
        fi
    fi
}

post_make()
{
    canonical_post_make
}

canonical_pre_test()
{
    return
}

canonical_do_test()
{
    if [ "${R}" = "0" ] ; then
        if [ "${TB_DO_TESTS}" = "1" ] ; then
            if ! ${TB_NICE} ${TB_WATCHDOG}  ${MAKE?} MAKE_RESTARTS=1 -sr check > "tb_${P?}_tests.log" 2>&1 ; then
                tb_REPORT_LOG="tb_${P?}_tests.log"
                tb_REPORT_MSGS="check failed - error is:"
                R=1
            fi
        fi
    fi
}

do_test()
{
    canonical_do_test
}

canonical_post_test()
{
    return
}

canonical_pre_push()
{
    return
}

canonical_do_push()
{
    [ $V ] && echo "Push: phase starting"

    if [ "${R}" != "0" ] ; then
        return 0;
    fi

    if [ "${TB_TYPE?}" = "tb" ] ; then
        # Push nightly build if needed
        if [ "$TB_PUSH_NIGHTLIES" = "1" ] ; then
            push_nightly
        fi
        # Push bibisect to remote bibisect if needed
        if [ "$TB_BIBISECT" = "1" ] ; then
            push_bibisect
        fi
    fi
    return 0;
}

do_push()
{
    canonical_do_push
}

canonical_post_push()
{
    return
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
    local phases="$@"
    local p
    [ $V ] && echo "do_build (${TB_TYPE?}) phase_list=${phases?}"

    for p in ${phases?} ; do
        [ $V ] && echo "phase $p"
        phase $p
    done

}
