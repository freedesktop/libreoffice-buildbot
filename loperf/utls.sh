#!/usr/bin/env bash
# Version: MPL 1.1 / GPLv3+ / LGPLv3+
#
# The contents of this file are subject to the Mozilla Public License Version
# 1.1 (the "License"); you may not use this file except in compliance with
# the License or as specified alternatively below. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS IS" basis,
# WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
# for the specific language governing rights and limitations under the
# License.
#
# Major Contributor(s):
#
#   Yifan Jiang <yifanj2007@gmail.com>
#   Stephan van den Akker <stephanv778@gmail.com>
#
# For minor contributions see the git repository.
#
# Alternatively, the contents of this file may be used under the terms of
# either the GNU General Public License Version 3 or later (the "GPLv3+"), or
# the GNU Lesser General Public License Version 3 or later (the "LGPLv3+"),
# in which case the provisions of the GPLv3+ or the LGPLv3+ are applicable
# instead of those above.

function get_lo_version {

    VERSIONRC_FN=$(echo -n $(echo -n "$1" | sed 's/soffice.*//')versionrc)
    LOGITDIR=$(echo -n $(echo -n "$1" | sed 's/core.*//')core/.git)

    version=$(git --git-dir="$LOGITDIR" rev-parse HEAD 2> /dev/null)

    if test "$version" = ""; then
        version=$(sed -nr 's/buildid=(.+)/\1/p' "$VERSIONRC_FN" 2> /dev/null)
        if test "$version" = ""; then
            version=$(echo -n $(echo $("$1" --version) | sed s/"LibreOffice "//))
            if test "$version" = ""; then
                version="unknown_version"
            fi
        fi
    fi

    echo -n "$version"

}


# A lovely script to compare versions from fgm/stackoverflow:)
# http://stackoverflow.com/questions/3511006/how-to-compare-versions-of-some-products-in-unix-shell
function compareversion () {

  typeset    IFS='.'
  typeset -a v1=( $1 )
  typeset -a v2=( $2 )
  typeset    n diff

  for (( n=0; n<4; n+=1 )); do
    diff=$((v1[n]-v2[n]))
    if [ $diff -ne 0 ] ; then
      [ $diff -le 0 ] && echo '-1' || echo '1'
      return
    fi
  done
  echo  '0'

}
