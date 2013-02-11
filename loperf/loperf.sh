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

source utls.sh

export OOO_EXIT_POST_STARTUP=1
export OOO_DISABLE_RECOVERY=1
OFFICEBIN="$1"

TESTDATE=$(date --rfc-3339=second)

BUILD_ID=$(get_lo_build_id "$OFFICEBIN")
BUILD_ID=${BUILD_ID:-"BUILD_ID_NOT_FOUND"}

LOVERSION=$(get_lo_version "$OFFICEBIN")
DT=$(echo "$TESTDATE" | tr -s '\ \+\-\:' "_")

CG_LOG="logs/callgrind/cg-lo$LOVERSION-$DT"
PF_LOG="logs/loperf/pf-lo$LOVERSION-$DT.log"
CSV_LOG="logs/callgrind/cg-lo$LOVERSION"
ERR_LOG="logs/error.log"

mkdir -p logs/callgrind 2>&1 > /dev/null
mkdir -p logs/loperf    2>&1 > /dev/null

function launch {

    if test "$1" = ""; then
        valgrind --tool=callgrind --callgrind-out-file="$CG_LOG"_offload.log --simulate-cache=yes --dump-instr=yes --collect-bus=yes --branch-sim=yes "$OFFICEBIN" --splash-pipe=0 --headless > /dev/null 2>&1
        echo -n "$CG_LOG"_offload.log
    else
        fn=${1#docs\/}
        valgrind --tool=callgrind --callgrind-out-file="$CG_LOG"_onload_"$fn".log --simulate-cache=yes --dump-instr=yes --collect-bus=yes --branch-sim=yes "$OFFICEBIN" "$1" --splash-pipe=0 --headless > /dev/null 2>&1
        echo -n "$CG_LOG"_onload_"$fn".log
    fi
}

# Do a clean launch
echo "Start offload pvt..."
cur_log=$(launch)

# Mapping the data to array:
#
# offload[0] -> Ir
# offload[1] -> Dr
# offload[2] -> Dw
# offload[3] -> I1mr
# offload[4] -> D1mr
# offload[5] -> D1mw
# offload[6] -> ILmr
# offload[7] -> DLmr
# offload[8] -> DLmw
# offload[9] -> Bc
# offload[10] -> Bcm
# offload[11] -> Bi
# offload[12] -> Bim
# offload[13] -> Ge

offload_str=$(grep '^summary:' "$cur_log" | sed s/"summary: "//)
offload=($offload_str)

# Populate offload to PF_LOG
echo " Ir Dr Dw I1mr D1mr D1mw ILmr DLmr DLmw Bc Bcm Bi Bim Ge" | tee -a "$PF_LOG"
echo "########################################################" | tee -a "$PF_LOG"
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
    # onload[6] -> ILmr
    # onload[7] -> DLmr
    # onload[8] -> DLmw
    # onload[9] -> Bc
    # onload[10] -> Bcm
    # onload[11] -> Bi
    # onload[12] -> Bim
    # onload[13] -> Ge

    onload_str=$(grep '^summary:' "$cur_log" | sed s/"summary: "//)
    onload=($onload_str)
    # Populate onload to PF_LOG
    echo "Load: $f" | tee -a "$PF_LOG"
    echo "$onload_str" | tee -a "$PF_LOG"

    #Construct the csv file name
    CSV_FN="$CSV_LOG"_onload_"${f#docs\/}".csv

    echo -n "$TESTDATE"$'\t'"$BUILD_ID" >> "$CSV_FN"

    # Populate onload delta to PF_LOG and CSV_FN
    for i in $(seq 0 13); do
        onload_delta[$i]=$(expr ${onload[$i]} - ${offload[$i]})
        echo -n ${onload_delta[$i]} " " | tee -a "$PF_LOG"
        echo -n $'\t'${onload_delta[$i]} >> "$CSV_FN"
    done

    # CEst = Ir + 10 Bm + 10 L1m + 20 Ge + 100 L2m + 100 LLm
    CEst=$(expr ${onload_delta[0]} + 10 \* $(expr ${onload_delta[12]} + ${onload_delta[10]}) + 10 \* $(expr ${onload_delta[3]} + ${onload_delta[4]} + ${onload_delta[5]}) + 20 \* ${onload_delta[13]} + 100 \* $(expr ${onload_delta[6]} + ${onload_delta[7]} + ${onload_delta[8]}))
    echo $'\t'$CEst >> "$CSV_FN"

    echo | tee -a "$PF_LOG"
    echo | tee -a "$PF_LOG"

done

# Regression check
echo "Regression Status:" | tee -a "$PF_LOG"
echo "-----------------" | tee -a "$PF_LOG"

find $(dirname $(readlink -f "$PF_LOG")) -type f | grep -v "$PF_LOG" | grep log$ | while read rf; do

    check_regression "$PF_LOG" "$rf" | tee -a "$PF_LOG"

done

grep '^Regression found!$' "$PF_LOG" > /dev/null || echo "Congratulations, no regression found!" | tee -a "$PF_LOG"
