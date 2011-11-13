#!/usr/bin/env bash
#
#    Copyright (C) 2011 Norbert Thiebaud
#    License: GPLv3
#

lock_file=/tmp/tinbuid-lockfile

# Do we have timeout? If yes, guard git pull with that - which has a
# tendency to hang forever, when connection is flaky
if which timeout > /dev/null 2>&1 ; then
	# std coreutils - timeout is two hours
	timeout="`which timeout` 2h"
fi

do_flock()
{
    if [ "$LOCK" = "1" ] ; then
        flock $@
    fi
}

epoch_from_utc()
{
local utc="$@"

    date -u '+%s' -d "$utc UTC"
}

epoch_to_utc()
{
    date -u -d @${1}
}

print_date()
{
    date -u '+%Y-%m-%d %H:%M:%S'
}

log_msgs()
{
    echo "[$(print_date) $TINDER_BRANCH]" "$@"
}

prepare_upload_manifest()
{
    local manifest_file="build_info.txt"

    echo "Build Info" > $manifest_file

    echo "tinderbox: administrator: ${OWNER?}" >> $manifest_file
    echo "tinderbox: buildname: ${TINDER_NAME?}" >> $manifest_file
    echo "tinderbox: tree: ${TINDER_BRANCH?}" >> $manifest_file
    echo "tinderbox: pull time $(cat tb_${B}_current-git-timestamp.log)" >> $manifest_file
    echo "tinderbox: git sha1s"  >> $manifest_file
    cat tb_${B}_current-git-heads.log  >> $manifest_file
    echo ""  >> $manifest_file
    echo "tinderbox: autogen log"  >> $manifest_file
    cat tb_${B}_autogen.log  >> $manifest_file

}

get_commits_since_last_good()
{
    local mode=$1
    local head=
    local repo=
    local sha=

    if [ -f tb_${B}_last-success-git-heads.txt ] ; then
	for head in $(cat tb_${B}_last-success-git-heads.txt) ; do
	    repo=$(echo ${head} | cut -d : -f 1)
	    sha=$(echo ${head} | cut -d : -f 2)
	    (
		if [ "${repo?}" != "bootstrap" -a "${repo}" != "core" ] ; then
		    cd clone/${repo?}
		fi
                if [ "${mode?}" = "people" ] ; then
		    git log '--pretty=tformat:%ce' ${sha?}..HEAD
                else
                    echo "==== ${repo} ===="
                    git log '--pretty=tformat:%h  %s' ${sha?}..HEAD | sed 's/^/  /'
                fi
	    )
	done
    fi
}

send_mail_msg()
{
local to="$1"
local subject="$2"
local headers="$3"
local bcc="$4"
local log="$5"
local quiet="-q"
local smtp_auth=""

    if [ -n "${SMTPUSER}" ] ; then
        smtp_auth="-xu ${SMTPUSER?} -xp ${SMTPPW?}"
    fi

    log_msgs "send mail to ${to?} with subject \"${subject?}\""
    [ $V ] && quiet=""
    if [ -n "${log}" ] ; then
	${BIN_DIR?}/sendEmail $quiet -f "$OWNER" -s "${SMTPHOST?}" $smtp_auth -t "${to?}" -bcc "${bcc?}" -u "${subject?}" -o "message-header=${headers?}" -a "${log?}"
    elif [ -n "${headers?}" ] ; then
	${BIN_DIR?}/sendEmail $quiet -f "$OWNER" -s "${SMTPHOST?}" $smtp_auth -t "${to?}" -bcc "${bcc?}" -u "${subject?}" -o "message-header=${headers?}"
    else
	${BIN_DIR?}/sendEmail $quiet -f "$OWNER" -s "${SMTPHOST?}" $smtp_auth -t "${to?}" -bcc "${bcc?}" -u "${subject?}"
    fi
}

report_to_tinderbox()
{
    if [ -z "$SEND_MAIL" -o -z "$TINDER_NAME" ] ; then
        return 0
    fi

    local start_date="$1"
    local status="$2"
    local log="$3"
    local start_line=
    local xtinder="X-Tinder: cookie"
    local subject="tinderbox build start notification"
    local gzlog=
    local message_content=

    start_line="tinderbox: starttime: $(epoch_from_utc ${start_date})"
    message_content="
tinderbox: administrator: ${OWNER?}
tinderbox: buildname: ${TINDER_NAME?}
tinderbox: tree: ${TINDER_BRANCH?}
$start_line
tinderbox: timenow: `date -u '+%s'`
tinderbox: errorparser: unix
tinderbox: status: ${status?}
tinderbox: END
"

    if [ "$log" = "yes" ] ; then
       gzlog="tinder.log.gz"
       ( echo "$message_content" ; cat tb_${B}_current-git-timestamp.log  tb_${B}_current-git-heads.log tb_${B}_autogen.log tb_${B}_clean.log tb_${B}_build.log tb_${B}_smoketest.log tb_${B}_install.log 2>/dev/null ) | gzip -c > "${gzlog}"
       xtinder="X-Tinder: gzookie"
       subject="tinderbox gzipped logfile"
    fi

    if [ "$SEND_MAIL" = "debug" ] ; then
        echo "$message_content" | send_mail_msg "${OWNER}" "${subject?}" "${xtinder?}" '' "${gzlog}"
    elif [ "$SEND_MAIL" = "author" ] ; then
        echo "$message_content" | send_mail_msg "${OWNER}" "${subject?}" "${xtinder?}" '' "${gzlog}"
        if [ -n "${BRANCH_AUTHOR}" ] ; then
            echo "$message_content" | send_mail_msg "${BRANCH_AUTHOR}" "${subject?}" "${xtinder?}" '' "${gzlog}"
        fi
    else
        echo "$message_content" | send_mail_msg "tinderbox@gimli.documentfoundation.org" "${subject?}" "${xtinder?}" '' "${gzlog}"
    fi
}


