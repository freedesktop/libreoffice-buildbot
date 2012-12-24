#!/usr/bin/sh
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
#   Stephan van den Akker
#
# For minor contributions see the git repository.
#
# Alternatively, the contents of this file may be used under the terms of
# either the GNU General Public License Version 3 or later (the "GPLv3+"), or
# the GNU Lesser General Public License Version 3 or later (the "LGPLv3+"),
# in which case the provisions of the GPLv3+ or the LGPLv3+ are applicable
# instead of those above.

source utls.sh

export OOO_EXIT_POST_STARTUP=1
export OOO_DISABLE_RECOVERY=1
OFFICEBIN="$1"

TESTDATE=$(date --rfc-3339=second)

if test "$2" = "--dev-build"; then
  TESTHASH=$(get_lo_commit_hash "$OFFICEBIN")
  TESTHASH=${TESTHASH:-"GIT_REPO_NOT_FOUND"}
else
  TESTHASH=$(get_lo_build);
fi

BUILD=$(get_lo_build)
DT=$(echo "$TESTDATE" | tr -s '\ \+\-\:' "_")

CG_LOG="logs/callgrind/cg-lo$BUILD-$DT"
PF_LOG="logs/loperf/pf-lo$BUILD-$DT.log"
CSV_LOG="logs/callgrind/cg-lo$BUILD"
ERR_LOG="logs/error.log"

mkdir -p logs/callgrind 2>&1 > /dev/null
mkdir -p logs/loperf    2>&1 > /dev/null

function launch {

    if test "$1" = ""; then
        valgrind --tool=callgrind --callgrind-out-file="$CG_LOG"_offload.log --simulate-cache=yes --dump-instr=yes  "$OFFICEBIN" --splash-pipe=0 --headless > /dev/null 2>&1
        echo -n "$CG_LOG"_offload.log
    else
        fn=${1#docs\/}
        valgrind --tool=callgrind --callgrind-out-file="$CG_LOG"_onload_"$fn".log --simulate-cache=yes --dump-instr=yes  "$OFFICEBIN" "$1" --splash-pipe=0 --headless > /dev/null 2>&1
        echo -n "$CG_LOG"_onload_"$fn".log
    fi

}

# Do a clean launch
echo "Start offload pvt..."
cur_log=$(launch)

# Mapping the data to array:
# 
# Ir Dr Dw I1mr D1mr D1mw I2mr D2mr D2mw
# offload[0] -> Ir
# offload[1] -> Dr
# offload[2] -> Dw 
# offload[3] -> I1mr
# offload[4] -> D1mr
# offload[5] -> D1mw
# offload[6] -> I2mr
# offload[7] -> D2mr
# offload[8] -> D2mw
offload_str=$(grep '^summary:' "$cur_log" | sed s/"summary: "//)
offload=($offload_str)

# Populate offload to PF_LOG
echo "Ir Dr Dw I1mr D1mr D1mw I2mr D2mr D2mw" | tee -a "$PF_LOG"
echo "######################################" | tee -a "$PF_LOG"
echo | tee -a "$PF_LOG"
echo "Offload:" | tee -a "$PF_LOG"
echo "$offload_str" | tee -a "$PF_LOG"
echo | tee -a "$PF_LOG"

# Loaded launch one by one
echo "Start onload pvt..."
find docs -type f |  grep -Ev "\/\." | while read f; do
    cur_log=$(launch "$f")
    # Mapping the data to array:
    # 
    # onload[0] -> Ir
    # onload[1] -> Dr
    # onload[2] -> Dw 
    # onload[3] -> I1mr
    # onload[4] -> D1mr
    # onload[5] -> D1mw
    # onload[6] -> I2mr
    # onload[7] -> D2mr
    # onload[8] -> D2mw

    onload_str=$(grep '^summary:' "$cur_log" | sed s/"summary: "//)
    onload=($onload_str)
    # Populate onload to PF_LOG
    echo "Load: $f" | tee -a "$PF_LOG"
    echo "$onload_str" | tee -a "$PF_LOG"    
    
    #Construct the csv file name
    CSV_FN="$CSV_LOG"_onload_"${f#docs\/}".csv

#   echo "$TESTDATE" | tr -d "\n" >> "$CSV_FN"
    
    echo -n "$TESTDATE"$'\t'"$TESTHASH" >> "$CSV_FN"

    # Populate onload delta to PF_LOG and CSV_FN
    for i in $(seq 0 8); do
        onload_delta[$i]=$(expr ${onload[$i]} - ${offload[$i]})
        echo -n ${onload_delta[$i]} " " | tee -a "$PF_LOG"
        echo -n $'\t' ${onload_delta[$i]} >> "$CSV_FN"
    done
    
    echo | tee -a "$PF_LOG"
    echo | tee -a "$PF_LOG"
    
    echo >> "$CSV_FN"
done

# Regression check
echo "Regression Status:" | tee -a "$PF_LOG"
echo "-----------------" | tee -a "$PF_LOG"

find $(dirname $(readlink -f "$PF_LOG")) -type f | grep -v "$PF_LOG" | grep log$ | while read rf; do
    
    check_regression "$PF_LOG" "$rf" | tee -a "$PF_LOG"

done

grep '^Regression found!$' "$PF_LOG" > /dev/null || echo "Congratulations, no regression found!" | tee -a "$PF_LOG"
