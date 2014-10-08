#!/usr/bin/env bash
# -*- tab-width : 4; indent-tabs-mode : nil -*-
#
#    Copyright (C) 2011-2013 Norbert Thiebaud
#    License: GPLv3
#
#
# Naming convention/Namespace
#
# lowercase variable: local variable. must be declared as 'local'
#
# tb_UPPER_CASE : global variable internal to the script. not to be set directly by config.
#
# TB_UPPER_CASE : global variable that can or must be set by config
#
# in general use readable variable name, use _ to separate the part of the variables name
#
# Exception: P : current project name
#            R : build result indicator ( 0=OK 1=KO 2=False positive )
#            V : verbose messages (V=1 => verbose message V= => no verbose message, iow: [ $V ] && log_msgs ....
#         MAKE : environement variable is use if set to point to a gnu-make
#                otherwise overriden to a gne-make found in the PATH
#
# canonical_* reserverved for phase implementation in tb_phases.sh
# canonical_[pre|do|post]_<phase> is garanteed to exist, even if it is a no-op function.
#
# The rational for these namespace is to allow lower-level overload to still call
# the implementation at higher level.
#
# for instance if a profile phase.sh want derefine the TMPDIR and clean it up
# in the pre-clean phase, but still want to do what-ever the tb_phase.sh normally do
# it can implement
# pre_clean()
# {
#    do what I need to do
#    canonical_pre_clean() to invoke the defautl impelmentation
# }
#
# ATTENTION: do not abuse this scheme by having defferent level invoking different phase
# at higher level... so a profile's pre_clean() for instance shall not invoke canonical_do_clean()
# or any other phase than *_pre_clean()
#
# Configuration files layout
#
#  ~/.tb/config
#       /meta/
#       /phases.sh
#       /profiles/<profile_name>/autogen.lastrun
#       /profiles/<profile_name>/config
#       /profiles/<profile_name>/false_negatives
#       /profiles/<profile_name>/phases.sh

# Note: config are accumulated from high to low.
#       autogen are 'lowest level prime'.

# XRef :
#

P=
V=
tb_LOGFILE="/dev/null"


# please keep the function declaration in alphabetical order


bibisect_post()
{
    pushd ${TB_BIBISECT_DIR?} > /dev/null
    if [ "${TB_BIBISECT_GC}" = "1" ] ; then
        git gc
    fi
    if [ "${TB_BIBISECT_PUSH}" = "1" ] ; then
        git push
    fi
    popd > /dev/null
}

#
# Save the sha associated with the HEAD of the current branch
#
collect_current_head()
{
    [ $V ] && echo "collect_current_head"
    echo "$(git rev-parse HEAD)" > "${TB_METADATA_DIR?}/${P?}_current-git-head.log"
    print_date > "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log"
}

#
# Copy the autogen.lastrun in the builddir
# this assume that the cwd is the builddir
# and that B and tb_BUILD_TYPE are set
# This is notmally called fromthe do_autogen()
# phase.
#
copy_autogen_config()
{
    if [ -f "${tb_CONFIG_DIR?}/profiles/${P?}/autogen.lastrun" ] ; then
        cp "${tb_CONFIG_DIR?}/profiles/${P?}/autogen.lastrun" autogen.input
    else
        cp "${tb_CONFIG_DIR?}/profiles/${P?}/autogen.input" autogen.input
    fi
}

deliver_lo_to_bibisect()
{
    # copy the content of lo proper to bibisect
    # this is  separate function so it can easily be overriden
    cp -fR ${tb_OPT_DIR?} ${TB_BIBISECT_DIR?}/

}

deliver_to_bibisect()
{
    local cc=""
    local oc=""

    [ $V ] && echo "deliver_to_bibisect()"

    if [ -n ${tb_OPT_DIR} ] ; then
        # verify that someone did not screw-up bibisect repo
        # while we were running
        if [ "${TB_BIBISECT}" != "0" ] ; then
            # note: this function will exit if something is wrong

            # avoid delivering the same build twice to bibisect
            cc=$(git rev-list -1 HEAD)
            if [ -f  "${TB_BIBISECT_DIR?}/commit.hash" ] ; then
                oc="$(cat ${TB_BIBISECT_DIR?}/commit.hash)"
            fi
            if [ "${cc}" != "${oc}" ] ; then
                deliver_lo_to_bibisect

                git log -1 --pretty=format:"source-hash-%H%n%n" ${tb_BUILD_COMMIT?} > "${TB_BIBISECT_DIR?}/commitmsg"
                git log -1 --pretty=fuller ${tb_BUILD_COMMIT?} >> "${TB_BIBISECT_DIR?}/commitmsg"

                [ $V ] && echo "Bibisect: Include interesting logs/other data"
                # Include the autogen log.
                cp tb_${P?}_autogen.log "${TB_BIBISECT_DIR?}/."

                # Include the build, test logs.
                cp tb_${P?}_build.log "${TB_BIBISECT_DIR?}/."

                # Make it easy to grab the commit id.
                git rev-list -1 HEAD > "${TB_BIBISECT_DIR?}/commit.hash"

                # Commit build to the local repo and push to the remote.
                [ $V ] && echo "Bibisect: Committing to local bibisect repo"
                pushd "${TB_BIBISECT_DIR?}" >/dev/null
                git add -A
                git commit -q --file=commitmsg
                popd > /dev/null

                bibisect_post

            fi
        fi
    fi

}


determine_default_tinderbox_branch()
{
    local b="$1"

    case "$b" in
        master)
            echo 'MASTER'
            ;;
        libreoffice-3-4)
            echo "${b?}"
            ;;
        libreoffice-3-5)
            echo "${b?}"
            ;;
        libreoffice-3-6)
            echo "${b?}"
            ;;
        libreoffice-4-0)
            echo "${b?}"
            ;;
        libreoffice-4-1)
            echo "${b?}"
            ;;
        libreoffice-4-2)
            echo "${b?}"
            ;;
        libreoffice-4-3)
            echo "${b?}"
            ;;
    esac
}

