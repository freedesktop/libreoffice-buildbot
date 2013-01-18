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
# Exception: P : project name
#            B : current branch name. gerrit_* are reserved branch names for gerrit works
#            R : build result indicator ( 0=OK 1=KO 2=False positive )
#            V : verbose messages (V=1 => verbose message V= => no verbose message, iow: [ $V ] && msgs_log ....
#         MAKE : environement variable is use if set to point to a gnu-make
#                otherwise overriden to a gne-make found in the PATH
#
# profile_* reserved for functions specific to .../<profile_name>/phases.sh
# branches_* reserved for functions specific to .../<branch_name>/phases.sh
# canonical_* reserverved for phase implementation in tb_phases.sh
# canonical_[pre|do|post]_<phase> is garanteed to exist, even if it is a no-op function.
#
# The rational for these namespace is to allow lower-level overload to still call
# the implementation at higher level.
#
# for instance if a branche phase.sh want derefine the TMPDIR and clean it up
# in the pre-clean phase, but still want to do what-ever the tb_phase.sh normally do
# it can implement
# pre_clean()
# {
#    do what I need to do
#    canonical_pre_clean() to invoke the defautl impelmentation
# }
#
# similarely at the profile level one can override pre-clean in this fashion:
#
# profile_pre_clean()
# {
#     profile override implementation fo pre-clean()
# }
#
# pre_clean()
# {
#     profile_pre_clean()
# }
#
# that way a branch's phase.sh can invoke profile_pre_clean in it's own implemenation of pre_clean()
#
# ATTENTION: do not abuse this scheme by having defferent level invoking different phase
# at higher level... so a branch's pre_clean() for instance shall not invoke canonical_do_clean()
# or any other phase than *_pre_clean()
# Obviously profile level phase.sh shall not invoke any branche_* functions.
#
# Configuration files layout
#
#  ~/.tb/config
#       /meta/
#       /phases.sh
#       /profiles/<profile_name>/autogen.lastrun
#       /profiles/<profile_name>/autogen.lastrun_gerrit
#       /profiles/<profile_name>/autogen.lastrun_tb
#       /profiles/<profile_name>/branches/<branch_name>/autogen.lastrun
#       /profiles/<profile_name>/branches/<branch_name>/autogen.lastrun_gerrit
#       /profiles/<profile_name>/branches/<branch_name>/autogen.lastrun_tb
#       /profiles/<profile_name>/branches/<branch_name>/config
#       /profiles/<profile_name>/branches/<branch_name>/config_gerrit
#       /profiles/<profile_name>/branches/<branch_name>/config_tb
#       /profiles/<profile_name>/branches/<branch_name>/false_negatives
#       /profiles/<profile_name>/config
#       /profiles/<profile_name>/false_negatives
#       /profiles/<profile_name>/phases.sh

# Note: config are accumulated from high to low.
#       autogen are 'lowest level prime'.

# XRef :
#
# tb_BIN_DIR :
# tb_BRANCHES :
# tb_BRANCH_AUTHOR :
# tb_BUILD_COMMIT :
# tb_BUILD_TYPE :
# tb_CONFIG_DIR :
# tb_GERRIT_BRANCHES :
# tb_GERRIT_PLATFORM :
# tb_KEEP_AUTOGEN :
# tb_LOGFILE :
# tb_MODE :
# tb_NEXT_PRIORITY :
# tb_ONE_SHOT :
# tb_OPT_DIR :
# tb_PRIORITY :
# tb_PRODILE_DIR :
# tb_PROFILE_DIR :
# tb_PUSH_NIGHTLIES :
# tb_REPORT_LOG :
# tb_REPORT_MSGS :
# tb_SEND_MAIL :
# tb_TB_BRANCHES :
# tb_TINDERBOX_BRANCH :