report_error ()
{
    local_to_mail=
    local tinder1=
    local tinder2=
    local error_kind="$1"
    shift
    local rough_time="$1"
    shift

    local last_success=$(cat tb_${B}_last-success-git-timestamp.txt)
    to_mail=
    if [ "$SEND_MAIL" = "owner" -o "$SEND_MAIL" = "debug" -o "$SEND_MAIL" = "author" ] ; then
        to_mail="${OWNER?}"
    else
        if [ "$SEND_MAIL" = "all" ] ; then
	    case "$error_kind" in
		owner) to_mail="${OWNER?}"
		    message="box broken" ;;
		*)
                    if [ -z "$last_success" ] ; then
			          # we need at least one successful build to
                      # be reliable
			to_mail="${OWNER?}"
		    else
			to_mail="$(get_committers)"
		    fi
		    message="last success: ${last_success?}" ;;
	    esac
        fi
    fi
    if [ -n "$to_mail" ] ; then
	echo "$*" 1>&2
	echo "Last success: ${last_success}" 1>&2
	tinder1="`echo \"Full log available at http://tinderbox.libreoffice.org/$TINDER_BRANCH/status.html\"`"
	tinder2="`echo \"Box name: ${TINDER_NAME?}\"`"

	cat <<EOF | send_mail_msg "$to_mail" "Tinderbox failure, $message" "" "${OWNER?}" ""
Hi folks,

One of you broke the build of LibreOffice with your commit :-(
Please commit and push a fix ASAP!

${tinder1}

Tinderbox info:

  ${tinder2}
  Machine: `uname -a`
  Configured with: `cat autogen.lastrun`

Commits since the last success:

$(get_commits_since_last_good commits)

The error is:

$*
EOF
    else
	echo "$*" 1>&2
    fi
}


collect_current_heads()
{
    ./g -1 rev-parse HEAD > tb_${B}_current-git-heads.log
    print_date > tb_${B}_current-git-timestamp.log
}

get_committers()
{
    echo "get_commiter: $(get_commits_since_last_good people)" 1>&2
    get_commits_since_last_good people | sort | uniq | tr '\n' ','
}

rotate_logs()
{
    if [ "$retval" = "0" ] ; then
	cp -f tb_${B}_current-git-heads.log tb_${B}_last-success-git-heads.txt 2>/dev/null
	cp -f tb_${B}_current-git-timestamp.log tb_${B}_last-success-git-timestamp.txt 2>/dev/null
    fi
    for f in tb_${B}*.log ; do
	mv -f ${f} prev-${f} 2>/dev/null
    done
}

wait_for_commits()
{
    local show_once=1
    local err_msgs=

    while true; do
        [ $V ] && echo "pulling from the repos"
	err_msgs="$( $timeout ./g pull -r 2>&1)"
	if [ "$?" -ne "0" ] ; then
	    report_error owner "$(date)" $(printf "git repo broken - error is:\n\n$err_msgs")
	else
	    collect_current_heads

	    if [ "$(cat tb_${B}_current-git-heads.log)" != "$(cat prev-tb_${B}_current-git-heads.log)" ] ; then
		log_msgs "Repo updated, going to build."
		break
            fi
	    if [ "$show_once" = "1" ] ; then
		log_msgs "Waiting until there are changes in the repo..."
		show_once=0
	    fi
        fi
	sleep 60
    done
}

m="$(uname)"

if [ -f "${BIN_DIR?}/tinbuild_internals_${m}.sh" ] ; then
    source "${BIN_DIR?}/tinbuild_internals_${m}.sh"
fi
unset m

## Determine how GNU make(1) is called on the system
for _g in make gmake gnumake; do
    $_g --version 2> /dev/null | grep -q GNU
    if test $? -eq 0;  then
	MAKE=$_g
	break
    fi
done

source ${BIN_DIR?}/tinbuild_phases.sh


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

    build_status="build_failed"
    retval=0
    for p in autogen clean make test push ; do
        [ $V ] && echo "phase $p"
	phase $p
    done
    if [ "$retval" = "0" ] ; then
        build_status="success"
        if [ -n "${last_checkout_date}" ] ; then
            report_to_tinderbox "$last_checkout_date" "success" "yes"
        else
            log_msgs "Successfuly primed branch '$TINDER_BRANCH'."
        fi
    elif [ "$retval" = "false_negative" ] ; then
        report_to_tinderbox "${last_checkout_date?}" "fold" "no"
        log_msgs "False negative build, skip reporting"
    else
        if [ -n "${last_checkout_date}" ] ; then
	    report_error committer "$last_checkout_date" `printf "${report_msgs?}:\n\n"` "$(cat build_error.log | grep -C10 "^[^[]")
======
$(tail -n50 ${report_log?} | grep -A25 'internal build errors' | grep 'ERROR:' )"
	    report_to_tinderbox "${last_checkout_date?}" "build_failed" "yes"
        else
            log_msgs "Failed to primed branch '$TINDER_BRANCH'. see build_error.log"
        fi
    fi
}
