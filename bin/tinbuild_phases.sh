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
    if [ "${retval}" = "0" ] ; then
        if ! $NICE $WATCHDOG ${MAKE?} -s $target >tb_${B}_build.log 2>&1 ; then
            report_log=tb_${B}_build.log
            report_msgs="build failed - error is:"
            retval=1
        else
	    # if we want to populate bibisect we need to 'install'
	    if [ $PUSH_TO_BIBISECT_REPO != "0" ] ; then
		if ! $NICE $WATCHDOG ${MAKE?} -s install-tb >>tb_${B}_build.log 2>&1 ; then
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
    else
	if [ $PUSH_TO_BIBISECT_REPO != "0" -a -n "${optdir}" ] ; then
	    deliver_to_bibisect
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
    if [ -n "${last_checkout_date}" ] ; then
        report_to_tinderbox "${last_checkout_date?}" "building" "no"
    fi

    previous_build_status="${build_status}"
    build_status="build_failed"
    retval=0
    retry_count=3
    if [ "$DO_NOT_CLEAN" = "1" ] ; then
        phase_list="autogen make test push"
    else
        phase_list="autogen clean make test push"
    fi
    while [ "$phase_list" != "" ] ; do
        for p in $phase_list ; do
            [ $V ] && echo "phase $p"
	        phase $p
        done
        phase_list=
        if [ "$retval" = "0" ] ; then
            build_status="success"
            if [ -n "${last_checkout_date}" ] ; then
                report_to_tinderbox "$last_checkout_date" "success" "yes"
		if [ "${previous_build_status}" = "build_failed" ]; then
		    report_fixed committer "$last_checkout_date"
		fi
            else
                log_msgs "Successfully primed branch '$TINDER_BRANCH'."
            fi
        elif [ "$retval" = "false_negative" ] ; then
            report_to_tinderbox "${last_checkout_date?}" "fold" "no"
            log_msgs "False negative build, skip reporting"
            # false negative foes not need a full clea build, let's just redo make and after
            phase_list="make test push"
            retry_count=$((retry_count - 1))
            if [ "$retry_count" = "0" ] ; then
                phase_list=
            fi
        else
            if [ -n "${last_checkout_date}" ] ; then
                printf "${report_msgs?}:\n\n" > report_error.log
                echo "======" >> report_error.log
                if [ "${report_log?}" == "tb_${B}_build.log" ] ; then
                    cat build_error.log | grep -C10 "^[^[]" >> report_error.log
                    tail -n50 ${report_log?} | grep -A25 'internal build errors' | grep 'ERROR:' >> report_error.log
                else
                    cat ${report_log?} >> report_error.log
                fi
                report_error committer "$last_checkout_date" report_error.log
	        report_to_tinderbox "${last_checkout_date?}" "build_failed" "yes"
            else
                log_msgs "Failed to primed branch '$TINDER_BRANCH'. see build_error.log"
            fi
        fi
    done
}
