#!/usr/bin/env bash
# -*- tab-width : 4; indent-tabs-mode : nil -*-
#
# This file is part of the LibreOffice project.
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Functions
#

#
# Display an error message and exit
#
die()
{
    echo "Error:" "$@" >&2
    exit -1;
}

init()
{
    if [ "${SOURCE_COMPILE?}${AFTER?}${BEFORE?}" != "TRUE" ] ; then
        die "You can only supply one of '-a', '-b' or '-c' simultaneously."
    fi

    if [ -n "${SRC_DIR?}" ] ; then
        if [ "${SRC_DIR?}" = "${BUILD_DIR?}" ] ; then
            die "Cannot set the source directory to the same value as the build directory."
        fi

        if [ ! -d "${SRC_DIR?}" ] ; then
            die "Failed to locate source code directory $SRC_DIR."
        else
            SRC_DIR=$(readlink -f "${SRC_DIR?}")
        fi

        if [ ! -d "${SRC_DIR?}/.git" ] ; then
            die "${SRC_DIR?} is not a git repository."
        fi

    fi

    if [ "${AFTER?}" = "TRUE" ] ; then
        if [ -z "${HTML_DIR?}" ] ; then
            die  "When specifying '-a', you also need to specify '-w'."
        fi

        if [ -z "${BUILD_DIR?}" ] ; then
            die "When specifying '-a', you also need to specify '-C'."
        fi

        if [ -z "${SRC_DIR?}" ] ; then
            die "When specifying '-a', you also need to specify '-s'."
        fi

        if [ ! -d "${TRACEFILE_DIR?}" ] ; then
            die "Failed to locate tracefile directory ${TRACEFILE_DIR?}."
        fi

        if [ ! -d "${HTML_DIR?}" ] ; then
            mkdir "${HTML_DIR?}" || die "Failed to create html directory ${HTML_DIR?}."
            HTML_DIR=$(readlink -f "${HTML_DIR?}")
        else
            rm -rf "${HTML_DIR?}"
            mkdir "${HTML_DIR?}" || die "Failed to create html directory ${HTML_DIR?}."
            HTML_DIR=$(readlink -f "${HTML_DIR?}")
        fi
    fi

    if [ "${BEFORE?}" = "TRUE" -o "${AFTER?}" = "TRUE" ] ; then
        if [ -z "${TRACEFILE_DIR?}" ] ; then
            die "When specifying '-a' or '-b', you also need to specify '-t'."
        fi

        if [ -z "${TEST_NAME?}" ] ; then
            die "When specifying '-a' or '-b', you also need to specify '-d'."
        fi

        if [ -z "${SRC_DIR?}" ] ; then
            die "When specifying '-a', you also need to specify '-s'."
        fi
    fi

    if [ "${BEFORE?}" = "TRUE" ] ; then
        if [ ! -d "${TRACEFILE_DIR?}" ] ; then
            mkdir "${TRACEFILE_DIR?}" || die "Failed to create tracefile directory ${TRACEFILE_DIR?}."
            TRACEFILE_DIR=$(readlink -f "${TRACEFILE_DIR?}")
        else
            rm -rf "${TRACEFILE_DIR?}"
            mkdir "${TRACEFILE_DIR?}" || die "Failed to create tracefile directory ${TRACEFILE_DIR?}."
            TRACEFILE_DIR=$(readlink -f "${TRACEFILE_DIR?}")
        fi
    fi

    if [ "${SOURCE_COMPILE?}" = "TRUE" ] ; then
        if [ -z "${BUILD_DIR?}" ] ; then
            die "When specifying '-c', you also need to specify '-C'."
        fi

        if [ -z "${SRC_DIR?}" ] ; then
            die "When specifying '-c', you also need to specify '-s'."
        fi
        if [ ! -d "$BUILD_DIR" ] ; then
            mkdir "$BUILD_DIR" || die "Failed to create source compile directory $BUILD_DIR."
            BUILD_DIR=$(readlink -f "${BUILD_DIR?}")
        else
            rm -rf "$BUILD_DIR"
            mkdir "$BUILD_DIR" || die "Failed to create source compile directory $BUILD_DIR."
            BUILD_DIR=$(readlink -f "${BUILD_DIR?}")
        fi
    fi
}

lcov_cleanup()
{
    lcov --zerocounters --directory "${BUILD_DIR?}"
}

source_build()
{
    cd "${BUILD_DIR?}"

    LDFLAGS+='-fprofile-arcs' CFLAGS+='-fprofile-arcs -ftest-coverage' CXXFLAGS+='-fprofile-arcs -ftest-coverage' CPPFLAGS+='-fprofile-arcs -ftest-coverage' \
    "${SRC_DIR?}/autogen.sh" --enable-python=internal --disable-online-update --without-system-libs --without-system-headers \
    || die "autogen.sh failed."

    gb_GCOV=YES make build-nocheck || die "make build-nocheck failed."

    cd -
}

lcov_tracefile_baseline()
{
    lcov --rc geninfo_auto_base=1 --capture --initial --directory "${BUILD_DIR?}" --output-file "${TRACEFILE_DIR?}/lcov_base.info" --test-name "${TEST_NAME?}" \
    || die "Tracefile ${TRACEFILE_DIR?}/lcov_base.info generation failed."
}

