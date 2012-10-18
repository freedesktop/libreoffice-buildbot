#!/usr/bin/env bash
#
#    Copyright (C) 2011-2012 Norbert Thiebaud, Robinson Tryon
#    License: GPLv3
#

lock_file=/tmp/tinbuild-lockfile
push_opts="-a"

# Do we have timeout? If yes, guard git pull with that - which has a
# tendency to hang forever, when connection is flaky
if which timeout > /dev/null 2>&1 ; then
	# std coreutils - timeout is two hours
	timeout="`which timeout` 2h"
fi

if [ -z "$FLOCK" ] ; then
    if [ -x ${BIN_DIR?}/flock ] ; then
	FLOCK="${BIN_DIR?}/flock"
    else
	FLOCK="$(which flock)"
    fi
fi

do_flock()
{
    if [ "$LOCK" = "1" ] ; then
        if [ -n "${FLOCK}" -a -x "$FLOCK" ] ; then
            [ $V ] && echo "locking... $@"
            ${FLOCK} $@
            [ $V ] && echo "locked. $@"
        else
            echo "no flock implementation, please build it from buildbot/flock or use -e" 1>&2
            exit 1;
        fi
    else
	true
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

die()
{
    echo "[$(print_date) $TINDER_BRANCH] Error:" "$@"
    exit -1;
}

source_build_env()
{
    if test -f ./config.mk ; then
        . ./config.mk
    fi

    if test -f ./Env.Host.sh ; then
        . ./Env.Host.sh
    fi
}

generate_cgit_link()
{
    line="$1"
    repo=$(echo $line | cut -f 1 -d \:)
    sha=$(echo $line | cut -f 2 -d \:)

    echo "<a href='http://cgit.freedesktop.org/libreoffice/${repo}/commit/?id=$sha'>$repo</a>"
}

prepare_upload_manifest()
{
    local manifest_file="build_info.txt"

    echo "Build Info" > $manifest_file

    echo "tinderbox: administrator: ${OWNER?}" >> $manifest_file
    echo "tinderbox: buildname: ${TINDER_NAME?}" >> $manifest_file
    echo "tinderbox: tree: ${TINDER_BRANCH?}" >> $manifest_file
    echo "tinderbox: pull time $(cat "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log")" >> $manifest_file
    echo "tinderbox: git sha1s"  >> $manifest_file
    cat "${METADATA_DIR?}/tb_${B}_current-git-heads.log"  >> $manifest_file
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

    if [ -f .gitmodules ] ; then
	head=$(head -n1 "${METADATA_DIR?}/tb_${B}_last-success-git-heads.txt")
	repo=$(echo ${head} | cut -d : -f 1)
	sha=$(echo ${head} | cut -d : -f 2)
        if [ "${mode?}" = "people" ] ; then
	    git log '--pretty=tformat:%ce' ${sha?}..HEAD
        else
	    echo "==== ${repo} ===="
	    git log '--pretty=tformat:%h  %s' ${sha?}..HEAD | sed 's/^/  /'
        fi
    else
	if [ -f "${METADATA_DIR?}/tb_${B}_last-success-git-heads.txt" ] ; then
	    for head in $(cat "${METADATA_DIR?}/tb_${B}_last-success-git-heads.txt") ; do
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
    fi
}

get_commits_since_last_bad()
{
    local mode=$1
    local head=
    local repo=
    local sha=

    if [ -f .gitmodules ] ; then
	head=$(head -n1 "${METADATA_DIR?}/tb_${B}_last-failure-git-heads.txt")
	repo=$(echo ${head} | cut -d : -f 1)
	sha=$(echo ${head} | cut -d : -f 2)
        if [ "${mode?}" = "people" ] ; then
	    git log '--pretty=tformat:%ce' ${sha?}..HEAD
        else
	    echo "==== ${repo} ===="
	    git log '--pretty=tformat:%h  %s' ${sha?}..HEAD | sed 's/^/  /'
        fi
    else
	if [ -f tb_${B}_last-failure-git-heads.txt ] ; then
	    for head in $(cat "${METADATA_DIR?}/tb_${B}_last-failure-git-heads.txt") ; do
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
    [ $V ] && echo "report_to_tinderbox status=$2"
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
       (
           echo "$message_content"
           cat "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log"
           for cm in $(cat ${METADATA_DIR?}/tb_${B}_current-git-heads.log) ; do echo "TinderboxPrint: $(generate_cgit_link ${cm})" ; done
           cat tb_${B}_autogen.log tb_${B}_clean.log tb_${B}_build.log tb_${B}_tests.log 2>/dev/null
       ) | gzip -c > "${gzlog}"
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
    local error_log="$1"
    shift

    local last_success=$(cat "${METADATA_DIR?}/tb_${B}_last-success-git-timestamp.txt")
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

	cat <<EOF | send_mail_msg "$to_mail" "Tinderbox failure, $TINDER_NAME, $TINDER_BRANCH, $message" "" "${OWNER?}" ""
Hi folks,

One of you broke the build of LibreOffice with your commit :-(
Please commit and push a fix ASAP!

${tinder1}

Tinderbox info:

  ${tinder2}
  Branch: $TINDER_BRANCH
  "starttime": $(epoch_from_utc "$rough_time")
  Machine: `uname -a`
  Configured with: `cat autogen.lastrun`

Commits since the last success:

$(get_commits_since_last_good commits)

The error is:

$(cat "$error_log")
EOF
    else
	cat $error_log
    fi
}

report_fixed ()
{
    local_to_mail=
    local tinder1=
    local tinder2=
    local mail_tail=
    local success_kind="$1"
    shift
    local rough_time="$1"
    shift

    local previous_success="$(cat tb_${B}_last-success-git-timestamp.txt)"
    local last_failure="$(cat tb_${B}_last-failure-git-timestamp.txt)"
    to_mail=
    if [ "$SEND_MAIL" = "owner" -o "$SEND_MAIL" = "debug" -o "$SEND_MAIL" = "author" ] ; then
        to_mail="${OWNER?}"
    else
        if [ "$SEND_MAIL" = "all" ] ; then
	    case "$success_kind" in
		owner) to_mail="${OWNER?}"
		    message="box fixed" ;;
		*)
                    if [ -z "$previous_success" ] ; then
                      # we need at least one successful build to
                      # be reliable
			to_mail="${OWNER?}"
		    else
			to_mail="$(get_committers)"
		    fi
		    message="previous success: ${previous_success?}" ;;
	    esac
        fi
    fi
    if [ -n "$to_mail" ] ; then
	echo "$*" 1>&2
	echo "Previous success: ${previous_success}" 1>&2
	echo "Last failure: ${last_failure}" 1>&2
	tinder1="`echo \"Full log available at http://tinderbox.libreoffice.org/$TINDER_BRANCH/status.html\"`"
	tinder2="`echo \"Box name: ${TINDER_NAME?}\"`"
	if [ "$*" != "" ]; then
	    mail_tail = $'\nAdditional information:\n\n'"$*"
	fi

	cat <<EOF | send_mail_msg "$to_mail" "Tinderbox fixed, $message" "" "${OWNER?}" ""
Hi folks,

The previously reported build failure is fixed. Thanks!

${tinder1}

Tinderbox info:

  ${tinder2}
  Machine: `uname -a`
  Configured with: `cat autogen.lastrun`

Commits since last failure:

$(get_commits_since_last_bad commits)

Commits since the previous success:

$(get_commits_since_last_good commits)
${mail_tail}
EOF
    else
	echo "$*" 1>&2
    fi
}

