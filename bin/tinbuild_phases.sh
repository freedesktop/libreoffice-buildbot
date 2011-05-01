#!/usr/bin/env bash

do_autogen()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ./autogen.sh ${DISTRO_CONFIG:+ --with-distro=${DISTRO_CONFIG}} >tb_autogen.log 2>&1 ; then
			report_error committer "$last_checkout_date" `printf "autogen.sh / configure failed - error is:\n\n"` "$(cat tb_autogen.log)"
			retval=1
		fi
	fi
}

do_clean()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ${MAKE?} clean >tb_clean.log 2>&1 ; then
			report_error committer "$last_checkout_date" `printf "cleaning up failed - error is:\n\n"` "$(tail -n100 tb_clean.log)"
			retval=1
		fi
	fi
}

do_make()
{
	if [ "${retval}" = "0" ] ; then
		if ! $NICE ${MAKE?} >tb_build.log 2>&1 ; then
			report_error committer "$last_checkout_date" `printf "building failed - error is:\n\n"` "$(tail -n100 tb_build.log)"
			retval=1
		fi
	fi
}





