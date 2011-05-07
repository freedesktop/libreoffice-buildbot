#!/usr/bin/env bash

lock_file=/tmp/tinbuid-lockfile

do_lock()
{
    if [ "$LOCK" = "1" ] ; then
        flock $@
    fi
}

epoch_from_utc()
{
local utc="$1"

    date '+%s' -d "$utc"
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

send_mail_msg()
{
local to="$1"
local subject="$2"
local headers="$3"
local bcc="$4"
local log=""

    log_msgs sendEmail -q -f "$OWNER" -s "${SMTPHOST?}" -xu "${SMTPUSER?}" -xp "${SMTPPW?}" -t "${to?}" -bcc "${bcc?}" -u "${subject?}" -o "message-header=${headers?}" -a "${log?}"
#    if [ -n "$5" ] ; then
#		log="-a $5"
#		${bin_path}/sendEmail -q -f "$OWNER" -s "${SMTPHOST?}" -xu "${SMTPUSER?}" -xp "${SMTPPW?}" -t "${to?}" -bcc "${bcc?}" -u "${subject?}" -o "message-header=${headers?}" -a "${log?}"
#	else
#		${bin_path}/sendEmail -q -f "$OWNER" -s "${SMTPHOST?}" -xu "${SMTPUSER?}" -xp "${SMTPPW?}" -t "${to?}" -bcc "${bcc?}" -u "${subject?}" -o "message-header=${headers?}"
#    fi
}

report_to_tinderbox()
{
	if test "$SEND_MAIL" -ne 1 -o -z "$TINDER_NAME" ; then
		return 0
	fi

	local start_time="$1"
	local status="$2"
	local log="$3"
	local start_line=
	local xtinder="X-Tinder: cookie"
	local subject="tinderbox build start notification"
	local gzlog=
	local message_content=

	start_line="tinderbox: starttime: $(epoch_from_utc \"${start_time}\")"
	message_content="
tinderbox: administrator: ${OWNER?}
tinderbox: buildname: ${TINDER_NAME?}
tinderbox: tree: ${TINDER_BRANCH?}
$start_line
tinderbox: timenow: `date '+%s'`
tinderbox: errorparser: unix
tinderbox: status: ${STATUS?}
tinderbox: END
"

	if [ "$log" = "yes" ] ; then
		gzlog="tinder.log.gz"
		( echo "$MESSAGE" ; cat autogen.log clean.log build.log smoketest.log install.log 2>/dev/null ) | gzip -c > "$GZLOG"
		xtinder="X-Tinder: gzookie"
		subject="tinderbox gzipped logfile"
	fi

	echo "$message_content" | send_mail_msg "tinderbox@gimli.documentfoundation.org" "${subject?}" "${xtinder?}" "" "${gzlog}"
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

	to_mail=
	if test "$SEND_MAIL" -eq 1; then
		case "$error_kind" in
			owner) to_mail="${OWNER?}"
			       message="box broken" ;;
			*)     if test -z "$last_success" ; then
			          # we need at least one successful build to
                      # be reliable
			          to_mail="${OWNER?}"
			       else
			          to_mail="$(get_committers)"
			       fi
			       message="last success: $rough_time" ;;
		esac
	fi

	echo "$*" 1>&2
	echo "Last success: $rough_time" 1>&2
	if test -n "$to_mail" ; then
		if test "$SEND_MAIL" -eq 1 -a -n "$TINDER_NAME" ; then
			tinder1="`echo \"Full log available at http://tinderbox.libreoffice.org/$TINDER_BRANCH/status.html\"`"
			tinder2="`echo \"Box name: ${TINDER_NAME?}\"`"
		fi
		cat <<EOF | send_mail_msg "$to_mail" "Tinderbox failure, $message" "" "${OWNER?}" ""
Hi folks,

One of you broke the build of LibreOffice master with your commit :-(
Please commit and push a fix ASAP!

${tinder1}

Tinderbox info:

  ${tinder2}
  Machine: `uname -a`
  Configured with: `cat autogen.lastrun`

Commits since the last success:

$(get_commit_since_last_good commits)

The error is:

$*
EOF
	else
		echo "$*" 1>&2
		if test "$error_kind" = "owner" ; then
			exit 1
		fi
	fi
}


collect_current_heads()
{
	./g -1 rev-parse --verify HEAD > tb_current-git-heads.log
	print_date > tb_current-git-timestamp.log
}

get_commits_since_last_good()
{
    local mode=$1
	local head=
	local repo=
	local sha=

	if [ -f tb_last-success-git-heads.txt ] ; then
		for head in $(cat tb_last-success-git-heads.txt) ; do
			repo=${head##:*}
			sha=${head#*:}
			(
				if [ "${repo?}" != "bootstrap" ] ; then
					cd clone/${repo?}
				fi
                if [ "${mode?}" = "people" ] ; then
                    echo "==== ${repo} ===="
				    git log '--pretty=tformat:%ce' ${sha?}..HEAD
                else
                    git log '--pretty=tformat:%h  %s' ${sha?}..HEAD | sed 's/^/  /'

                fi
			)
		done
	fi
}

get_committers()
{
    $(get_commits_since_last_good people | sort | uniq | tr '\n' ',')
}

rotate_logs()
{

	if [ "$retval" = "0" ] ; then
		cp -f tb_current-git-heads.log tb_last-success-git-heads.txt 2>/dev/null
		cp -f tb_current-git-timestamp.log tb_last-success-git-timestamp.txt 2>/dev/null
	fi
	for f in tb_*.log ; do
		mv -f ${f} prev-${f} 2>/dev/null
	done
}

push_nightlies()
{
	local curr_day=

	#upload new daily build?
	if [ "$PUSH_NIGHTLIES" = "1" ] ; then
		curr_day=$(date -u '+%j')
		last_day_upload="$(cat tb_last-upload-day.txt) 2>/dev/null"
		if [ -z $last_day_upload -o $last_day_upload -lt $curr_day ]; then
			$bin_path/push_nightlies.sh -t "$(cat tb_current-git-timestamp.log)" -n "$TINDER_NAME" -l "$BANDWIDTH"
			if [ "$?" == "0" ] ; then
				echo "$curr_day" > tb_last-upload-day.txt
			fi
		fi
	fi
}

wait_for_commits()
{
	local show_once=1
	local err_msgs=

	while true; do
		err_msgs="$(./g pull -r 2>&1)"
		if [ "$?" -ne "0" ] ; then
			report_error owner "$(date)" $(printf "git repo broken - error is:\n\n$err_msgs")
		else
			collect_current_heads

		    if [ "$(cat tb_current-git-heads.log)" != "$(cat prev-tb_current-git-heads.log)" ] ; then
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

if [ -f "${bin_dir?}/tinbuild_internals_${m}.sh" ] ; then
	source "${bin_dir?}/tinbuild_internals_${m}.sh"
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

source ${bin_dir?}/tinbuild_phases.sh


tb_call()
{
	declare -F "$1" > /dev/null && $1
}

phase()
{
	local f=${1}
	for x in {pre_,do_,_post}${f} ; do
		tb_call ${x}
	done
}


do_build()
{
	retval=0
	for p in autogen clean make test push ; do
        echo "call $p"
		phase $p
	done
}