collect_current_heads()
{
    [ $V ] && echo "collect_current_head"
    if [ -f .gitmodules ] ; then
	echo "core:$(git rev-parse HEAD)" > "${METADATA_DIR?}/tb_${B}_current-git-heads.log"
    else
	./g -1 rev-parse HEAD > "${METADATA_DIR?}/tb_${B}_current-git-heads.log"
    fi
    print_date > "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log"
}

get_committers()
{
    echo "get_committers: $(get_commits_since_last_good people)" 1>&2
    get_commits_since_last_good people | sort | uniq | tr '\n' ','
}

rotate_logs()
{
    if [ "$retval" = "0" ] ; then
	cp -f "${METADATA_DIR?}/tb_${B}_current-git-heads.log" "${METADATA_DIR?}/tb_${B}_last-success-git-heads.txt" 2>/dev/null
	cp -f "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log" "${METADATA_DIR?}/tb_${B}_last-success-git-timestamp.txt" 2>/dev/null
    elif [ "$retval" != "false_negative" ]; then
	cp -f "${METADATA_DIR?}/tb_${B}_current-git-heads.log" "${METADATA_DIR?}/tb_${B}_last-failure-git-heads.txt" 2>/dev/null
	cp -f "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log" "${METADATA_DIR?}/tb_${B}_last-failure-git-timestamp.txt" 2>/dev/null
    fi
    for f in tb_${B}*.log ; do
	mv -f ${f} prev-${f} 2>/dev/null
    done
    pushd "${METADATA_DIR?}" > /dev/null
    for f in tb_${B}*.log ; do
	mv -f ${f} prev-${f} 2>/dev/null
    done
    popd > /dev/null
}