#
# Find a gnu make
#
determine_make()
{
    ## Determine how GNU make is called on the system
    if [ -n "$MAKE" ] ; then
        $MAKE --version 2> /dev/null | grep -q GNU
        if test $? -eq 0;  then
            return
        else
            MAKE=
        fi
    fi

    for _g in make gmake gnumake; do
        $_g --version 2> /dev/null | grep -q GNU
        if test $? -eq 0;  then
            MAKE=$_g
            break
        fi
    done
    if [ -z "$MAKE" ] ; then
        die "Could not find a Gnu Make"
    fi
}

#
# Display an error message and exit
# tb or a sub-shell
#
die()
{
    echo "[$(print_date) ${P}] Error:" "$@" | tee -a ${tb_LOGFILE?}
    R=-1
    exit -1;
}

epoch_from_utc()
{
    local utc="$@"

    date -u '+%s' -d "$utc UTC"
}

find_dev_install_location()
{
    find . -name opt -type d
}

generate_cgit_link()
{
    local sha="$1"

    echo "<a href='http://cgit.freedesktop.org/libreoffice/core/log/?id=$sha'>core</a>"
}

get_commits_since_last_good()
{
    local mode=$1
    local head=
    local repo=
    local sha=

    pushd "${TB_GIT_DIR?}" > /dev/null

    if [ -f "${TB_METADATA_DIR?}/${P?}_last-success-git-head.txt" ] ; then
        sha=$(head -n1 "${TB_METADATA_DIR?}/${P?}_last-success-git-head.txt")
        repo="core"
        if [ "${mode?}" = "people" ] ; then
            git log '--pretty=tformat:%ce' ${sha?}..HEAD
        else
            echo "==== ${repo} ===="
            git log '--pretty=tformat:%h  %s' ${sha?}..HEAD | sed 's/^/  /'
        fi
    else
        if [ "${mode?}" = "people" ] ; then
            echo "$TB_OWNER"
        else
            echo "==== ${repo} ===="
            echo "no primer available, can't extract the relevant log"
        fi
    fi
    popd > /dev/null # GIT_DIR
}

get_committers()
{
    echo "get_committers: $(get_commits_since_last_good people)" 1>&2
    get_commits_since_last_good people | sort | uniq | tr '\n' ','
}

interupted_build()
{
    log_msgs "Interrupted by Signal"
    if [ "$TB_MODE" = "gerrit" ] ; then
        if [ -n "${GERRIT_TASK_TICKET}" ] ;then
            # report a cancellation if we already acquired the ticket
            R=2
            report_gerrit
        fi
    elif [ "$TB_MODE" = "tb" ] ; then
        if [ -n "${tb_LAST_CHECKOUT_DATE?}" ] ; then
            # report a cancellation if we already notified a start
            report_to_tinderbox "${tb_LAST_CHECKOUT_DATE?}" "fold" "no"
        fi
    fi
    # propagate the stop request to the main loop
    touch ${tb_CONFIG_DIR?}/stop

    exit 4
}

load_config()
{
    tb_CONFIG_DIR="$HOME/.tb"
    if [ ! -d "${tb_CONFIG_DIR?}" ] ; then
        die "You need to configure tb to use it"
    fi
    if [ -f "${tb_CONFIG_DIR?}/config" ] ; then
        source "${tb_CONFIG_DIR?}/config"
    fi
}

load_profile()
{
    local p="$1"
    source_profile "${p?}"

    # deal with missing or default value
    if [ "${TB_TYPE?}" = "gerrit" ]; then
        profile_gerrit_defaults
    elif [ "${TB_TYPE?}" = "tb" ]; then
        profile_tb_defaults
    fi
}

log_msgs()
{
    echo "[$(print_date) ${P?}]" "$@" | tee -a ${tb_LOGFILE?}
}

position_bibisect_branch()
{
    pushd ${TB_BIBISECT_DIR?} > /dev/null
    git checkout -q ${TB_BRANCH?}
    if [ "$?" -ne "0" ] ; then
        echo "Error could not position the bibisect repository to the branch $B" 1>&2
        exit 1;
    fi
    popd > /dev/null
}

prepare_git_repo_for_gerrit()
{
    [ $V ] && echo "fetching gerrit path from ssh://${TB_GERRIT_HOST?}/core ${GERRIT_TASK_REF?}"

    (
        git clean -fd && git fetch ssh://${TB_GERRIT_HOST?}/core ${GERRIT_TASK_REF}
        if [ "$?" = "0" ] ; then
            git checkout FETCH_HEAD || exit -1
            git submodule update
        else
            exit -1
        fi
    ) 2>&1 > ${TB_BUILD_DIR}/error_log.log

    if [ "$?" != "0" ] ; then
        log_msgs "Error checkout out ${GERRIT_TASK_TICKET?}"
        R=2;
    fi

}

prepare_git_repo_for_tb()
{
    local remote_sha="$(cat "${TB_METADATA_DIR?}/${P?}_current-git-head.log")"
    local local_sha=
    local refspec=
    local remote_refspec=

    # by default the local branch name is the 'branch' name for the profile
    refspec="${TB_LOCAL_REFSPEC?}"
    remote_refspec="${TB_REMOTE_REFSPEC?}"

    if [ -z "$TB_BUILD_DIR" ] ; then
        TB_BUILD_DIR="${TB_GIT_DIR?}"
    fi

    (
        local_sha=$(git rev-parse ${refspec?})
        if [ "$?" = "0" ] ; then
            cb=$(git rev-parse --abbrev-ref HEAD)
            if [ "$?" = "0" -a "${cb?}" = "${refspec?}" ] ; then
                git clean -fd &&  git reset --hard ${remote_refspec?} && git submodule update
            else
                git clean -fd && git checkout -q ${refspec?} && git reset --hard ${remote_refspec?} && git submodule update
            fi
        else
            git clean -fd && git checkout -b ${refspec?} ${remote_refspec?} && git submodule update
        fi
    ) 2>&1 > ${TB_BUILD_DIR}/error_log.log

    if [ "$?" != "0" ] ; then
        report_error owner "$(print_date)" error_log.log
        die "Cannot reposition repo ${TB_GIT_DIR?} to the proper branch"
    fi

}