lcov_tracefile_tests()
{
    lcov --rc geninfo_auto_base=1 --capture --directory "${BUILD_DIR?}" --output-file "${TRACEFILE_DIR?}/lcov_test.info" --test-name "${TEST_NAME?}" \
    || die "Tracefile ${TRACEFILE_DIR?}/lcov_test.info generation failed."
}

lcov_tracefile_join()
{
    lcov --rc geninfo_auto_base=1 --add-tracefile "${TRACEFILE_DIR?}/lcov_base.info" \
    --add-tracefile "${TRACEFILE_DIR?}/lcov_test.info" --output-file "${TRACEFILE_DIR?}/lcov_total.info" --test-name "${TEST_NAME?}" \
    || die "Tracefile generation $TRACEFILE_DIR/lcov_total.info failed."
}

lcov_tracefile_cleanup()
{
    lcov --rc geninfo_auto_base=1 --remove "${TRACEFILE_DIR?}/lcov_total.info" \
    "/usr/include/*" "/usr/lib/*" "${SRC_DIR?}/*/UnpackedTarball/*" "${SRC_DIR?}/workdir/*" \
    "${BUILD_DIR?}/workdir/*" "${SRC_DIR?}/instdir/*" "${SRC_DIR?}/external/*" \
    -o "${TRACEFILE_DIR?}/lcov_filtered.info" --test-name "${TEST_NAME?}" \
    || die "tracefile generation ${TRACEFILE_DIR?}/lcov_filtered.info failed."
}

lcov_mkhtml()
{
    mkdir "${HTML_DIR?}/master~${COMMIT_DATE?}_${COMMIT_TIME?}" || die "Failed to create subdirectory in ${HTML_DIR?}/master~${COMMIT_DATE?}_${COMMIT_TIME?}"

    genhtml --rc geninfo_auto_base=1 --prefix "${SRC_DIR?}" --ignore-errors source "${TRACEFILE_DIR?}/lcov_filtered.info" \
    --legend --title "${TEST_NAME?}" --rc genhtml_desc_html=1 \
    --output-directory="${HTML_DIR?}/master~${COMMIT_DATE?}_${COMMIT_TIME?}" --description-file "${TRACEFILE_DIR?}/${DESC_FILE?}" \
    || die "ERROR: Generation of html files in ${HTML_DIR?}/master~${COMMIT_DATE?}_${COMMIT_TIME?} failed."
}

lcov_get_commit()
{
    cd "${SRC_DIR?}"

    COMMIT_SHA1=$(git log --date=iso | head -3 | awk '/^commit/ {print $2}')
    COMMIT_DATE=$(git log --date=iso | head -3 | awk '/^Date/ {print $2}')
    COMMIT_TIME=$(git log --date=iso | head -3 | awk '/^Date/ {print $3}')

    cd -
}

lcov_mk_desc()
{
    echo "TN: ${TEST_NAME?}" > "${TRACEFILE_DIR?}/${DESC_FILE?}"
    echo "TD: Commit SHA1: ${COMMIT_SHA1?} <br>" >> "${TRACEFILE_DIR?}/${DESC_FILE?}"
    echo "TD: Commit DATE: ${COMMIT_DATE?} ${COMMIT_TIME?} <br>" >> "${TRACEFILE_DIR?}/${DESC_FILE?}"
    echo "TD: Source Code Directory: ${SRC_DIR?} <br>" >> "${TRACEFILE_DIR?}/${DESC_FILE?}"
}

usage()
{
    echo >&2 "Usage: lcov-report.sh [-a|-b|-c] -s [DIRECTORY] -C [DIRECTORY] -t [DIRECTORY] -w [DIRECTORY] -d "test description"
        -b    run lcov commands before your tests
        -a    run lcov commands after your tests
        -c    compile libreoffice sources
        -C    build directory to compile libreoffice sources in
        -s    source code directory
        -t    tracefile directory
        -w    html (www) directory
        -d    description of test that was ran"
    exit 1
}

#
# Main
#

SOURCE_COMPILE=
BEFORE=
AFTER=
SRC_DIR=
TRACEFILE_DIR=
HTML_DIR=
BUILD_DIR=
COMMIT_SHA1=
COMMIT_DATE=
COMMIT_TIME=
TEST_NAME=
DESC_FILE=descfile.desc

if [ "$#" = "0" ] ; then
    usage
fi

while getopts ":s:t:w:C:d:abc" opt ; do
    case "$opt" in
    s)
        SRC_DIR="${OPTARG?}"
        ;;
    t)
        TRACEFILE_DIR="${OPTARG?}"
        ;;
    w)
        HTML_DIR="${OPTARG?}"
        ;;
    c)
        SOURCE_COMPILE=TRUE
        ;;
    C)
        BUILD_DIR="${OPTARG?}"
        ;;
    b)
        BEFORE=TRUE
        ;;
    a)
        AFTER=TRUE
        ;;
    d)
        TEST_NAME="${OPTARG?}"
        ;;
    *)
        usage
        ;;
    esac
done

init

if [ "${BEFORE?}" = "TRUE" ] ; then
    lcov_cleanup
    lcov_get_commit
    lcov_tracefile_baseline
    lcov_mk_desc
fi

if [ "${SOURCE_COMPILE?}" = "TRUE" ] ; then
    source_build
fi

if [ "${AFTER?}" = "TRUE" ] ; then
    lcov_get_commit
    lcov_tracefile_tests
    lcov_tracefile_join
    lcov_tracefile_cleanup
    lcov_mkhtml
fi