check_for_commit()
{
    [ $V ] && echo "pulling from the repos"
    err_msgs="$( $timeout ./g pull -r 2>&1)"
    if [ "$?" -ne "0" ] ; then
	printf "git repo broken - error is:\n\n$err_msgs" > error_log.log
	report_error owner "$(print_date)" error_log.log
	IS_NEW_COMMIT="error"
    else
        collect_current_heads

        if [ "$(cat "${METADATA_DIR?}/tb_${B}_current-git-heads.log")" != "$(cat "${METADATA_DIR?}/prev-tb_${B}_current-git-heads.log")" ] ; then
	    IS_NEW_COMMIT="yes"
        else
	    IS_NEW_COMMIT="no"
	fi
    fi
    [ $V ] && echo "pulling from the repos -> new commit : ${IS_NEW_COMMIT?}"
}

check_for_gerrit()
{
local result

    IS_NEW_GERRIT="error"
    result=$(ssh ${GERRIT_HOST?} buildbot get-task -p core -a ${GERRIT_PLATFORM?} --format bash)
    result=$(echo "$result" | grep "^GERRIT_TASK_")
    if [ -n "${result}" ] ; then
	eval "${result}"
	IS_NEW_GERRIT="yes"
    else
	#FIXME normal "no task" detection
	IS_NEW_GERRIT="no"
    fi
}

wait_for_commits()
{
    local show_once=1
    local err_msgs=

    while true; do
	check_for_commit
	case "${IS_NEW_COMMIT?}" in
	    error)
		log_msgs "Error pulling... Waiting ${PAUSE_SECONDS?} seconds."
		sleep ${PAUSE_SECONDS?}
		;;
	    no)
		if [ "$show_once" = "1" ] ; then
                    log_msgs "Waiting until there are changes in the repo..."
                    show_once=0
		fi
		[ $V ] && echo "sleep 60"
		sleep 60
		;;
	    yes)
		return
		;;
	esac
    done
}

determine_make()
{
    ## Determine how GNU make is called on the system
    for _g in make gmake gnumake; do
	$_g --version 2> /dev/null | grep -q GNU
	if test $? -eq 0;  then
	    MAKE=$_g
	    break
	fi
    done
}

find_dev_install_location()
{
    find . -name opt -type d
}


position_bibisect_branch()
{
    pushd ${ARTIFACTDIR?} > /dev/null
    git checkout -q ${B?}
    if [ "$?" -ne "0" ] ; then
	echo "Error could not position the bibisect repository to the branch $B" 1>&2
	exit 1;
    fi
    popd > /dev/null
}

deliver_lo_to_bibisect()
{
    # copy the content of lo proper to bibisect
    # this is  separate function so it can easily be overriden
	cp -fR ${optdir?} ${ARTIFACTDIR?}/

}

bibisect_gc()
{
    pushd ${ARTIFACTDIR?} > /dev/null
    git gc
    popd > /dev/null
}

