#!/usr/bin/env bash

do_autogen()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ./autogen.sh ${DISTRO_CONFIG:+ --with-distro=${DISTRO_CONFIG}} >tb_autogen.log 2>&1 ; then
            report_log=tb_autogen.log
            report_msgs="autogen/configure failed - error is:"
			retval=1
		fi
	fi
}

do_clean()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ${MAKE?} clean >tb_clean.log 2>&1 ; then
            report_log=tb_clean.log
            report_msgs="cleaning up failed - error is:"
			retval=1
		fi
	fi
}

do_make()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ${MAKE?} >tb_build.log 2>&1 ; then
            report_log=tb_build.log
            report_msgs="build failed - error is:"
			retval=1
		fi
	fi
}