prepare_upload_manifest()
{
    local manifest_file="build_info.txt"

    echo "Build Info" > $manifest_file

    echo "tinderbox: administrator: ${TB_OWNER?}" >> $manifest_file
    echo "tinderbox: buildname: ${TB_NAME?}" >> $manifest_file
    echo "tinderbox: tree: ${TB_TINDERBOX_BRANCH?}" >> $manifest_file
    echo "tinderbox: pull time $(cat "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log")" >> $manifest_file
    echo "tinderbox: git sha1s"  >> $manifest_file
    echo "core:$(cat ${TB_METADATA_DIR?}/${P?}_current-git-head.log)"  >> $manifest_file
    echo ""  >> $manifest_file
    echo "tinderbox: autogen log"  >> $manifest_file
    cat tb_${P?}_autogen.log  >> $manifest_file

}

print_date()
{
    date -u '+%Y-%m-%d %H:%M:%S'
}

print_local_date()
{
    date '+%Y-%m-%d %H:%M:%S'
}

profile_gerrit_defaults()
{
    if [ -z "$TB_BUILD_DIR" ] ; then
        TB_BUILD_DIR="${TB_GIT_DIR?}"
    fi
    if [ "${TB_GERRIT_TEST}" = "1" -o "${TB_TEST}" = "1" ] ; then
        tb_GERRIT_TEST="-t"
    fi
    if [ -z "${TB_GERRIT_PLATFORM}" ] ; then
        os=$(uname)
        case "$os" in
            *Linux*)
                TB_GERRIT_PLATFORM="LINUX"
                ;;
            Darwin)
                TB_GERRIT_PLATFORM="MAC"
                ;;
            CYGWIN*)
                TB_GERRIT_PLATFORM="WINDOWS"
                ;;
        esac
        if [ -z "${TB_GERRIT_PLATFORM}" ] ; then
            die "Could not determine gerrit platform for ${os}"
        fi
    fi
}

profile_tb_defaults()
{
    if [ -z "$TB_BUILD_DIR" ] ; then
        TB_BUILD_DIR="${TB_GIT_DIR?}"
    fi
    if [ -z "${TB_LOCAL_REFSPEC}" ] ; then
        TB_LOCAL_REFSPEC="${TB_BRANCH?}"
    fi
    if [ -z "${TB_REMOTE_REFSPEC}" ] ; then
        TB_REMOTE_REFSPEC="origin/${TB_LOCAL_REFSPEC}"
    fi
    if [ -n "${TB_SEND_MAIL}" ] ; then
        tb_SEND_MAIL="${TB_SEND_MAIL}"
    fi
}

push_bibisect()
{
    local curr_day=
    local last_day_upload=

    if [ ${TB_BIBISECT} = "1" -a -n "${tb_OPT_DIR}" ] ; then

        [ $V ] && echo "Push: bibisec builds enabled"
        curr_day=$(date -u '+%Y%j')
        last_day_upload="$(cat "${TB_METADATA_DIR?}/${P?}_last-bibisect-day.txt" 2>/dev/null)"
        if [ -z "$last_day_upload" ] ; then
            last_day_upload=0
        fi
        [ $V ] && echo "bibisect curr_day=$curr_day"
        [ $V ] && echo "bibisect last_day_upload=$last_day_upload"

        # If it has been less than a day since we pushed the last build
        # (based on calendar date), skip the rest of the push phase.
        if [ $last_day_upload -ge $curr_day ] ; then
            return 0;
        fi
        [ $V ] && echo "Record bibisect"
        deliver_to_bibisect

        echo "$curr_day" > "${TB_METADATA_DIR?}/${P?}_last-bibisect-day.txt"

    fi
}

# Add pdb files for binaries of the given extension (exe,dll)
# and type (Library/Executable) to the given list.
add_pdb_files()
{
    extension=$1
    type=$2
    list=$3
    find instdir/ -name "*.${extension}" | while read file
    do
        filename=`basename $file .${extension}`
        pdb="workdir/LinkTarget/${type}/${filename}.pdb"
        if test -f "$pdb"; then
            echo `cygpath -w $pdb` >>$list
        fi
    done

}

# upload .pdb symbols (for Windows remote debugging server)
push_symbols()
{
    [ -n "$TB_SYMBOLS_DIR" ] || return 1

    local PULL_TIME="$(cat "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log")"

    pushd "$TB_BUILD_DIR" >/dev/null
    ssh upload@gimli.documentfoundation.org "mkdir -p \"/srv/www/dev-builds.libreoffice.org/daily/${TB_BRANCH?}/${TB_NAME?}/symbols\"" || return 1
    echo "update symbols"
    rm -f symbols-pdb-list.txt
    mkdir -p "${TB_SYMBOLS_DIR}"
    add_pdb_files dll Library symbols-pdb-list.txt
    add_pdb_files exe Executable symbols-pdb-list.txt
    "${TB_SYMSTORE}" add /f @symbols-pdb-list.txt /s `cygpath -w $TB_SYMBOLS_DIR` /t LibreOffice /v "$PULL_TIME"
    rm symbols-pdb-list.txt

    # The maximum number of versions of symbols to keep, older revisions will be removed.
    # Unless the .dll/.exe changes, the .pdb should be shared, so with incremental tinderbox several revisions should
    # not be that space-demanding.
    KEEP_MAX_REVISIONS=5
    to_remove=`ls -1 ${TB_SYMBOLS_DIR}/000Admin | grep -v '\.txt' | grep -v '\.deleted' | sort | head -n -${KEEP_MAX_REVISIONS}`
    for revision in $to_remove; do
        "${TB_SYMSTORE}" del /i ${revision} /s `cygpath -w $TB_SYMBOLS_DIR`
    done
    popd >/dev/null

    rsync --bwlimit=${TB_BANDWIDTH_LIMIT} --fuzzy --delete-after -avzP -e ssh "${TB_SYMBOLS_DIR}/" "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${TB_BRANCH?}/${TB_NAME?}/symbols/" || return 1
}