B=
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
# Check if a branch is suitably configured
# to be build for tb and/or gerrit
#
check_branch_profile()
{
    local b="$1"
    local type=
    local ret=
    local rb=

    if [ ! -d "${tb_PROFILE_DIR?}/${b?}" ] ; then
        msgs_log "No branch specific config for branch '${b?}', using default from profile"
    fi
    if [ "${tb_MODE?}" = "dual" -o "${tb_MODE?}" = "tb" ] ; then
        rb=$(check_branch_profile_tb "$b")
        ret=$?
        if [ "$ret" = "0" ] ; then
            if [ -z "${tb_TB_BRANCHES}" ] ; then
                tb_TB_BRANCHES="${rb?}"
            else
                tb_TB_BRANCHES="${tb_TB_BRANCHES?} ${rb?}"
            fi
        fi
    fi
    if [ "${tb_MODE?}" = "dual" -o "${tb_MODE?}" = "gerrit" ] ; then
        rb=$(check_branch_profile_gerrit "${b?}")
        ret=$?
        if [ "${ret?}" = "0" ] ; then
            if [ -z "${tb_GERRIT_BRANCHES}" ; then
                tb_GERRIT_BRANCHES="${rb?}"
            else
                tb_GERRIT_BRANCHES="${tb_GERRIT_BRANCHES?} ${rb?}"
            fi
        fi
    fi
}

#
# Checks common to both tb and gerrit
# buildability of a branch profile
#
check_branch_profile_common()
{
    local b="$1"

    if [ -z "${TB_GIT_DIR}" ] ; then
        die "Missing TB_GIT_DIR for branch ${b?}"
    else
        if [ ! -d "${TB_GIT_DIR?}" ] ; then
            die "TB_GIT_DIR:${TB_GIT_DIR?} for branch ${b?} is not a directory"
        fi
        if [ ! -d "${TB_GIT_DIR?}/.git" ] ; then
            die "TB_GIT_DIR:${TB_GIT_DIR?} for branch ${b?} is not a git repository"
        fi
    fi
    if [ -n "${TB_BUILD_DIR}" ] ; then
        if [ ! -d "${TB_BUILD_DIR?}" ] ; then
            die "TB_BUILD_DIR:${TB_BUILD_DIR?} for branch ${b?} does not exist"
        fi
    fi
}

#
# Check specific to gerrit builability
# of a branch profile
#
check_branch_profile_gerrit()
{
    local b="$1"

    # unset higher level CCACHE_DIR setting
    unset CCACHE_DIR

    source_branch_level_config "${b?}" "gerrit"

    # if CCACHE_DIR is set it has been set by the branch's profile
    # if TB_CCACHE_SIZE is set make sure the cache is as big as specified
    # note: no need to restore the old CCACHE value
    # since check_branches is run in a sub-shell
    if [ -n "${CCACHE_DIR}" ] ; then
        if [ -n "${TB_CCACHE_SIZE}" ] ; then
            ccache -M "${TB_CCACHE_SIZE?}" > /dev/null
        fi
    fi

    # if we did not die yet... we are good for this branch: print it
    echo "${b?}"

}

#
# Checks psecific to tb buildability
# of a branch
#
check_branch_profile_tb()
{
    local b="$1"
    local sha=

    # unset higher level CCACHE_DIR setting
    unset CCACHE_DIR

    source_branch_level_config "${b?}" "tb"

    if [ -z "${TB_TINDERBOX_BRANCH}" ; then
        # FIXME: determine if we can derive that value
        # from ${b}
        die "Missing TB_TINDERBOX_BRANCH to associate a BRANCH name on the tiderbox server to the branch ${b?}"
    fi

    if [ "${TB_BIBISECT}" == "1" ] ; then
        if  [ -z "${TB_BIBISECT_DIR}" ] ; then
            die "To do bibisect you must define TB_BIBISECT_DIR to point to your bibisect git repo"
        fi
        if [ ! -d "${TB_BIBISECT_DIR?}" -o ! -d "${TB_BIBISECT_DIR}/.git" ] ; then
            die "TB_BIBISECT_DIR:${TB_BIBISECT_DIR?} is not a git repository"
        fi
        pushd "${TB_BIBISECT_DIR?}" > /dev/null || die "Cannot cd to ${TB_BIBISECT_DIR?} for branch ${b?}"
        sha=$(git rev-parse "${b?}")
        if [ "$?" != "0" ] ; then
            die "Branch ${b?} does not exist in the bibisect repo, Cannot collect the requested bibisect"
        fi
    fi

    # if CCACHE_DIR is set it has been set by the branch's profile
    # if TB_CCACHE_SIZE is set make sure the cache is as big as specified
    # note: no need to restore the old CCACHE value
    # since check_branches is run in a sub-shell
    if [ -n "${CCACHE_DIR}" ] ; then
        if [ -n "${TB_CCACHE_SIZE}" ] ; then
            ccache -M "${TB_CCACHE_SIZE?}" > /dev/null
        fi
    fi

    # if we did not die yet... we are good for this branch: print it
    echo "${b?}"
}


#
# Check all the branches under consideration
# for suitable configuration
#
check_branches_profile()
{
local b

    tb_TB_BRANCHES=""
    tb_GERRIT_BRANCHES=""

    for b in ${tb_BRANCHES?} ; do
        if [ -z "$b" ] ; then
            die "Internal Error: trying to process and empty branch name"
        fi
        check_branch_profile "$b"
    done

    # Accumulate valid branches for tb and gerrit
    # depending of the mode
    if [ "$tb_MODE" = "dual" -o "$tb_MODE" = "gerrit" ] ; then
        if [ -z "$tb_GERRIT_BRANCHES" ] ; then
            die "No branches are configured properly for gerrit"
        fi
    fi
    if [ "$tb_MODE" = "dual" -o "$tb_MODE" = "tb" ] ; then
        if [ -z "$tb_TB_BRANCHES" ] ; then
            die "No branches are configured properly for tb"
        fi
    fi
}

#
# Determine if there are new commits
# on a given branch
#
check_for_commit()
{
    local b="$1"
    local err_msgs=
    local rev=
    local refspec=
    local r="-1"

    [ $V ] && echo "Checking for new commit for tb-branch ${b?}"

    source_branch_level_config "${b?}" "tb"

    pushd "${TB_GIT_DIR?}" > /dev/null || die "Cannot cd to git repo ${TB_GIT_DIR?} for tb-branche ${b?}"

    err_msgs="$( $tb_TIMEOUT git fetch 2>&1)"
    if [ "$?" -ne "0" ] ; then
        printf "Git repo broken - error is:\n\n$err_msgs" > error_log.log
        report_error owner "$(print_date)" error_log.log
        exit -1
    else
        refspec="origin/${b?}"
        if [ -n "${TB_BRANCH_REMOTE_REFSPEC}" ] ; then
            refspec="${TB_BRANCH_REMOTE_REFSPEC?}"
        fi
        [ $V ] && echo "collect current head for branch ${b?} refspec ${refspec?}"
        rev=$(git rev-parse ${refspec?})
        if [ "$?" = "0" ] ; then
            echo "${rev?}" > "${TB_METADATA_DIR?}/${P}_${b?}_current-git-head.log"
            print_date > "${TB_METADATA_DIR?}/${P}_${b?}_current-git-timestamp.log"

            if [ ! -f "${TB_METADATA_DIR?}/prev-${P?}_${b?}_current-git-head.log" ] ; then
                [ $V ] && echo "New commit for tb-branch ${b?} (no primer)"
                r=0
            elif [ "$(cat "${TB_METADATA_DIR?}/${P}_${b?}_current-git-head.log")" != "$(cat "${TB_METADATA_DIR?}/prev-${P?}_${b?}_current-git-head.log")" ] ; then
                [ $V ] && echo "New commit for tb-branch ${b?}"
                r=0
            else
                [ $V ] && echo "No New commit for tb-branch ${b?}"
                r=1
            fi
        else
            msgs_log "Git error while checking for commit on ${TB_GIT_REPO?} for branch ${b?}"
            printf "Git repo broken - error is:\n\n$err_msgs" > error_log.log
            report_error owner "$(print_date)" error_log.log
            exit -1
        fi
    fi
    [ $V ] && echo "pulling from the repo ${TB_GIT_REPO?} for branch ${b?} -> r=${r?}"
    exit ${r?}
}

#
# Save the sha assoicated with the HEAD of the current branch
#
collect_current_head()
{
    [ $V ] && echo "collect_current_head"
    echo "core:$(git rev-parse HEAD)" > "${TB_METADATA_DIR?}/${P}_${B?}_current-git-head.log"
    print_date > "${TB_METADATA_DIR?}/${P}_${B?}_current-git-timestamp.log"
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
    if [ -f "${tb_PROFILE_DIR?}/branches/${B}/autogen.lastrun_${tb_BUILD_TYPE?}" ] ; then
        cp "${tb_PROFILE_DIR?}/branches/${B}/autogen.lastrun_${tb_BUILD_TYPE?}" autogen.lastrun
    elif [ -f "${tb_PROFILE_DIR?}/branches/${B}/autogen" ] ; then
        cp "${tb_PROFILE_DIR?}/branches/${B}/autogen.lastrun" autogen.lastrun
    elif [ -f "${tb_PROFILE_DIR?}/autogen.lastrun_${tb_BUILD_TYPE?}" ] ; then
        cp "${tb_PROFILE_DIR?}/autogen.lastrun_${tb_BUILD_TYPE?}" autogen.lastrun
    elif [ -f "${tb_PROFILE_DIR?}/autogen.lastrun" ] ; then
        cp "${tb_PROFILE_DIR?}/autogen.lastrun" autogen.lastrun
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
                cp tb_${B?}_autogen.log "${TB_BIBISECT_DIR?}/."

                # Include the build, test logs.
                cp tb_${B?}_build.log "${TB_BIBISECT_DIR?}/."

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
    [ $V ] && echo "unlock ${lock_file?}.bibisect"
    [ $V ] && echo "unlock ${lock_file?}.bibisect"
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
    echo "[$(print_date) ${P?}] Error:" "$@" | tee -a ${tb_LOGFILE?}
    exit -1;
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

#
# Fetch a gerrit changeset and check it out
#
fetch_gerrit()
{
    GERRIT_PREV_B=`git branch | grep '^\*' | sed 's/^..//' | sed 's/\//_/g'`
    [ $V ] && echo "fetching gerrit path from ssh://${GERRIT_HOST?}/core ${GERRIT_TASK_REF}"
    git fetch -q ssh://${GERRIT_HOST?}/core ${GERRIT_TASK_REF}
    if [ "$?" != "0" ] ; then
        retval="3"
    else
        git checkout -q FETCH_HEAD || die "fatal error checking out gerrit ref"
        git submodule -q update
        [ $V ] && echo "fetched gerrit path from ssh://${GERRIT_HOST?}/core ${GERRIT_TASK_REF}"
        retval="0"
    fi
}

find_dev_install_location()
{
    find . -name opt -type d
}

generate_cgit_link()
{
    local line="$1"
    local repo=$(echo $line | cut -f 1 -d \:)
    local sha=$(echo $line | cut -f 2 -d \:)

    echo "<a href='http://cgit.freedesktop.org/libreoffice/${repo}/log/?id=$sha'>$repo</a>"
}

get_commits_since_last_good()
{
    local mode=$1
    local head=
    local repo=
    local sha=

    if [ -f "${TB_METADATA_DIR?}/${P?}_${B?}_last-success-git-head.txt" ] ; then
        head=$(head -n1 "${TB_METADATA_DIR?}/${P?}_${B?}_last-success-git-head.txt")
        repo=$(echo ${head?} | cut -d : -f 1)
        sha=$(echo ${head?} | cut -d : -f 2)
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
}

get_committers()
{
    echo "get_committers: $(get_commits_since_last_good people)" 1>&2
    get_commits_since_last_good people | sort | uniq | tr '\n' ','
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
    local p=$1
    local rc=0
    local config_file=
    local old_ccache_dir=

    if [ -z "$p" ] ; then
        die "A profile is needed to run: use -p or configure one"
    else
        tb_PROFILE_DIR="${tb_CONFIG_DIR?}/profiles/${p}"
        if [ ! -d "${tb_PROFILE_DIR}" ] ; then
            die "You need to configure the profile ${p} to use it"
        fi

        #save the current CCACHE_DIR setting
        if [ -n "${CCACHE_DIR}" ] ; then
            old_ccache_dir="${CCACHE_DIR?}"
            unset CCACHE_DIR
        fi
        config_file="${tb_PROFILE_DIR?}/config"
        if [ -f "${config_file?}" ] ; then
            source "${config_file?}"
        fi
        # global level phase override
        if [ -f "${tb_CONFIG_DIR?}/phases.sh" ] ; then
            source "${tb_CONFIG_DIR?}/phases.sh"
        fi
        # project level phase override
        if [ -f "${tb_PROFILE_DIR?}/phases.sh" ] ; then
            source "${tb_PROFILE_DIR?}/phases.sh"
        fi

        # if we have a CCACHE_DIR here, it has been set by
        # the profile. if we also haev a TB_CCACHE_SIZE
        # make sure the cache is as big as indicated
        # if CCACHE_DIR is not set, restaure the potential
        # previous value
        if [ -n "${CCACHE_DIR}" ] ; then
            if [ -n "${TB_CCACHE_SIZE}" ] ; then
                ccache -M "${TB_CCACHE_SIZE?}" > /dev/null
            fi
        else
            if [ -n "${old_ccache_dir}" ] ; then
                CCACHE="${old_ccache_dir?}"
            fi
        fi
    fi
}

log_msgs()
{
    echo "[$(print_date) ${P?}]" "$@" | tee -a ${tb_LOGFILE?}
}

prepare_git_repo_for_gerrit()
{
    if [ -z "$TB_BUILD_DIR" ] ; then
        TB_BUILD_DIR="${TB_GIT_DIR?}"
    fi
    pushd ${TB_GIT_DIR?} > /dev/null || die "Cannot cd to build dir : ${TB_GIT_DIR?}"
    [ $V ] && echo "fetching gerrit path from ssh://${TB_GERRIT_HOST?}/core ${GERRIT_TASK_REF}"

    (
        git clean -fd && git fetch -q ssh://${GERRIT_HOST?}/core ${GERRIT_TASK_REF}
        if [ "$?" = "0" ] ; then
            git checkout -q FETCH_HEAD
            git submodule -q update
        else
            exit -1
        fi
    ) 2>&1 > ${TB_BUILD_DIR}/error_log.log
    popd > /dev/null

    if [ "$?" != "0" ] ; then
        report_error owner "$(print_date)" error_log.log
        die "Cannot reposition repo ${TB_GIT_DIR} to the proper branch"
    fi

}

prepare_git_repo_for_tb()
{
    local remote_sha="$(cat "${TB_METADATA_DIR?}/${P}_${B?}_current-git-head.log")"
    local local_sha=
    local refspec=
    local remote_refspec=

    refspec="${B?}"
    if [ -n "${TB_BRANCH_LOCAL_REFSPEC}" ] ; then
        refspec="${TB_BRANCH_LOCAL_REFSPEC?}"
    fi

    remote_refspec="${B?}"
    if [ -n "${TB_BRANCH_REMOTE_REFSPEC}" ] ; then
        remote_refspec="${TB_BRANCH_REMOTE_REFSPEC?}"
    fi

    if [ -z "$TB_BUILD_DIR" ] ; then
        TB_BUILD_DIR="${TB_GIT_DIR?}"
    fi
    pushd ${TB_GIT_DIR?} > /dev/null || die "Cannot cd to build dir : ${TB_GIT_DIR?}"

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
        die "Cannot reposition repo ${TB_GIT_DIR} to the proper branch"
    fi
    popd > /dev/null

}

prepare_upload_manifest()
{
    local manifest_file="build_info.txt"

    echo "Build Info" > $manifest_file

    echo "tinderbox: administrator: ${TB_OWNER?}" >> $manifest_file
    echo "tinderbox: buildname: ${TB_NAME?}" >> $manifest_file
    echo "tinderbox: tree: ${tb_TINDERBOX_BRANCH?}" >> $manifest_file
    echo "tinderbox: pull time $(cat "${TB_METADATA_DIR?}/${P?}_${B?}_current-git-timestamp.log")" >> $manifest_file
    echo "tinderbox: git sha1s"  >> $manifest_file
    cat "${TB_METADATA_DIR?}/{P?}_${B?}_current-git-head.log"  >> $manifest_file
    echo ""  >> $manifest_file
    echo "tinderbox: autogen log"  >> $manifest_file
    cat tb_${P?}_${B?}_autogen.log  >> $manifest_file

}

print_date()
{
    date -u '+%Y-%m-%d %H:%M:%S'
}

print_local_date()
{
    date '+%Y-%m-%d %H:%M:%S'
}

position_bibisect_branch()
{
    pushd ${TB_BIBISECT_DIR?} > /dev/null
    git checkout -q ${B?}
    if [ "$?" -ne "0" ] ; then
        echo "Error could not position the bibisect repository to the branch $B" 1>&2
        exit 1;
    fi
    popd > /dev/null
}

push_bibisect()
{
    local curr_day=
    local last_day_upload=

    if [ ${TB_BIBISECT} = "1" -a -n "${tb_OPT_DIR}" ] ; then

        [ $V ] && echo "Push: bibisec builds enabled"
        curr_day=$(date -u '+%Y%j')
        last_day_upload="$(cat "${TB_METADATA_DIR?}/${P}_${B?}_last-bibisect-day.txt" 2>/dev/null)"
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

        echo "$curr_day" > "${TB_METADATA_DIR?}/${P}_${B?}_last-bibisect-day.txt"

    fi
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

    # Push build up to the project server (if enabled).
    [ $V ] && echo "Push: Nightly builds enabled"
    curr_day=$(date -u '+%Y%j')
    last_day_upload="$(cat "${TB_METADATA_DIR?}/${P}_${B?}_last-upload-day.txt" 2>/dev/null)"
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

    upload_time="$(cat "${TB_METADATA_DIR?}/${P?}_${B?}_current-git-timestamp.log")"
    ssh upload@gimli.documentfoundation.org "mkdir -p \"/srv/www/dev-builds.libreoffice.org/daily/${B?}/${TB_NAME?}/${upload_time?}\"" || return 1

    if [ -f config_host.mk ] ; then
        inpath=$(grep INPATH= config_host.mk | sed -e "s/.*=//")
    else
        return 1
    fi
    if [ -z "${inpath?}" -o ! -d "instsetoo_native/${inpath?}" ] ; then
        return 1
    fi
    pushd instsetoo_native/${inpath?} > /dev/null
    mkdir push 2>/dev/null || return 1
    stage="./push"
    tag="${B?}~${upload_time?}"

    for file in $(find . -name "*.dmg" -o -name '*.apk' -o -name "Lib*.tar.gz" -o -name "Lib*.exe" -o -name "Lib*.zip" -o -path '*/native/install/*.msi' | grep -v "/push/")
    do
        target=$(basename $file)
        target="${tag}_${target}"
        mv $file "$stage/$target"
    done;

    rsync --bwlimit=${TB_BANDWIDTH_LIMIT} -avPe ssh ${stage}/${tag}_* "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${B?}/${TB_NAME?}/${upload_time?}/" || return 1
    if [ "$?" == "0" ] ; then
        ssh upload@gimli.documentfoundation.org "cd \"/srv/www/dev-builds.libreoffice.org/daily/${B?}/${TB_NAME?}/\" && { rm current; ln -s \"${upload_time}\" current ; }"
    fi
    echo "$curr_day" > "${TB_METADATA_DIR?}/${P}_${B?}_last-upload-day.txt"
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

    local last_success=$(cat "${TB_METADATA_DIR?}/${P}_${B?}_last-success-git-timestamp.txt")
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

report_gerrit()
{
local log_type="$1"
local status="failed"
local gzlog=

    [ $V ] && echo "report to gerrit retval=${retval} log_type=${log_type}"
    if [ "$log_type" = "short"  -a "${R?}" = "0" ] ; then
        gzlog="tinder.log.gz"
        (
            echo "gerrit_task_ticket:$GERRIT_TASK_TICKET"
            echo "gerrit_task_branch:$GERRIT_TASK_BRANCH"
            echo "gerrit task_ref:$GERRIT_TASK_REF"
            echo ""
            echo "Build: OK"
            echo ""
            cat tb_${B}_autogen.log 2>/dev/null
        ) | gzip -c > "${gzlog}"
    else
        gzlog="tinder.log.gz"
        (
            echo "gerrit_task_ticket:$GERRIT_TASK_TICKET"
            echo "gerrit_task_branch:$GERRIT_TASK_BRANCH"
            echo "gerrit task_ref:$GERRIT_TASK_REF"
            echo ""
            if [ "${retval?}" = "0" ] ; then
                echo "Build: OK"
            else
                echo "Build: FAIL"
            fi
            echo ""
            cat tb_${B}_autogen.log tb_${B}_clean.log tb_${B}_build.log tb_${B}_tests.log 2>/dev/null
        ) | gzip -c > "${gzlog}"
    fi

    if [ "${R?}" = "0" ] ; then
        status="success"
    elif [ "${R?}" = "2" ] ; then
        status="canceled"
    fi
    log_msgs "Report Success for gerrit ref '$GERRIT_TASK_TICKET'."
    cat "${gzlog}" | ssh ${TB_GERRIT_HOST?} buildbot put --id ${TB_ID?} --ticket "${GERRIT_TASK_TICKET}" --status $status --log -

}


report_to_tinderbox()
{
    [ $V ] && echo "report_to_tinderbox status=$2"
    if [ -z "${tb_SEND_MAIL}" -o "${tb_SEND_MAIL}" = "none" -o -z "${TB_NAME}" ] ; then
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
            cat "${TB_METADATA_DIR?}/${P}_${B?}_current-git-timestamp.log"
            for cm in $(cat ${TB_METADATA_DIR?}/${P?}_${B?}_current-git-head.log) ; do echo "TinderboxPrint: $(generate_cgit_link ${cm})" ; done
            cat tb_${B?}_autogen.log tb_${B?}_clean.log tb_${B?}_build.log tb_${B?}_tests.log 2>/dev/null
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

rotate_logs()
{
    if [ "${R?}" = "0" ] ; then
        cp -f "${TB_METADATA_DIR?}/${P}_${B?}_current-git-head.log" "${TB_METADATA_DIR?}/${P}_${B?}_last-success-git-head.txt" 2>/dev/null
        cp -f "${TB_METADATA_DIR?}/${P}_${B?}_current-git-timestamp.log" "${TB_METADATA_DIR?}/${P}_${B?}_last-success-git-timestamp.txt" 2>/dev/null
    elif [ "${R}" != "2" ]; then # do not count abandonned false_negative loop as failure
        cp -f "${TB_METADATA_DIR?}/${P}_${B?}_current-git-head.log" "${TB_METADATA_DIR?}/${P}_${B?}_last-failure-git-head.txt" 2>/dev/null
        cp -f "${TB_METADATA_DIR?}/${P}_${B?}_current-git-timestamp.log" "${TB_METADATA_DIR?}/${P}_${B?}_last-failure-git-timestamp.txt" 2>/dev/null
    fi
}

rotate_branches()
{
    local top="$1"

    shift
    if [ -n "$1" ] ; then
        echo "$@ ${top}"
    else
        echo "$top"
    fi
}

#
# Main loop
#
run_loop()
{
local s=0

    check_branches_profile

    while true; do

        # Check for stop request
        if [ -f ${TB_METADATA_DIR?}/stop ] ; then
            break;
        else
            sleep ${s?}
        fi

        # Select the next task
        # this set tb_BUILD_TYPE and B
        select_next_task

        # based on the build type run the appropriate build
        case "$tb_BUILD_TYPE" in
            tb)
                run_one_tb
                s=${TB_POST_BUILD_DELAY?}
                ;;
            gerrit)
                run_one_gerrit
                s=${TB_POST_BUILD_DELAY?}
                ;;
            wait)
                log_msgs "Nothing to do. waiting ${TB_POLL_DELAY?} seconds."
                s=${TB_POLL_DELAY?}
                ;;
            *)
                die "Invalid next mode $tb_BUILD_TYPE."
                ;;
        esac

    done

    # if we were stopped by request, let's log that
    # clean the semaphore file
    if [ -f ${TB_METADATA_DIR?}/stop ] ; then
        log_msgs "Stoped by request"
        rm ${TB_METADATA_DIR?}/stop
    fi

}

#
# Run a gerrit build
#
# Run a a subshell to isolate Branch-level config
#
run_one_gerrit()
{
    R=0
    (
        # source branch-level configuration
        source_branch_level_config "${B?}" "gerrit"

        if [ -z "$TB_BUILD_DIR" ] ; then
            TB_BUILD_DIR="${TB_GIT_DIR?}"
        fi

        # clean-up the git repo associated with the
        # branch and checkout the target sha
        prepare_git_repo_for_gerrit

        # gerrit build are not incremental
        # always use all the phases
        local phase_list="autogen clean make test push"

        pushd ${TB_BUILD_DIR?} > /dev/null || die "Cannot cd to build dir : ${TB_BUILD_DIR?}"

        # run the build
        do_build ${phase_list?}

        # tell teh gerrit buildbot of the result of the build
        # R contain the overall result
        report_gerrit

        popd > /dev/null
        exit $R
    )
    R="$?"
}

#
# Run a tinderbox build
#
# Run as subshel to isolate Branch-level config
#
run_one_tb()
{
    R=0
    (
        source_branch_level_config "${B?}" "${tb_BUILD_TYPE?}"
        if [ -z "$TB_BUILD_DIR" ] ; then
            TB_BUILD_DIR="${TB_GIT_DIR?}"
        fi

        # for 'primer' build we expect the repo to be in a buildable
        # condition already
        if [ "${tb_ONE_SHOT?}" != "1" ] ; then
            prepare_git_repo_for_tb
        fi

        local last_checkout_date="$(cat "${TB_METADATA_DIR?}/${P}_${B?}_current-git-timestamp.log")"
        local phase_list
        local retry_count=3

        report_to_tinderbox "${last_checkout_date?}" "building" "no"


        if [ "$TB_INCREMENTAL" = "1" ] ; then
            phase_list="autogen make test push"
        else
            phase_list="autogen clean make test push"
        fi

        pushd ${TB_BUILD_DIR?} > /dev/null || die "Cannot cd to build dir : ${TB_BUILD_DIR?}"

        while [ "${phase_list}" != "" ] ; do

            do_build ${phase_list?}

            if [ "$R" = "0" ] ; then
                report_to_tinderbox "$last_checkout_date" "success" "yes"
                phase_list=
            elif [ "$R" = "2" ] ; then
                if [ "${tb_ONE_SHOT?}" != "1" ] ; then
                    report_to_tinderbox "${last_checkout_date?}" "fold" "no"
                fi
                log_msgs "False negative build, skip reporting"
                    # false negative does not need a full clean build, let's just redo make and after
                retry_count=$((retry_count - 1))
                if [ "$retry_count" = "0" ] ; then
                    phase_list=""
                    R=2
                else
                    phase_list="make test push"
                    R=0
                fi
            else
                printf "${tb_REPORT_MSGS?}:\n\n" > report_error.log
                echo "======" >> report_error.log
                if [ "${tb_REPORT_LOG?}" == "tb_${B}_build.log" ] ; then
                    tail -n1000 ${tb_REPORT_LOG?} >> report_error.log
                else
                    cat ${tb_REPORT_LOG?} >> report_error.log
                fi
                report_error committer "$last_checkout_date" report_error.log
                report_to_tinderbox "${last_checkout_date?}" "build_failed" "yes"
                phase_list=""
            fi
        done
        popd > /dev/null
        exit $R
    )
    R="$?"
    rotate_logs
}

#
# run a one-shot tb run
#
run_primer()
{
    check_branch_profile

    # as a special case the select_next_task
    # if tb_ONE_SHOT=1 return the first branch
    # of the slected list
    # a primer build build one and one branch only.
    select_next_task

    # as a special case tun_one_tb() does not reset the repo
    # do it will just build what is there.
    # it is the user responsability to make sure that the state
    # of the repo is correct.
    # the rational is to allow 'primer' build to be use
    # to test uncommited changes and/or local commit
    run_one_tb
}

#
# Select a gerrit task from
# the gerrit buildbot plugin
#
select_next_gerrit_task()
{
    local result
    local has_task

    [ $V ] && echo "Try to get a task for gerrit buildbot"

    tb_BUILD_TYPE="wait"
    GERRIT_TASK_TICKET=""
    GERRIT_TASK_BRANCH=""
    GERRIT_TASK_REF=""
    GERRIT_TASK_FEATURE=""
    result=$(ssh ${TB_GERRIT_HOST?} buildbot get -p core --id ${TB_ID?} -a ${tb_GERRIT_PLATFORM?} --format BASH ${tb_GERRIT_BRANCHES?})
    [ $V ] && echo "Get task result:${result}"

    has_task=$(echo "$result" | grep "^GERRIT_TASK_")
    if [ -n "${has_task}" ] ; then
        eval "${result}"
        if [ -z "${GERRIT_TASK_TICKET}" -o -z "${GERRIT_TASK_REF}" -o -z "${GERRIT_TASK_BRANCH}" ] ; then
            [ $V ] && echo "no valid task from gerrit buildbot"
        else
            tb_BUILD_TYPE="gerrit"
            B="${GERRIT_TASK_BRANCH?}"
            [ $V ] && echo "got task TASK_TICKET=$GERRIT_TASK_TICKET TASK_REF=$GERRIT_TASK_REF TASK_BRANCH=${B?} "
        fi
    else
        [ $V ] && echo "no task from gerrit buildbot"
    fi

}

#
# Select the next task to do
# either tb or gerrit depending
# on the mode of operation
#
select_next_task()
{

    if [ tb_MODE="tb" ] ; then
        select_next_tb_task
    elif [ tb_MODE="gerrit" ] ; then
        select_next_gerrit_task
    else
        if [ "${tb_NEXT_PRIORITY}" = "tb" ] ; then
            select_next_tb_task
            if [ "${tb_BUILD_TYPE?}" = "wait" ] ; then
                select_next_gerrit_task
            fi
        else
            select_next_gerrit_task
            if [ "${tb_BUILD_TYPE?}" = "wait" ] ; then
                select_next_tb_task
            fi
        fi

        # if we use a 'fair' priority
        # switch the order in which we try to get stuff
        if [ "${tb_PRIORITY?}" = "fair" ] ; then
            if [ "${tb_BUILD_TYPE?}" = "tb" ] ; then
                tb_NEXT_PRIORITY="gerrit"
            elif [ "${tb_BUILD_TYPE?}" = "gerrit" ] ; then
                tb_NEXT_PRIORITY="tb"
            fi
        fi
    fi
}

#
# Select a Tinderbox task
# by seraching for new commits
# on on of the branches under consideration
#
select_next_tb_task()
{
    local b
    local r

    tb_BUILD_TYPE="wait"
    for b in ${tb_TB_BRANCHES?} ; do
        if [ "${tb_ONE_SHOT?}" = "1" ] ; then
            B="${b?}"
            tb_BUILD_TYPE="tb"
            break
        else
            ( check_for_commit "$b" )
            r="$?"
            if [ ${r?} = 0 ] ; then
                B="${b?}"
                rotate_branches ${tb_TB_BRANCHES?}
                tb_BUILD_TYPE="tb"
                break
            fi
        fi
    done
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

    log_msgs "send mail to ${to?} with subject \"${subject?}\""
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

    tb_ONE_SHOT=

}

#
# Setup default at the profile level
#
# Based on the content of the profile
# setup some interna variable
# assign some default and
# do some other housekeeping
#
# Verify that mandatory profile
# variables are defined
setup_profile_defaults()
{
    local os

    if [  -n "${TB_LOGFILE}" ] ; then
        if [ ! -f "${TB_LOGFILE?}" ] ; then
            touch "${TB_LOGFILE?}" || die "Creating ${TB_LOGFILE?}"
        fi
        tb_LOGFILE="$TB_LOGFILES"
    fi

    if [ -z "{TB_METADATA_DIR}" ] ; then
        TB_METADATA_DIR="${tb_CONFIG_DIR?}/meta/"
    fi
    if [ ! -d ${TB_METADATA_DIR} ] ; then
        mkdir -p "${TB_METADATA_DIR?}" || die "Creating ${TB_METADATA_DIR?}"
    fi

    if [ -z "$TB_ID" ] ; then
        die "Error: TB_ID is required to be configured"
    fi

    if [ -z "${TB_OWNER}" ] ; then
        die "Error: TB_OWNER is required to be configured"
    fi

    if [ -z "${TB_NAME}" ] ; then
        die "TB_NAME is required to be configured"
    fi

    if [ -z "${tb_GERRIT_PLATFORM}" ] ; then
        os=$(uname)
        case "$os" in
            *Linux*)
                tb_GERRIT_PLATFORM="LINUX"
                ;;
            Darwin)
                tb_GERRIT_PLATFORM="MAC"
                ;;
            CYGWIN*)
                tb_GERRIT_PLATFORM="WINDOWS"
                ;;
        esac
    fi

    if [ -z "${tb_MODE}" ] ; then
        tb_MODE="${TB_DEFAULT_MODE:-tb}"
    fi

    if [ -z "${tb_BRANCHES}" ] ; then
        tb_BRANCHES="${TB_BRANCHES}"
        if [ -z "${tb_BRANCHES}" ] ; then
            log_msgs "TB_BRANCHES and -b not specified. Default to 'master'"
            tb_BRANCHES="master"
        fi
    fi
}