deliver_to_bibisect()
{
local cc=""
local oc=""

    [ $V ] && echo "deliver_to_bibisect()"
    (
        do_flock -x 201

        if [ -n ${optdir} ] ; then
            # verify that someone did not screw-up bibisect repo
            # while we were running
            if [ "${PUSH_TO_BIBISECT_REPO}" != "0" ] ; then
                # note: this function will exit if something is wrong
                position_bibisect_branch
            # avoid delivering the same build twice to bibisect
                cc=$(git rev-list -1 HEAD)
                if [ -f  ${ARTIFACTDIR?}/commit.hash ] ; then
                    oc="$(cat ${ARTIFACTDIR}/commit.hash)"
                fi
                if [ "${cc}" != "${oc}" ] ; then
                    deliver_lo_to_bibisect

                    git log -1 --pretty=format:"source-hash-%H%n%n" $BUILDCOMMIT > ${ARTIFACTDIR?}/commitmsg
                    git log -1 --pretty=fuller $BUILDCOMMIT >> ${ARTIFACTDIR?}/commitmsg

                    [ $V ] && echo "Bibisect: Include interesting logs/other data"
                    # Include the autogen log.
                    cp tb_${B?}_autogen.log ${ARTIFACTDIR?}

                    # Include the build, test logs.
                    cp tb_${B?}_build.log ${ARTIFACTDIR?}

                    # Make it easy to grab the commit id.
                    git rev-list -1 HEAD > ${ARTIFACTDIR?}/commit.hash

                    # Commit build to the local repo and push to the remote.
                    [ $V ] && echo "Bibisect: Committing to local bibisect repo"
                    pushd "${ARTIFACTDIR?}" >/dev/null
                    git add -A
                    git commit -q --file=commitmsg
                    popd > /dev/null
                fi
            fi
        fi
    ) 201> ${lock_file?}.bibisect
    [ $V ] && echo "unlock ${lock_file?}.bibisect"
    # asynchhronously compact the bibisect repo, but still hold a lock to avoid try to mess with the reo while being compressed
    (
        do_flock -x 201
        #close the upper-level lock
        exec 200>&-
        bibisect_gc
	[ $V ] && echo "unlock ${lock_file?}.bibisect"
    )  201> ${lock_file?}.bibisect &
}

push_bibisect()
{
    # TODO: push the local bibisect to the remote one
    # this need to be async with lock the same way push_bightly works
    # (note that git may actually already provide the lock to be verified
    #  so that git push & may be enough here)
    # optionally we can push once in a while
    # or at a certain time of the day...
    true
}

push_nightly()
{
    local curr_day=

    # Push build up to the project server (if enabled).
    if [ "$PUSH_NIGHTLIES" = "1" ] ; then
        [ $V ] && echo "Push: Nightly builds enabled"
        curr_day=$(date -u '+%Y%j')
	last_day_upload="$(cat "${METADATA_DIR?}/tb_${B}_last-upload-day.txt" 2>/dev/null)"
	if [ -z "$last_day_upload" ] ; then
            last_day_upload=0
	fi
	[ $V ] && echo "curr_day=$curr_day"
	[ $V ] && echo "last_day_upload=$last_day_upload"

        # If it has been less than a day since we pushed the last build
        # (based on calendar date), skip the rest of the push phase.
	if [ $last_day_upload -ge $curr_day ] ; then
            return 0;
	fi
        [ $V ] && echo "Push Nightly builds"
        prepare_upload_manifest
        ${BIN_DIR?}/push_nightlies.sh $push_opts -t "$(cat "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log")" -n "$TINDER_NAME" -l "$BANDWIDTH"
        # If we had a failure in pushing the build up, return
        # immediately (making sure we do not mark this build as the
        # last uploaded daily build).
        if [ "$?" != "0" ] ; then
            return 0;
        fi
	echo "$curr_day" > "${METADATA_DIR?}/tb_${B}_last-upload-day.txt"
    fi

}

report_gerrit()
{
    if [ "${retval?}" = "0" ] ; then
	ssh ${GERRIT_HOST?} buildbot report --ticket "${GERRIT_TASK_ID}" --succeed
    else
	ssh ${GERRIT_HOST?} buildbot report --ticket "${GERRIT_TASK_ID}" --failed
    fi
}

fetch_gerrit()
{
    GERRIT_PREV_B=`git branch | grep '^\*' | sed 's/^..//' | sed 's/\//_/g'`
    git fetch ssh://${GERRIT_HOST?}/core ${GERRIT_TASK_REF}
    if [ "$?" != "0" ] ; then
	retval="3"
    else
	git checkout FETCH_HEAD || die "fatal error checking out gerrit ref"
    fi
}

run_primer()
{
    if [ "$SEND_MAIL" != "owner" ] ; then
        SEND_MAIL=""  # we don't want to notify the tinderbox
    fi
    # if we want to upload after a prime, we really want to upload, not just once a day
    if [ "$PUSH_NIGHTLIES" = "1" ] ; then
        rm -f "${METADATA_DIR?}/tb_${B?}_last-upload-day.txt"
    fi


    log_msgs "Starting primer for branch '$TINDER_BRANCH'."
    (
        do_flock -x 200

	collect_current_heads
	retval="0"
	if [ "$DO_NOT_CLEAN" = "1" ] ; then
	    PHASE_LIST="autogen make test push"
	else
	    PHASE_LIST="autogen clean make test push"
	fi
        do_build "tb"

        rotate_logs
        if [ "$retval" = "0" ] ; then
            exit 0
        else
            exit 1
        fi
    ) 200>${lock_file?}
    retval=$?
    [ $V ] && echo "unlock ${lock_file?}"
    return ${retval?}
}

