#!/usr/bin/env bash
# -*- tab-width : 4; indent-tabs-mode : nil -*-

lcov-make-check_do_make()
{
    if [ "${R}" = "0" ] ; then
        # we for MAKE_RESTARTS=1 because 1/ we know that Makefile is up to date
        # and 2/ the 'restart' mechanism in make is messed-up by the fact that we trap SIGINT
        if ! ${TB_NICE} ${TB_WATCHDOG} ${MAKE?} MAKE_RESTARTS=1 gb_GCOV=YES build-nocheck > "tb_${P?}_build-nocheck.log" 2>&1 ; then
            tb_REPORT_LOG="tb_${P?}_build-nocheck.log"
            tb_REPORT_MSGS="build failed - error is:"
            [ $V ] && echo "make failed :"
            [ $V ] && cat tb_${P?}_build-nocheck.log
            R=1
        else
            if ! ${TB_LCOV_REPORT} -b -C "$TB_BUILD_DIR" -s "$TB_GIT_DIR" -t "$TB_LCOV_TRACEFILE_DIR" -d "$TB_LCOV_TEST_NAME" >> "tb_${P?}_build-nocheck.log" 2>&1 ; then
                tb_REPORT_LOG="tb_${P}_build-nocheck.log"
                tb_REPORT_MSGS="lcov before failed - error is:"
                [ $V ] && echo "lcov before failed :"
                [ $V ] && cat tb_${P?}_build-nocheck.log
                R=1
            else
                if ! ${TB_NICE} ${TB_WATCHDOG} ${MAKE?} MAKE_RESTARTS=1 gb_GCOV=YES check >> "tb_${P?}_build-nocheck.log" 2>&1 ; then
                    tb_REPORT_LOG="tb_${P?}_build-nocheck.log"
                    tb_REPORT_MSGS="make check failed - error is:"
                    [ $V ] && echo "make failed :"
                    [ $V ] && cat tb_${P?}_build-nocheck.log
                    R=1
                else
                    if ! ${TB_LCOV_REPORT} -a -s "$TB_GIT_DIR" -C "$TB_BUILD_DIR" -t "$TB_LCOV_TRACEFILE_DIR" -d "$TB_LCOV_TEST_NAME" -w "$TB_LCOV_HTML_DIR" >> "tb_${P?}_build-nocheck.log" 2>&1 ; then
                        tb_REPORT_LOG="tb_${P?}_build-nocheck.log"
                        tb_REPORT_MSGS="lcov after  failed - error is:"
                        [ $V ] && echo "lcov after failed :"
                        [ $V ] && cat tb_${P?}_build-nocheck.log
                        R=1
                    fi
                fi
            fi
        fi
    fi
}

do_make()
{
   lcov-make-check_do_make
}

lcov-make-check_do_autogen()
{
local current_timestamp=
 
    if [ "${R}" = "0" ] ; then
        export EXTRA_BUILDID=
        if [ "${TB_TYPE?}" = "tb" ] ; then
            current_timestamp=$(sed -e "s/ /_/" "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log")
            export EXTRA_BUILDID="TinderBox: ${TB_NAME?}, Branch:${TB_BRANCH?}, Time: $current_timestamp"
        fi
        "${TB_GIT_DIR?}/autogen.sh" > "tb_${P?}_autogen.log" 2>&1
        if [ "$?" != "0" ] ; then
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
    lcov-make-check_do_autogen
}

lcov-make-check_do_test()
{
    return 0
}

do_test()
{
    lcov-make-check_do_test
}

lcov-make-check_do_push()
{
        return 0
}

do_push()
{
    lcov-make-check_do_push
}