push_nightly()
{
    local curr_day=
    local last_day_upload=
    local upload_time=
    local inpath=
    local stage=
    local file=
    local target=
    local tag=
    local pack_loc=

    # Push build up to the project server (if enabled).
    [ $V ] && echo "Push: Nightly builds enabled"
    curr_day=$(date -u '+%Y%j')
    last_day_upload="$(cat "${TB_METADATA_DIR?}/${P?}_last-upload-day.txt" 2>/dev/null)"
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

    upload_time="$(cat "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log" | sed -e "s/ /_/g" | sed -e "s/:/./g")"
    ssh upload@gimli.documentfoundation.org "mkdir -p \"/srv/www/dev-builds.libreoffice.org/daily/${TB_BRANCH?}/${TB_NAME?}/${upload_time?}\"" || return 1

    if [ -f config_host.mk ] ; then
        inpath=$(grep INPATH= config_host.mk | sed -e "s/.*=//")
        if [ -n "${inpath?}" -a -d "instsetoo_native/${inpath?}" ] ; then
            pack_loc="instsetoo_native/${inpath?}"
        else
            pack_loc="workdir"
        fi
    else
        pack_loc="instsetoo_native/${inpath?}"
    fi
    pushd "${pack_loc?}" > /dev/null
    rm -fr push
    mkdir push 2>/dev/null
    stage="./push"
    tag="${P?}~${upload_time?}"

    for file in $(find . -name "*.dmg" -o -name '*.apk' -o -name "Lib*.tar.gz" -o -name "Lib*.exe" -o -name "Lib*.zip" -o -path '*/installation/*/msi/install/*.msi' | grep -v "/push/")
    do
        target=$(basename $file)
        target="${tag}_${target}"
        mv $file "$stage/$target"
    done;

    rsync --bwlimit=${TB_BANDWIDTH_LIMIT} -avPe ssh ${stage}/${tag}_* "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${TB_BRANCH?}/${TB_NAME?}/${upload_time?}/" || return 1
    if [ "$?" == "0" ] ; then
        ssh upload@gimli.documentfoundation.org "cd \"/srv/www/dev-builds.libreoffice.org/daily/${TB_BRANCH?}/${TB_NAME?}/\" && { rm current; ln -s \"${upload_time}\" current ; }"
    fi
    echo "$curr_day" > "${TB_METADATA_DIR?}/${P?}_last-upload-day.txt"
    popd  > /dev/null # pack_loc

    # Push pdb symbols too if needed
    if [ "$TB_PUSH_SYMBOLS" = "1" ] ; then
        push_symbols
    fi

    return 0
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

    local last_success=$(cat "${TB_METADATA_DIR?}/${P?}_last-success-git-timestamp.txt")
    to_mail=
    if [ "${tb_SEND_MAIL?}" = "owner" -o "${tb_SEND_MAIL?}" = "debug" -o "${tb_SEND_MAIL?}" = "author" ] ; then
        to_mail="${TB_OWNER?}"
    else
        if [ "${tb_SEND_MAIL?}" = "all" ] ; then
            case "$error_kind" in
                owner) to_mail="${TB_OWNER?}"
                    message="box broken" ;;
                *)
                    if [ -z "$last_success" ] ; then
                        # we need at least one successful build to
                        # be reliable
                        to_mail="${TB_OWNER?}"
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
        tinder1="`echo \"Full log available at http://tinderbox.libreoffice.org/${TB_TINDERBOX_BRANCH?}/status.html\"`"
        tinder2="`echo \"Box name: ${TB_NAME?}\"`"

        cat <<EOF | send_mail_msg "$to_mail" "Tinderbox failure, ${TB_NAME?}, ${TB_TINDERBOX_BRANCH?}, $message" "" "${TB_OWNER?}" ""
Hi folks,

One of you broke the build of LibreOffice with your commit :-(
Please commit and push a fix ASAP!

${tinder1}

 Tinderbox info:

 ${tinder2}
 Branch: $TB_BRANCH
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

report_gerrit()
{
local log_type="$1"
local status=
local gzlog=

    [ $V ] && echo "report to gerrit retval=${R} log_type=${log_type}"
    if [ "$log_type" = "short"  -a "${R?}" = "0" ] ; then
        gzlog="tinder.log.gz"
        (
            echo "gerrit_task_ticket:${GERRIT_TASK_TICKET?}"
            echo "gerrit_task_branch:${GERRIT_TASK_BRANCH?}"
            echo "gerrit task_ref:${GERRIT_TASK_REF?}"
            echo ""
            echo "Build: OK"
            echo ""
            cat tb_${P?}_autogen.log 2>/dev/null
        ) | gzip -c > "${gzlog}"
    else
        gzlog="tinder.log.gz"
        (
            echo "gerrit_task_ticket:${GERRIT_TASK_TICKET?}"
            echo "gerrit_task_branch:${GERRIT_TASK_BRANCH?}"
            echo "gerrit task_ref:${GERRIT_TASK_REF?}"
            echo ""
            if [ "${R?}" = "0" ] ; then
                echo "Build: OK"
            else
                echo "Build: FAIL"
            fi
            echo ""
            cat tb_${P?}_autogen.log tb_${P?}_clean.log tb_${P?}_build.log tb_${P?}_tests.log 2>/dev/null
        ) | gzip -c > "${gzlog}"
    fi

    if [ "${R?}" = "0" ] ; then
        log_msgs "Report Success for gerrit ref ${GERRIT_TASK_TICKET?}"
        status="success"
    elif [ "${R?}" = "1" ] ; then
        log_msgs "Report Failure for gerrit ref ${GERRIT_TASK_TICKET?}"
        status="failed"
    else
        log_msgs "Report Cancellation for gerrit ref ${GERRIT_TASK_TICKET?}"
        status="canceled"
    fi
    cat "${gzlog}" | ssh ${TB_GERRIT_HOST?} buildbot put --ticket "${GERRIT_TASK_TICKET?}" --status $status --log -
}


report_to_tinderbox()
{
    [ $V ] && echo "report_to_tinderbox status=$2"
    if [ -z "${tb_SEND_MAIL}" -o "${tb_SEND_MAIL}" = "none" ] ; then
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

    if [ -z "${TB_TINDERBOX_BRANCH}" ] ; then
        TB_TINDERBOX_BRANCH=$(determine_default_tinderbox_branch "${TB_BRANCH?}")
    fi

    start_line="tinderbox: starttime: $(epoch_from_utc ${start_date})"
    message_content="
tinderbox: administrator: ${TB_OWNER?}
tinderbox: buildname: ${TB_NAME?}
tinderbox: tree: ${TB_TINDERBOX_BRANCH?}
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
            cat "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log"
            for cm in $(cat "${TB_METADATA_DIR?}/${P?}_current-git-head.log") ; do echo "TinderboxPrint: $(generate_cgit_link "${cm}")" ; done
            cat tb_${P?}_autogen.log tb_${P?}_clean.log tb_${P?}_build.log tb_${P?}_tests.log 2>/dev/null
        ) | gzip -c > "${gzlog}"
        xtinder="X-Tinder: gzookie"
        subject="tinderbox gzipped logfile"
    fi

    if [ "$SEND_MAIL" = "debug" ] ; then
        echo "$message_content" | send_mail_msg "${TB_OWNER?}" "${subject?}" "${xtinder?}" '' "${gzlog}"
    elif [ "$SEND_MAIL" = "author" ] ; then
        echo "$message_content" | send_mail_msg "${TB_OWNER?}" "${subject?}" "${xtinder?}" '' "${gzlog}"
        if [ -n "${tb_BRANCH_AUTHOR}" ] ; then
            echo "$message_content" | send_mail_msg "${tb_BRANCH_AUTHOR}" "${subject?}" "${xtinder?}" '' "${gzlog}"
        fi
    else
        echo "$message_content" | send_mail_msg "tinderbox@gimli.documentfoundation.org" "${subject?}" "${xtinder?}" '' "${gzlog}"
    fi
}