run_gerrit_patch()
{
    if [ "$PUSH_NIGHTLIES" = "1" ] ; then
        echo "Warning: pushing build is not supported with gerrit build" 1>&2
	PUSH_NIGHTLIES=0
    fi
    if [ "$SEND_MAIL" != "owner" ] ; then
        SEND_MAIL=""  # we don't want to notify the tinderbox
    fi

    log_msgs "Starting build for gerrit ref '$GERRIT_REF'."
    (
        do_flock -x 200

	GERRIT_PREV_B=`git branch | grep '^\*' | sed 's/^..//' | sed 's/\//_/g'`
	[ $V ] && echo "git fetch ssh://${GERRIT_HOST?}/core $GERRIT_REF"
	git fetch ssh://${GERRIT_HOST?}/core $GERRIT_REF && git checkout FETCH_HEAD || die "Error setting up the ref";

        echo "ssh ${GERRIT_HOST?} gerrit review --project core --force-message -m \"Starting Build on ${TINDER_NAME}\" $(git rev-parse HEAD)"
        ssh ${GERRIT_HOST?} gerrit review --project core --force-message -m \"Starting Build on ${TINDER_NAME}\" $(git rev-parse HEAD) || die "error reviewing in"

	retval="0"
	PHASE_LIST="autogen clean make test push"
        do_build "gerrit"

        if [ "${retval}" = "0" ] ; then
            echo "ssh ${GERRIT_HOST?} gerrit review --project core --force-message -m \"Successful build of $(git rev-parse HEAD) on tinderbox: $TINDER_NAME\" --verified +1 $(git rev-parse HEAD)"
            ssh ${GERRIT_HOST?} gerrit review --project core --force-message -m \"Successful build of $(git rev-parse HEAD) on tinderbox: $TINDER_NAME\" --verified +1 $(git rev-parse HEAD)
        else
            echo "ssh ${GERRIT_HOST?} gerrit review --project core --force-message -m \"Failed build of $(git rev-parse HEAD) on tinderbox: $TINDER_NAME\" --verified -1 $(git rev-parse HEAD)"
            ssh ${GERRIT_HOST?} gerrit review --project core --force-message -m \"Failed build of $(git rev-parse HEAD) on tinderbox: $TINDER_NAME\" --verified -1 $(git rev-parse HEAD) || die "error reviewing out"

        fi
        if [ -n "$GERRIT_PREV_B" ] ; then
            git checkout "$GERRIT_PREV_B"
        fi
        if [ "$retval" = "0" ] ; then
            exit 0
        else
            exit 1
        fi
    ) 200>${lock_file?}
    retval=$?
    [ $V ] && echo "unlock ${lock_file?}"
    return ${retval?}
}

run_gerrit_loop()
{
    # main tinderbox loop
    while true; do
	if [ -f tb_${B}_stop ] ; then
            break
	fi
	(
            do_flock -x 200

            check_for_gerrit

	    if [ "${IS_NEW_GERRIT}" = "yes" ] ; then

		fetch_gerrit

		if [ "$retval" = "0" ] ; then

		    PHASE_LIST="autogen clean make test push"
		    do_build "gerrit"

		    report_gerrit
		fi
		if [ -n "$GERRIT_PREV_B" ] ; then
		    git checkout "$GERRIT_PREV_B"
		fi
		if [ "$retval" = "0" ] ; then
		    exit 0
		elif [ "$retval" = "3" ] ; then
		    exit 3
		elif [ "$retval" = "-1" ] ; then
		    exit -1
		else
		    exit 1
		fi
	    else
		exit 3
	    fi
	) 200>${lock_file?}
	retval=$?
	[ $V ] && echo "unlock ${lock_file?}"
	if [ -f tb_${B}_stop -o "${retval?}" = "-1" ] ; then
            break
	fi
	if [ "$retval" = "3" ] ; then
	    [ $V ] && echo "sleep 60"
	    sleep 60
            retval="0"
	fi
    done
}



