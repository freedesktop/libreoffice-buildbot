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
    if [ "${retval}" = "0" ] ; then
        if ! $NICE $WATCHDOG ${MAKE?} -s $target >tb_${B}_build.log 2>&1 ; then
            report_log=tb_${B}_build.log
            report_msgs="build failed - error is:"
            retval=1
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
    fi
}

# Push the data into the bibisect repository.
do_bibisect_push()
{
    [ $V ] && echo "do_bibisect_push() started"

    if [ "${retval}" != "0" ] ||
       [ $PUSH_TO_BIBISECT_REPO != "1" ] ; then
        return 0;
    fi

    # BUILDCOMMIT contains the sha1 of the current commit used in the
    # build. We can't set this variable in tinbuild2, because it needs
    # to be updated for each new build. We could set it in an earlier
    # phase, but because tinbuild allows functions to be replaced, we
    # have no guarantee that it would be properly set when we enter
    # do_bibisect_push().
    cd $BUILDDIR
    BUILDCOMMIT=`git rev-list -1 HEAD`
    LATEST_BIBISECT_COMMIT=
    OPTDIR=

    # Error-out if local bibisect repository does not exist.
    if [ ! -d "${ARTIFACTDIR}/.git" ] ; then
        report_log=tb_${B}_bibisect.log
        report_msgs="Bibisect: '$ARTIFACTDIR' is not a git repository."
        retval=1
        return;
    fi

    # Make sure that
    # 1) The local bibisect repo is up to date, and
    # 2) That the latest build in the bibisect repo is of an
    #    ancestor commit to BUILDCOMMIT (i.e. we're going forward
    #    and we're on the right branch)
    [ $V ] && echo "Bibisect repo exists; updating from remote"
    cd $ARTIFACTDIR
    # Fetch isn't very verbose, so we'll keep its output for now.
    git fetch
    git pull -q

    if [ -f "commit.hash" ] ; then
        LATEST_BIBISECT_COMMIT=$(<commit.hash)
    fi

    cd $BUILDDIR
    if [ -z "$LATEST_BIBISECT_COMMIT" ] ; then
        # If LATEST_BIBISECT_COMMIT is empty, then this is the first
        # build added to the bibisect repository and there's no
        # need to check commit order.
        echo "Bibisect: Empty bibisect repository detected."
    elif [ "$BIBISECT_TEST" = "1" ] ; then
        echo "Bibisect: TEST: Skipping commit checks."
    elif [ "$LATEST_BIBISECT_COMMIT" = "$BUILDCOMMIT" ] ; then
        # If we've already pushed this build into the bibisect
        # repository, skip the rest of the bibisect phase and continue
        # with the next commit.
        echo "Bibisect: WARNING: Build of commit '$BUILDCOMMIT' already in repository; skipping rest of bibisect step"
        return 0;
    elif [ -z "`git rev-list --boundary ${LATEST_BIBISECT_COMMIT}..${BUILDCOMMIT}`" ] ; then
        report_log=tb_${B}_bibisect.log
        report_msgs="Latest bibisect commit '$LATEST_BIBISECT_COMMIT' is not an ancestor of current build commit '$BUILDCOMMIT'."
        retval=1
        return;
    fi

    [ $V ] && echo "Bibisect: Build commit verified monotonic WRT repo."

    # Get the build into the local bibisect repository.
    format_build_and_copy_into_repository
    if [ "${retval}" != "0" ] ; then
        return;
    fi

    # Create additional files for bibisect.

    # The commitmsg is a concatenation of short and long logs.
    [ $V ] && echo "Bibisect: Create commitmsg"
    git log -1 --pretty=format:"source-hash-%H%n%n" $BUILDCOMMIT > ${ARTIFACTDIR}/commitmsg
    git log -1 --pretty=fuller $BUILDCOMMIT >> ${ARTIFACTDIR}/commitmsg

    [ $V ] && echo "Bibisect: Include interesting logs/other data"
    # Include the autogen log.
    # (Even with a failed build, this should be properly overwritten by
    #  the next build)
    cp tb_${B}_autogen.log $ARTIFACTDIR

    # Include the build, test logs.
    cp tb_${B}_build.log $ARTIFACTDIR
    #cp tb_${B}_tests.log $ARTIFACTDIR

    # Make it easy to grab the commit id.
    echo $BUILDCOMMIT > ${ARTIFACTDIR}/commit.hash

    # Commit build to the local repo and push to the remote.
    [ $V ] && echo "Bibisect: Committing to local bibisect repo"
    cd $ARTIFACTDIR
    git add *
    git commit -q --file=commitmsg
    [ $V ] && echo "Bibisect: Pushing to remote bibisect repo"
    git push -q

    cd $BUILDDIR

    [ $V ] && echo "Bibisect: complete"
    return 0;
}

do_push()
{
    [ $V ] && echo "Push: phase starting"
    local curr_day=

    if [ "${retval}" != "0" ] ; then
        return 0;
    fi

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

    # Push build into the bibisect repository (if enabled).
    do_bibisect_push

    # Push build up to the project server (if enabled).
    if [ "$PUSH_NIGHTLIES" = "1" ] ; then
        [ $V ] && echo "Push: Nightly builds enabled"
        prepare_upload_manifest
        ${BIN_DIR?}/push_nightlies.sh $push_opts -t "$(cat "${METADATA_DIR?}/tb_${B}_current-git-timestamp.log")" -n "$TINDER_NAME" -l "$BANDWIDTH"
        # If we had a failure in pushing the build up, return
        # immediately (making sure we do not mark this build as the
        # last uploaded daily build).
        if [ "$?" != "0" ] ; then
            return 0;
        fi
    fi

    echo "$curr_day" > "${METADATA_DIR?}/tb_${B}_last-upload-day.txt"
    return 0;
}