rotate_active_profiles()
{
    local x=
    local p="$1"
    local rot=""

    for x in ${tb_ACTIVE_PROFILES} ; do
        if [ "${x?}" != "${p?}" ] ; then
            if [ -z "${rot?}" ] ; then
                rot="${x?}"
            else
                rot="${rot?} ${x?}"
            fi
        fi
    done
    if [ -z "${rot?}" ] ; then
        rot="${p?}"
    else
        rot="${rot?} ${p?}"
    fi
    tb_ACTIVE_PROFILES="${rot?}"
}

rotate_logs()
{
    if [ "${R?}" = "0" ] ; then
        cp -f "${TB_METADATA_DIR?}/${P?}_current-git-head.log" "${TB_METADATA_DIR?}/${P?}_last-success-git-head.txt" 2>/dev/null
        cp -f "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log" "${TB_METADATA_DIR?}/${P?}_last-success-git-timestamp.txt" 2>/dev/null
    elif [ "${R}" != "2" ]; then # do not count abandonned false_negative loop as failure
        cp -f "${TB_METADATA_DIR?}/${P?}_current-git-head.log" "${TB_METADATA_DIR?}/${P?}_last-failure-git-head.txt" 2>/dev/null
        cp -f "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log" "${TB_METADATA_DIR?}/${P?}_last-failure-git-timestamp.txt" 2>/dev/null
    fi
    for f in tb_${P?}_*.log ; do
        mv -f ${f} prev-${f} 2>/dev/null
    done
    pushd "${TB_METADATA_DIR?}" > /dev/null
    for f in ${P?}_*.log ; do
        mv -f ${f} prev-${f} 2>/dev/null
    done
    popd > /dev/null

}

#
# Run a gerrit build
#
# Run a a subshell to isolate Branch-level config
#
run_gerrit_task()
{
    log_msgs "Starting build gerrit ref:${GERRIT_TASK_TICKET?}"

    # clean-up the git repo associated with the
    # branch and checkout the target sha
    prepare_git_repo_for_gerrit

    # if prepare repor failed R is no 0 anymore
    if [ "${R}" == 0 ] ; then
        # gerrit build are not incremental
        # always use all the phases and cleanup after yourself
        local phase_list="autogen clean make test push clean"

        pushd ${TB_BUILD_DIR?} > /dev/null || die "Cannot cd to build dir : ${TB_BUILD_DIR?}"

        # run the build
        do_build ${phase_list?}
    fi
    # tell the gerrit buildbot of the result of the build
    # R contain the overall result
    report_gerrit

    popd > /dev/null # BUILD_DIR
}

#
# Main loop
#
run_loop()
{
local s=0

    while true; do

        # Check for stop request
        if [ -f ${tb_CONFIG_DIR?}/stop ] ; then
            break;
        else
            sleep ${s?}
        fi

        # Select the next task
        # this set P
        run_next_task

        # based on the build type run the appropriate build
        if [ -z "${P?}" ] ; then
            if [ "${s?}" != "${TB_POLL_DELAY?}" ] ; then
                log_msgs "Nothing to do. waiting ${TB_POLL_DELAY?} seconds."
            fi
            s=${TB_POLL_DELAY?}
        else
            s=${TB_POST_BUILD_DELAY?}
        fi
    done

    # if we were stopped by request, let's log that
    # clean the semaphore file
    if [ -f ${tb_CONFIG_DIR?}/stop ] ; then
        log_msgs "Stoped by request"
        rm ${tb_CONFIG_DIR?}/stop
    fi

}

#
# Find a profile that has something to do then run it
#
run_next_task()
{
    P=
    R=0
    for P in ${tb_ACTIVE_PROFILES} ; do
        try_run_task "$P"
        if [ "${R}" = "0" ] ; then
            break;
        fi
        P=
    done
    if [ "${TB_SCHEDULING}" = "fair" ] ; then
        if [ -n "$P" -a "${R}" = "0" ] ; then
            rotate_active_profiles "${P?}"
        fi
    fi
}

run_primer()
{
    P=
    R=0
    for P in ${tb_ACTIVE_PROFILES} ; do
        (
        local triggered=0
        R=0
        trap 'interupted_build' SIGINT SIGQUIT
        load_profile "${P?}"

        # we do not want to send any email on 'primer/one-shot' build
        tb_SEND_MAIL="none"
        pushd "${TB_GIT_DIR?}" > /dev/null || die "Cannot cd to git repo ${TB_GIT_DIR?} for profile ${P?}"
        run_tb_task
        exit "$R"
        )
        R="$?"
    done

}