source_branch_level_config()
{
    local b="$1"
    local t="$2"

    if [ -f "${tb_PROFILE_DIR?}/branches/${b?}/config" ] ; then
        source "${tb_PROFILE_DIR?}/branches/${B?}/config"
    fi
    if [ -f "${tb_PROFILE_DIR?}/branches/${b?}/config_${t?}" ] ; then
        source "${tb_PROFILE_DIR?}/branches/${b?}/config_${t?}"
    fi
}

#
# Verify the coherence of the command line arguments
#
verify_command()
{
local rc

    case "$tb_MODE" in
        dual)
            if [ -z "$tb_GERRIT_PLATFORM" ] ; then
                die "tb_GERRIT_PLATFORM is required for mode involving gerrit"
            fi
            if [ -z "TB_DUAL_PRIORITY" ] ; then
                TB_DUAL_PRIORITY="fair"
            fi
            ;;
        gerrit)
            if [ -z "$tb_GERRIT_PLATFORM" ] ; then
                die "tb_GERRIT_PLATFORM is required for mode involving gerrit"
            fi
            ;;
        gerrit-patch)
            tb_SEND_MAIL="none"
            tb_PUSH_NIGHTLIES=0
            ;;
        tb)
            if [ "${tb_ONE_SHOT?}" = "1" ] ; then
                tb_SEND_MAIL="none"
                tb_BRANCHES=$(determine_current_branch ${tb_BRANCHES?})
                B=${tb_BRANCHES}
                if [ "${tb_PUSH_NIGHTLIES}" = "1" ] ; then
                    rm -f "${METADATA_DIR?}/${P?}_${B?}_last-upload-day.txt"
                fi
            fi
            ;;
        *)
            ;;
    esac

    if [ -z "$tb_SEND_MAIL" ] ; then
        tb_SEND_MAIL="${TB_SEND_MAIL}"
    fi
    # if we want email to be sent, we must make sure that the required parameters are set in the profile (or in the environment)
    case "$tb_SEND_MAIL" in
        all|tb|owner|debug|author)
            if [ -z "${TB_SMTP_HOST}" ] ; then
                die "TB_SMTP_HOST is required in the config to send email"
            fi
            if [ -z "${TB_SMTP_USER}" ] ; then
                echo "Warning: missing SMTPUSER (can work, depends on your smtp server)" 1>&2
            fi
            if [ -n "${TB_SMTP_USER}" -a -z "${TB_SMTP_PASSWORD}" ] ; then
                die "TB_SMTP_PASSWRD is required with TB_SMTP_USER set"
            fi
            if [ "$rc" != "0" ] ; then
                exit 1
            fi
            ;;
        none)
            ;;
        *)
            die "Invalid -m argument:${tb_SEND_MAIL}"
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
