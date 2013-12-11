#!/bin/bash
#
# Helper script to run the LibreOffice executable in a bibisect repo.
#  - Robinson Tryon <qubit@runcibility.com>
#  - Miroslaw Zalewski <miniopl@pczta.onet.pl>
#
# This script does a little magic behind the scenes to improve the
# bibisect experience:
#   * Uses (and clears) alternate user profile location
#     * Keeps tester's regular LO profile safe
#     * Produces more consistent, reproducible results
#

echo "-----------------------------------------------"
echo "  Welcome to the Wonderful World of Bibisect!"
echo "-----------------------------------------------"
echo ""

# Choose a profile directory inside /tmp.
export BIBISECT_PROFILE_DIR=/tmp/libreoffice-bibisect

# Make sure to clear the profile directory (in case we've previously
# used it).
rm -rf $BIBISECT_PROFILE_DIR

echo "Starting LibreOffice"
./opt/program/soffice -env:UserInstallation=file://$BIBISECT_PROFILE_DIR &


echo "----------------------"
echo "  Helper Script Done"
echo "----------------------"