run_tb_task()
{
    local phase_list
    local retry_count=3

    if [ "${tb_ONE_SHOT?}" != "1" ] ; then
        prepare_git_repo_for_tb
    else
        collect_current_head
    fi

    log_msgs "Starting tb build for sha:$(cat "${TB_METADATA_DIR?}/${P?}_current-git-head.log")"

    tb_LAST_CHECKOUT_DATE="$(cat "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log")"
    report_to_tinderbox "${tb_LAST_CHECKOUT_DATE?}" "building" "no"

    if [ "$TB_INCREMENTAL" = "1" ] ; then
        phase_list="autogen make test push"
    else
        phase_list="autogen clean make test push"
    fi

    pushd ${TB_BUILD_DIR?} > /dev/null || die "Cannot cd to build dir : ${TB_BUILD_DIR?}"

    while [ "${phase_list}" != "" ] ; do

        do_build ${phase_list?}

        if [ "${R?}" = "0" ] ; then
            report_to_tinderbox "${tb_LAST_CHECKOUT_DATE}" "success" "yes"
            phase_list=
            log_msgs "Successful tb build for sha:$(cat "${TB_METADATA_DIR?}/${P?}_current-git-head.log")"
        elif [ "${R?}" = "2" ] ; then
            log_msgs "False negative build, skip reporting"
                    # false negative does not need a full clean build, let's just redo make and after
            retry_count=$((retry_count - 1))
            if [ "$retry_count" = "0" ] ; then
                log_msgs "False Negative Failed tb build for sha:$(cat "${TB_METADATA_DIR?}/${P?}_current-git-head.log")"
                phase_list=""
                R=2
                if [ "${tb_ONE_SHOT?}" != "1" ] ; then
                    report_to_tinderbox "${tb_LAST_CHECKOUT_DATE?}" "fold" "no"
                fi
            else
                log_msgs "False Negative Retry tb build for sha:$(cat "${TB_METADATA_DIR?}/${P?}_current-git-head.log")"
                phase_list="make test push"
                R=0
            fi
        else
            printf "${tb_REPORT_MSGS?}:\n\n" > report_error.log
            echo "======" >> report_error.log
            if [ "${tb_REPORT_LOG?}" == "tb_${P?}_build.log" ] ; then
                tail -n1000 ${tb_REPORT_LOG?} >> report_error.log
            else
                cat ${tb_REPORT_LOG?} >> report_error.log
            fi
            report_error committer "${tb_LAST_CHECKOUT_DATE?}" report_error.log
            report_to_tinderbox "${tb_LAST_CHECKOUT_DATE?}" "build_failed" "yes"
            phase_list=""
            log_msgs "Failed tb build for sha:$(cat "${TB_METADATA_DIR?}/${P?}_current-git-head.log")"
        fi
    done
    tb_LAST_CHECKOUT_DATE=
    rotate_logs
    popd > /dev/null # BUILD_DIR

}

#
# Select a gerrit task from
# the gerrit buildbot plugin
#
select_next_gerrit_task()
{
    local result
    local has_task
    local r=0

    # short-cut triiger based build
    if [ -n "${TB_TRIGGER_FILE}" ] ; then
        if [ ! -f "${TB_TRIGGER_FILE}" ] ; then
            R=3
            [ $V ] && echo "Trigger file ${TB_TRIGGER_FILE} missing for profile ${P?} -> R=${R?}"
            return
        fi
    fi

    [ $V ] && echo "Try to get a task for gerrit buildbot"

    GERRIT_TASK_TICKET=""
    GERRIT_TASK_BRANCH=""
    GERRIT_TASK_REF=""
    GERRIT_TASK_FEATURE=""
    result=$(ssh ${TB_GERRIT_HOST?} buildbot get -p core -a ${TB_GERRIT_PLATFORM?} --format BASH ${TB_BRANCH?} ${tb_GERRIT_TEST})
    [ $V ] && echo "Get task result:${result}"

    has_task=$(echo "$result" | grep "^GERRIT_TASK_")
    if [ -n "${has_task}" ] ; then
        eval "${result}"
        if [ -z "${GERRIT_TASK_TICKET}" -o -z "${GERRIT_TASK_REF}" -o -z "${GERRIT_TASK_BRANCH}" ] ; then
            [ $V ] && echo "no valid task from gerrit buildbot"
            R=2
        else
            [ $V ] && echo "got task TASK_TICKET=$GERRIT_TASK_TICKET TASK_REF=$GERRIT_TASK_REF TASK_BRANCH=${GERRIT_TASK_BRANCH} for profile ${P?} "
            R=0
        fi
    else
        [ $V ] && echo "no task from gerrit buildbot"
        R=2
    fi
    if [ "${R?}" = "0" ] ; then
        if [ -n "${TB_TRIGGER_FILE}" ] ; then
            R=1
            [ $V ] && echo "Trigger file ${TB_TRIGGER_FILE} detected for profile ${P?} -> R=${R?}"
        fi
    fi
}

#
# Select the next task to do
# either tb or gerrit depending
# on the mode of operation
#
select_next_task()
{
    if [ "${TB_TYPE?}" = "tb" ] ; then
        select_next_tb_task
    elif [ "${TB_TYPE?}" = "gerrit" ] ; then
        select_next_gerrit_task
    else
        die "Invalid TB_TYPE:$TB_TYPE"
    fi
}

