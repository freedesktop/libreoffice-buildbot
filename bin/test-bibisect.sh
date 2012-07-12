#!/usr/bin/env bash
#
# Copyright (c) 2012 Robinson Tryon <qubit@runcibility.com>
# License: GPLv3+
#
# Test file for verifying the push-to-bibisect-repo functionality.

# Set the proper tinder name/profile name here:
# (Bob the Builder, etc..)
PROFILE_NAME="bob"

echo "TEST for bibisect"

BIN_DIR=$(dirname "$0")
echo BIN_DIR is $BIN_DIR

report_log=
report_msgs=
retval=0
V=1

B="master"
PUSH_TO_BIBISECT_REPO=1
BUILDDIR=`pwd`
ARTIFACTDIR="${BUILDDIR}/../bibisect-repository"
BUILDCOMMIT=`git rev-list -1 HEAD`
BIBISECT_TEST=1

source ${BIN_DIR?}/tinbuild_phases.sh
echo "tinbuild_phases.sh sourced"

source ${BIN_DIR?}/tinbuild_internals.sh
echo "tinbuild_internals.sh sourced"

do_bibisect_push

echo "do_bibisect_push finished"

if [ $retval != "0" ] ; then
  echo "Error encountered: $return"
  echo "Messages: ${report_msgs?}"
  echo "----------"
  echo "Log: ${report_log?}"
fi

echo "TEST for bibisect finished"