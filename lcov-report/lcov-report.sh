#!/bin/sh
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


init()
{ 
if [ "$SRC_DIR" = "/" -o "$TRACEFILE_DIR" = "/" -o "$HTML_DIR" = "/" ]
then
	echo "ERROR: Dont use the root '/' directory for storage." >&2
	exit 1
fi

if [ ! -d "$SRC_DIR" ]
then
	echo "ERROR: Failed to locate directory $SRC_DIR." >&2
	exit 1
fi

rm -rf "$TRACEFILE_DIR" "$HTML_DIR"

mkdir "$TRACEFILE_DIR"
if [ "$?" != "0" ]
then
	echo "ERROR: Failed to create directory $TRACEFILE_DIR." >&2
	exit 1
fi

mkdir "$HTML_DIR"
if [ "$?" != "0" ]
then
	echo "ERROR: Failed to create directory $HTML_DIR." >&2
	exit 1
fi

if [ ! -f "$TEST_CMDS_FILE" ]
then
	echo "ERROR: Failed to find test command file $TEST_CMDS_FILE." >&2
	exit 1
fi
}

lcov_cleanup()
{
lcov --zerocounters --directory "$SRC_DIR"
}

source_build()
{
cd "$SRC_DIR"
make distclean
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo "ERROR: make distclean failed with exitcode $MY_EXITCODE." >&2
	exit "$MY_EXITCODE"
fi

./autogen.sh

LDFLAGS+='-fprofile-arcs' CFLAGS+='-fprofile-arcs -ftest-coverage' CXXFLAGS+='-fprofile-arcs -ftest-coverage' CPPFLAGS+='-fprofile-arcs -ftest-coverage' ./configure --disable-online-update --without-system-libs --without-system-headers
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo "ERROR: configure failed with exitcode $MY_EXITCODE." >&2
	exit "$MY_EXITCODE"
fi

make build-nocheck
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo "ERROR: make build-nocheck failed with exitcode $MY_EXITCODE." >&2
	exit "$MY_EXITCODE"
fi
}

lcov_tracefile_baseline()
{
lcov --rc geninfo_auto_base=1 --no-external --capture --initial --directory "$SRC_DIR" --output-file "$TRACEFILE_DIR"/lcov_base.info
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo "ERROR: tracefile $TRACEFILE_DIR/lcov_base.info generation failed with exitcode $MY_EXITCODE." >&2
	exit "$MY_EXITCODE"
fi
}

run_tests()
{
/bin/sh "$TEST_CMDS_FILE"
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo "ERROR: failed to run tests from testfile $TEST_CMDS_FILE with exitcode $MY_EXITCODE." >&2
	exit "$MY_EXITCODE"
fi
}


lcov_tracefile_tests()
{
lcov --rc geninfo_auto_base=1 --no-external --capture --directory "$SRC_DIR" --output-file "$TRACEFILE_DIR"/lcov_test.info
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo "ERROR: tracefile $TRACEFILE_DIR/lcov_test.info generation failed with exitcode $MY_EXITCODE." >&2
	exit "$MY_EXITCODE"
fi
}

lcov_tracefile_join()
{
lcov --rc geninfo_auto_base=1 --add-tracefile "$TRACEFILE_DIR"/lcov_base.info --add-tracefile "$TRACEFILE_DIR"/lcov_test.info --output-file "$TRACEFILE_DIR"/lcov_total.info
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo "ERROR: tracefile generation $TRACEFILE_DIR/lcov_total.info failed with exitcode $MY_EXITCODE." >&2
	exit "$MY_EXITCODE"
fi
}

lcov_tracefile_cleanup()
{
lcov --rc geninfo_auto_base=1 --remove "$TRACEFILE_DIR"/lcov_total.info  "/usr/include/*" "/usr/lib/*" "$SRC_DIR/*/UnpackedTarball/*" "$SRC_DIR/workdir/*" "$SRC_DIR/instdir/*" "$SRC_DIR/external/*" -o "$TRACEFILE_DIR"/lcov_filtered.info
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo "ERROR: tracefile generation $TRACEFILE_DIR/lcov_filtered.info failed with exitcode $MY_EXITCODE." >&2
	exit "$MY_EXITCODE"
fi
}

lcov_mkhtml()
{
cd "$SRC_DIR"
if [ ! -d "$SRC_DIR"/.git ]
then
	echo "ERROR: $SRC_DIR is not a git repository." >&2
	exit 1
fi

COMMIT_SHA1=$(git log --date=iso | head -3 | awk '/^commit/ {print $2}')
COMMIT_DATE=$(git log --date=iso | head -3 | awk '/^Date/ {print $2}')
COMMIT_TIME=$(git log --date=iso | head -3 | awk '/^Date/ {print $3}')

mkdir "$HTML_DIR"/master~"$COMMIT_DATE"_"$COMMIT_TIME"
MY_EXITCODE=$?
if [ ! -d "$HTML_DIR"/master~"$COMMIT_DATE"_"$COMMIT_TIME" ]
then
	echo >&2 ERROR: failed to create subdirectory in $HTML_DIR/master~"$COMMIT_DATE"_"$COMMIT_TIME" with exitcode $MY_EXITCODE
	exit "$MY_EXITCODE"
fi

genhtml --rc geninfo_auto_base=1 --prefix "$SRC_DIR" --ignore-errors source "$TRACEFILE_DIR"/lcov_filtered.info --legend --title "commit $COMMIT_SHA1" --output-directory="$HTML_DIR"/master~"$COMMIT_DATE"_"$COMMIT_TIME"
MY_EXITCODE=$?
if [ "$MY_EXITCODE" != "0" ]
then
	echo >&2 ERROR: Generation of html files in $HTML_DIR/master~"$COMMIT_DATE"_"$COMMIT_TIME" failed with exitcode $MY_EXITCODE.
	exit "$MY_EXITCODE"
fi
}

usage()
{
	echo >&2 "Usage: lcov-report.sh [-b] -c [FILE] -s [DIRECTORY] -t [DIRECTORY] -w [DIRECTORY]
	-b	build libreoffice sources
	-c	file containing test commands to run
	-s	source code directory
	-t 	tracefile directory
	-w 	html (www) directory"
	exit 1
}

#
# Main
#

if [ "$#" = "0" ]
then
	usage
fi

while getopts ":s:t:w:c:b" opt
do
	case $opt in
		s)
			export SRC_DIR="$OPTARG"
			;;
		t)
			export TRACEFILE_DIR="$OPTARG"
			;;
		w)
			export HTML_DIR="$OPTARG"
			;;
		b)
			export SOURCE_BUILD=TRUE
			;;
		c)
			export TEST_CMDS_FILE="$OPTARG"
			;;
		*)
			usage
			;;
	esac
done


init

lcov_cleanup

if [ "$SOURCE_BUILD" = "TRUE" ]
then
	source_build
fi

lcov_tracefile_baseline

run_tests

lcov_tracefile_tests
lcov_tracefile_join
lcov_tracefile_cleanup

lcov_mkhtml