run_tb_gerrit_loop()
{
local priority="${1:-fair}"
local next_priority="$priority"
local retry_count

    if [ "${priority?}" = "fair" ] ; then
	next_priority="tb"
    fi

    while true; do

	if [ -f tb_${B?}_stop ] ; then
            break
	fi
	(
            do_flock -x 200
	    build_type=""
	    if [ "${next_priority?}" = "tb" ] ; then
		check_for_commit
		if [ "${IS_NEW_COMMIT?}" = "yes" ] ; then
		    build_type="tb"
		    if [ "${priority?}" = "fair" ] ; then
			next_priority="gerrit"
		    fi
		else
		    check_for_gerrit
		    if [ "${IS_NEW_GERRIT?}" = "yes" ] ; then
			build_type="tb"
			if [ "${priority?}" = "fair" ] ; then
			    last_priority="tb"
			fi
		    fi
		fi
	    else
		check_for_gerrit
		if [ "${IS_NEW_GERRIT?}" = "yes" ] ; then
		    build_type="tb"
		    if [ "${priority?}" = "fair" ] ; then
			last_priority="tb"
		    fi
		else
		    check_for_commit
		    if [ "${IS_NEW_COMMIT?}" = "yes" ] ; then
			build_type="tb"
			if [ "${priority?}" = "fair" ] ; then
			    next_priority="gerrit"
			fi
		    fi
		fi
	    fi
	    if [ "${build_type}" = "tb" ] ; then

		last_checkout_date="$(cat "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log")"

		report_to_tinderbox "${last_checkout_date?}" "building" "no"

		previous_build_status="${build_status}"
		build_status="build_failed"
		retval=0
		retry_count=3

		if [ "$DO_NOT_CLEAN" = "1" ] ; then
		    PHASE_LIST="autogen make test push"
		else
		    PHASE_LIST="autogen clean make test push"
		fi

		while [ "${PHASE_LIST}" != "" ] ; do

		    do_build "tb"

		    if [ "$retval" = "0" ] ; then
			build_status="success"
			report_to_tinderbox "$last_checkout_date" "success" "yes"
			if [ "${previous_build_status}" = "build_failed" ]; then
			    report_fixed committer "$last_checkout_date"
			fi
		    elif [ "$retval" = "false_negative" ] ; then
			report_to_tinderbox "${last_checkout_date?}" "fold" "no"
			log_msgs "False negative build, skip reporting"
                    # false negative does not need a full clean build, let's just redo make and after
			retry_count=$((retry_count - 1))
			if [ "$retry_count" = "0" ] ; then
			    PHASE_LIST=
			else
			    PHASE_LIST="make test push"
			fi
		    else
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
		    fi
		done

		rotate_logs

		if [ "$retval" = "0" ] ; then
		    exit 0
		elif [ "$retval" = "false_negative" ] ; then
		    exit 2
		else
		    exit 1
		fi
	    elif [ "${build_type?}" = "gerrit" ] ; then

		fetch_gerrit

		if [ "${retval?}" = "0" ] ; then

		    PHASE_LIST="autogen clean make test push"
		    retry_count=3
		    while [ "${PHASE_LIST}" != "" ] ; do
			do_build "gerrit"
			if [ "${retval?}" = "false_negative" ] ; then
			    report_to_tinderbox "${last_checkout_date?}" "fold" "no"
			    log_msgs "False negative build, skip reporting"
                    # false negative does not need a full clean build, let's just redo make and after
			    retry_count=$((retry_count - 1))
			    if [ "${retry_count?}" = "0" ] ; then
				PHASE_LIST=
			    else
				PHASE_LIST="make test push"
			    fi
			else
			    report_gerrit
			fi
		    done
		fi
		if [ -n "$GERRIT_PREV_B" ] ; then
		    git checkout "$GERRIT_PREV_B"
		fi
		if [ "${retval?}" = "0" ] ; then
		    exit 0
		elif [ "${retval?}" = "3" ] ; then
		    exit 3
		elif [ "$retval" = "-1" ] ; then
		    exit -1
		else
		    exit 1
		fi
	    else
		exit 3
	    fi
	) 200>${lock_file?}

	ret="$?"
	if [ -f tb_${B}_stop -o "${retval?}" = "-1" ] ; then
            break
	fi
	if [ "${ret?}" == "2" ] ; then
            retval="false_negative"
	elif [ "$ret" == "3" ] ; then
	    [ $V ] && echo "sleep 60"
	    sleep 60
            retval="0"
	else
            log_msgs "Waiting ${PAUSE_SECONDS?} seconds."
	    sleep ${PAUSE_SECONDS?}
            retval="0"
	fi
    done

    if [ -f tb_${B}_stop ] ; then
	log_msgs "Stoped by request"
	rm tb_${B}_stop
    fi




}
run_tb_loop()
{
    if [ ! -f "${METADATA_DIR?}/tb_${B}_last-success-git-heads.txt" ] ; then
        echo "You need a valid baseline. run once with -z or make sure you have a valid ${METADATA_DIR?}/tb_${B}_last-success-git-heads.txt" 1>&2
        exit 1;
    else
        if [ "$FORCE_REBUILD" = "1" ] ; then
            retval="false_negative" # to force a rebuild the first time around
        else
            retval=0
        fi
        cp "${METADATA_DIR?}/tb_${B}_last-success-git-heads.txt" "${METADATA_DIR?}/tb_${B}_current-git-heads.log"
        cp "${METADATA_DIR?}/tb_${B}_last-success-git-timestamp.txt" "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log"
        rotate_logs
    fi

    # main tinderbox loop
    while true; do

	if [ -f tb_${B}_stop ] ; then
            break
	fi
	(
            do_flock -x 200

	    if [ "$retval" != "false_negative" ] ; then
		check_for_commit
	    else
		collect_current_heads
		IS_NEW_COMMIT="yes"
	    fi
	    if [ "${IS_NEW_COMMIT?}" = "yes" ] ; then

		last_checkout_date="$(cat "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log")"

		report_to_tinderbox "${last_checkout_date?}" "building" "no"

		previous_build_status="${build_status}"
		build_status="build_failed"
		retval=0
		retry_count=3

		if [ "$DO_NOT_CLEAN" = "1" ] ; then
		    PHASE_LIST="autogen make test push"
		else
		    PHASE_LIST="autogen clean make test push"
		fi

		while [ "${PHASE_LIST}" != "" ] ; do

		    do_build "tb"

		    if [ "$retval" = "0" ] ; then
			build_status="success"
			report_to_tinderbox "$last_checkout_date" "success" "yes"
			if [ "${previous_build_status}" = "build_failed" ]; then
			    report_fixed committer "$last_checkout_date"
			fi
		    elif [ "$retval" = "false_negative" ] ; then
			report_to_tinderbox "${last_checkout_date?}" "fold" "no"
			log_msgs "False negative build, skip reporting"
                    # false negative does not need a full clean build, let's just redo make and after
			retry_count=$((retry_count - 1))
			if [ "$retry_count" = "0" ] ; then
			    PHASE_LIST=
			else
			    PHASE_LIST="make test push"
			fi
		    else
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
		    fi
		done

		rotate_logs

		if [ "$retval" = "0" ] ; then
		    exit 0
		elif [ "$retval" = "false_negative" ] ; then
		    exit 2
		else
		    exit 1
		fi
	    else
		exit 3
	    fi

	) 200>${lock_file?}
	ret="$?"
	[ $V ] && echo "unlock ${lock_file?}"

	if [ -f tb_${B}_stop ] ; then
            break
	fi
	if [ "$ret" == "2" ] ; then
            retval="false_negative"
	elif [ "$ret" == "3" ] ; then
	    [ $V ] && echo "sleep 60"
	    sleep 60
            retval="0"
	else
            log_msgs "Waiting ${PAUSE_SECONDS?} seconds."
	    sleep ${PAUSE_SECONDS?}
            retval="0"
	fi
    done

    if [ -f tb_${B}_stop ] ; then
	log_msgs "Stoped by request"
	rm tb_${B}_stop
    fi

}

################
# ATTENTION:
# Nothing below this point can be overriden at the platform-level
# so you should probably add code above this point
# unless you have a darn good reason not to

# source the platform specific override

mo="$(uname -o 2>/dev/null)"
ms="$(uname -s 2>/dev/null)"
if [ -n "${mo}" -a -f "${BIN_DIR?}/tinbuild_internals_${mo}.sh" ] ; then
    source "${BIN_DIR?}/tinbuild_internals_${mo}.sh"
else
    if [ -n "${ms}" -a -f "${BIN_DIR?}/tinbuild_internals_${ms}.sh" ] ; then
	source "${BIN_DIR?}/tinbuild_internals_${ms}.sh"
    fi
fi
unset mo
unset ms


determine_make


source ${BIN_DIR?}/tinbuild_phases.sh