#
# Select a Tinderbox task
# by seraching for new commits
# on on of the branches under consideration
#
select_next_tb_task()
{
    # short-cut triiger based build
    if [ -n "${TB_TRIGGER_FILE}" ] ; then
        if [ ! -f "${TB_TRIGGER_FILE}" ] ; then
            R=3
            [ $V ] && echo "Trigger file ${TB_TRIGGER_FILE} missing for profile ${P?} -> R=${R?}"
            return
        fi
    fi

    [ $V ] && echo "Checking for new commit for profile ${P?}"

    err_msgs="$( $tb_TIMEOUT git fetch 2>&1)"
    if [ "$?" -ne "0" ] ; then
        printf "Git repo broken - error is:\n\n$err_msgs" > error_log.log
        report_error owner "$(print_date)" error_log.log
        R="-1"
    else
        refspec="${TB_REMOTE_REFSPEC?}"

        [ $V ] && echo "collect current head for profile ${P?} refspec ${refspec?}"
        rev=$(git rev-parse ${refspec?})
        if [ "$?" = "0" ] ; then
            echo "${rev?}" > "${TB_METADATA_DIR?}/${P?}_current-git-head.log"
            print_date > "${TB_METADATA_DIR?}/${P?}_current-git-timestamp.log"

            if [ ! -f "${TB_METADATA_DIR?}/prev-${P?}_current-git-head.log" ] ; then
                [ $V ] && echo "New commit for profile ${P?} (no primer)"
                R=0
            elif [ "$(cat "${TB_METADATA_DIR?}/${P?}_current-git-head.log")" != "$(cat "${TB_METADATA_DIR?}/prev-${P?}_current-git-head.log")" ] ; then
                [ $V ] && echo "New commit for profile ${P?}"
                R=0
            else
                [ $V ] && echo "No New commit for profile ${P?}"
                R=2
            fi
        else
            log_msgs "Git error while checking for commit on ${TB_GIT_DIR?} for profile ${P?}"
            printf "Git repo broken - error is:\n\n$err_msgs" > error_log.log
            report_error owner "$(print_date)" error_log.log
            return -1
        fi
    fi
    [ $V ] && echo "pulling from the repo ${TB_GIT_DIR?} for profile ${P?} -> R=${R?}"
    if [ "${R?}" = "0" ] ; then
        if [ -n "${TB_TRIGGER_FILE}" ] ; then
            if [ -f "${TB_TRIGGER_FILE}" ] ; then
                R=1
                [ $V ] && echo "Trigger file ${TB_TRIGGER_FILE} detected for profile ${P?} -> R=${R?}"
            else
                R=3
                [ $V ] && echo "Trigger file ${TB_TRIGGER_FILE} missing for profile ${P?} -> R=${R?}"
            fi
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

    if [ -n "${TB_SMTP_USER}" ] ; then
        smtp_auth="-xu ${TB_SMTP_USER?} -xp ${TB_SMTP_PASSWORD?}"
    fi

    [ $V ] && log_msgs "send mail to ${to?} with subject \"${subject?}\""
    [ $V ] && quiet=""
    if [ -n "${log}" ] ; then
        ${tb_BIN_DIR?}/tb_send_email $quiet -f "${TB_OWNER?}" -s "${TB_SMTP_HOST?}" $smtp_auth -t "${to?}" -bcc "${bcc?}" -u "${subject?}" -o "message-header=${headers?}" -a "${log?}"
    elif [ -n "${headers?}" ] ; then
        ${tb_BIN_DIR?}/tb_send_email $quiet -f "${TB_OWNER?}" -s "${TB_SMTP_HOST?}" $smtp_auth -t "${to?}" -bcc "${bcc?}" -u "${subject?}" -o "message-header=${headers?}"
    else
        ${tb_BIN_DIR?}/tb_send_email $quiet -f "${TB_OWNER?}" -s "${TB_SMTP_HOST?}" $smtp_auth -t "${to?}" -bcc "${bcc?}" -u "${subject?}"
    fi
}

#
# Setup factory default for variables
#
# this is invoked before the profile is known
# so it cannot be overriden in the profile's phases.sh
#
set_factory_default()
{
    TB_INCREMENTAL=
    TB_GERRIT_HOST="logerrit"
    TB_POLL_DELAY=120
    TB_POST_BUILD_DELAY=15
    TB_BIBISECT=0
    TB_PUSH_NIGHTLIES=0
    TB_BANDWIDTH_LIMIT=2000

    TB_SYMBOLS_DIR="${HOME}/symbols"
    TB_SYMSTORE="/cygdrive/c/Program Files/Debugging Tools for Windows (x64)/symstore.exe"

    tb_ONE_SHOT=
    tb_SEND_MAIL="none"
    tb_PUSH_NIGHTLIES=0
    tb_CONFIG_DIR="~/.tb"
}

#
# Setup default at the global level
#
# Based on the content of the profile
# setup some interna variable
# assign some default and
# do some other housekeeping
#
# Verify that mandatory profile
# variables are defined
set_global_defaults()
{
    local os

    if [  -n "${TB_LOGFILE}" ] ; then
        if [ ! -f "${TB_LOGFILE?}" ] ; then
            touch "${TB_LOGFILE?}" || die "Creating ${TB_LOGFILE?}"
        fi
        tb_LOGFILE="${TB_LOGFILE?}"
    fi

    if [ -z "${TB_METADATA_DIR}" ] ; then
        TB_METADATA_DIR="${tb_CONFIG_DIR?}/meta"
    fi
    if [ ! -d "${TB_METADATA_DIR?}" ] ; then
        mkdir -p "${TB_METADATA_DIR?}" || die "Creating ${TB_METADATA_DIR?}"
    fi

}

source_profile()
{
    local p="$1"

    if [ -f "${tb_CONFIG_DIR?}/profiles/${p?}/config" ] ; then
        source "${tb_CONFIG_DIR?}/profiles/${p?}/config"
    else
        die "config ${tb_CONFIG_DIR?}/profiles/${p?}/config does not exist"
    fi
    if [ -f "${tb_CONFIG_DIR?}/profiles/${p?}/phases.sh" ] ; then
        source "${tb_CONFIG_DIR?}/profiles/${p?}/phases.sh"
    fi

}

try_run_task()
{
    (
        local triggered=0
        R=0
        trap 'interupted_build' SIGINT SIGQUIT
        load_profile "${P?}"

        pushd "${TB_GIT_DIR?}" > /dev/null || die "Cannot cd to git repo ${TB_GIT_DIR?} for profile ${P?}"

        select_next_task
        # do not delete the trigger until we succeed
        if [ "$R" = "1" ] ; then
            triggered="$R"
            R=0
        fi
        # best effort and delete
        if [ "$R" = "5" ] ; then
            triggered="$R"
            R=0
        fi
        if [ "$R" = "0" ] ; then
            if [ "${TB_TYPE?}" = "gerrit" ]; then
                run_gerrit_task
            elif [ "${TB_TYPE?}" = "tb" ]; then
                run_tb_task
            fi
        fi

        popd > /dev/null # GIT_DIR

        if [ "${triggered}" != "0" ] ; then
            if [ "triggered" = "1" -a "$R" = 0 ] ; then
                rm -f "${TB_TRIGGER_FILE?}"
            elif [ "triggered" = "5" ] ; then
                rm -f "${TB_TRIGGER_FILE?}"
            fi
        fi
        exit "$R"
    )
    R="$?"
    # check we we intercepted a signal, if so bail
    if [ "${R?}" = "4" ] ; then
        exit -1
    fi
}

validate_active_profile()
{
    local p="$1"
    (
        source_profile "${p?}"

        # check for mandatory values
        if [ -z "${TB_TYPE}" ] ; then
            die "Missing TB_TYPE for profile ${p?}"
        elif [ "${TB_TYPE}" = "gerrit" ] ; then
            validate_gerrit_profile "${p?}"
        elif [ "${TB_TYPE}" = "tb" ] ; then
            validate_tb_profile "${p?}"
        else
            die "Invalid TB_TYPE:${TB_TYPE} for profile ${p?}"
        fi
    )
    if test $? -ne 0;  then
        R=8
    fi
}

validate_active_profiles()
{
    if [ -z "${tb_ACTIVE_PROFILES}" ] ; then
        tb_ACTIVE_PROFILES="$TB_ACTIVE_PROFILES"
    fi
    if [ -z "${tb_ACTIVE_PROFILES}" ] ; then
        die "TB_ACTIVE_PROFILES, or -p <profile>  is required"
    fi
    R=0
    for P in ${tb_ACTIVE_PROFILES} ; do
        validate_active_profile $P
    done
    if [ "$R" != "0" ] ; then
        die "Error while validating actives profiles"
    fi
}

validate_gerrit_profile()
{
    local p="$1"
    if [ -z "${TB_NAME}" ] ; then
        die "TB_NAME is required to be configured"
    fi
    if [ -z "${TB_BRANCH}" ] ; then
        die "TB_BRANCH is required to be configured"
    fi
    if [ -z "${TB_GIT_DIR}" ] ; then
        die "TB_GIT_DIR is required to be configured"
    fi
    if [ ! -d "${TB_GIT_DIR?}" ] ; then
        die "TB_GIT_DIR:${TB_GIT_DIR?} is not a directory"
    fi
    if [ ! -d "${TB_GIT_DIR?}/.git" ] ; then
        die "TB_GIT_DIR:${TB_GIT_DIR?} is not a git repo"
    fi
    if [ -z "${TB_GERRIT_PLATFORM}" ] ; then
        os=$(uname)
        case "$os" in
            *Linux*)
                TB_GERRIT_PLATFORM="Linux"
                ;;
            Darwin)
                TB_GERRIT_PLATFORM="MacOSX"
                ;;
            CYGWIN*)
                TB_GERRIT_PLATFORM="Windows"
                ;;
        esac
        if [ -z "${TB_GERRIT_PLATFORM}" ] ; then
            die "Could not determine gerrit platform for ${os}"
        fi
    fi
}

validate_tb_profile()
{
    local p="$1"

    if [ -z "${TB_NAME}" ] ; then
        die "TB_NAME is required to be configured"
    fi
    if [ -z "${TB_OWNER}" ] ; then
        die "TB_OWNER is required to be configured"
    fi
    if [ -z "${TB_BRANCH}" ] ; then
        die "TB_BRANCH is required to be configured"
    fi
    if [ -z "${TB_NAME}" ] ; then
        die "TB_NAME is required to be configured"
    fi
    if [ -z "${TB_TINDERBOX_BRANCH}" ] ; then
        TB_TINDERBOX_BRANCH=$(determine_default_tinderbox_branch "${TB_BRANCH?}")
    fi
    if [ -z "${TB_TINDERBOX_BRANCH}" ] ; then
        die "TB_TINDERBOX_BRANCH is required to be configured"
    fi
    if [ -z "${TB_GIT_DIR}" ] ; then
        die "TB_GIT_DIR is required to be configured"
    fi
    if [ ! -d "${TB_GIT_DIR?}" ] ; then
        die "TB_GIT_DIR:${TB_GIT_DIR?} is not a directory"
    fi
    if [ ! -d "${TB_GIT_DIR?}/.git" ] ; then
        die "TB_GIT_DIR:${TB_GIT_DIR?} is not a git repo"
    fi
    if [ -n "$TB_BUILD_DIR" ] ; then
        if [ ! -d "${TB_BUILD_DIR}" ] ; then
            die "TB_BULD_DIR:${TB_BUILD_DIR?} is not a directory"
        fi
    fi

    if [ -n "${TB_SEND_MAIL}" ] ; then
        tb_SEND_MAIL="${TB_SEND_MAIL}"
    fi
    # if we want email to be sent, we must make sure that the required parameters are set in the profile (or in the environment)
    case "${tb_SEND_MAIL?}" in
        all|tb|owner|debug|author)
            if [ -z "${TB_SMTP_HOST}" ] ; then
                die "TB_SMTP_HOST is required in the config to send email"
            fi
            if [ -z "${TB_SMTP_USER}" ] ; then
                echo "Warning: missing SMTPUSER (can work, depends on your smtp server)" 1>&2
            fi
            if [ -n "${TB_SMTP_USER}" -a -z "${TB_SMTP_PASSWORD}" ] ; then
                die "TB_SMTP_PASSWORD is required with TB_SMTP_USER set"
            fi
            ;;
        none)
            ;;
        *)
            die "Invalid TB_SEND_MAIL argument:${tb_SEND_MAIL}"
            ;;
    esac

}


# Do we have timeout? If yes, guard git pull with that - which has a
# tendency to hang forever, when connection is flaky
if which timeout > /dev/null 2>&1 ; then
	# std coreutils - timeout is two hours
	tb_TIMEOUT="$(which timeout) 2h"
fi

################
# ATTENTION:
# Nothing below this point can be overriden at the platform-level
# so you should probably add code above this point
# unless you have a darn good reason not to

# source the platform specific override

mo="$(uname -o 2>/dev/null)"
ms="$(uname -s 2>/dev/null)"
if [ -n "${mo}" -a -f "${tb_BIN_DIR?}/tb_internals_${mo}.sh" ] ; then
    source "${tb_BIN_DIR?}/tb_internals_${mo}.sh"
else
    if [ -n "${ms}" -a -f "${tb_BIN_DIR?}/tb_internals_${ms}.sh" ] ; then
        source "${tb_BIN_DIR?}/tb_internals_${ms}.sh"
    fi
fi
unset mo
unset ms


determine_make


# source the standard build phases
source ${tb_BIN_DIR?}/tb_phases.sh
