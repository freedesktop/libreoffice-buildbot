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

# Requirement check
# Vagrind >= 3.7

REQUIRED_VALGRIND_VERSION="valgrind-3.7.0"

hash valgrind > /dev/null 2>&1 || echo "valgrind >= $REQUIRED_VALGRIND_VERSION is required for this test."
hash gzip > /dev/null 2>&1 && GZIP="TRUE"

if test $(compareversion "$(valgrind --version)" "$REQUIRED_VALGRIND_VERSION") -eq -1; then
    echo "valgrind >= $REQUIRED_VALGRIND_VERSION is required for this test."
    exit 1
fi

# Post dependency check
export OOO_DISABLE_RECOVERY=1
OFFICEBIN="$1"
DOCUMENTSDIR="$2"
test -z "$DOCUMENTSDIR" && echo "missing second parameter: directory with documents to test" && exit 1

TESTDATE=$(date --rfc-3339=second)

test ! -f "$OFFICEBIN" && exit 1
LOVERSION="$(get_lo_version "$OFFICEBIN")"
DT=$(echo "$TESTDATE" | tr -s '\ \+\-\:' "_")

CG_LOG="logs/callgrind/cg-lo-$DT-$LOVERSION"
PF_LOG="logs/loperf/pf-lo-$DT-$LOVERSION.log"
ERR_LOG="logs/error.log"
CSV_LOG_DIR="logs/csv/"
CSV_HISTORY="logs/history.csv"

mkdir -p logs/callgrind > /dev/null 2>&1
mkdir -p logs/loperf > /dev/null 2>&1
mkdir -p "$CSV_LOG_DIR" > /dev/null 2>&1
test -f "$CSV_HISTORY" || echo -e "time,git-commit,offload$(ls $DOCUMENTSDIR/* | sed s%$DOCUMENTSDIR/%,%g | tr -d '\n')" > "$CSV_HISTORY"

function launch {

    if test "$1" = ""; then
        export OOO_EXIT_POST_STARTUP=1
        valgrind --tool=callgrind --callgrind-out-file="$CG_LOG"-offload.log --simulate-cache=yes --dump-instr=yes --collect-bus=yes --branch-sim=yes "$OFFICEBIN" --splash-pipe=0 --headless > /dev/null 2>&1
        unset OOO_EXIT_POST_STARTUP
        echo -n "$CG_LOG"-offload.log
    else
        fn=${1#$DOCUMENTSDIR\/}
        ext=${fn##*.}
        valgrind --tool=callgrind --callgrind-out-file="$CG_LOG"-onload-"$fn".log --simulate-cache=yes --dump-instr=yes --collect-bus=yes --branch-sim=yes "$OFFICEBIN" --splash-pipe=0 --headless --convert-to "$ext" --outdir tmp "$1" > /dev/null 2>&1
        echo -n "$CG_LOG"-onload-"$fn".log
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
if test -n "$GZIP"; then gzip "$cur_log" > /dev/null 2>&1; fi

#Collect data to csv file
CSV_FN="$CSV_LOG_DIR"/"offload.csv"
echo -n "$TESTDATE"$'\t'"$LOVERSION" >> "$CSV_FN"
for i in $(seq 0 13); do
    echo -n $'\t'${offload[$i]} >> "$CSV_FN"
done
# CEst = Ir + 10 Bm + 10 L1m + 20 Ge + 100 L2m + 100 LLm
CEst=$(expr ${offload[0]} + 10 \* $(expr ${offload[12]} + ${offload[10]}) + 10 \* $(expr ${offload[3]} + ${offload[4]} + ${offload[5]}) + 20 \* ${offload[13]} + 100 \* $(expr ${offload[6]} + ${offload[7]} + ${offload[8]}))
echo $'\t'$CEst >> "$CSV_FN"
echo -n "$TESTDATE","$LOVERSION",$CEst >> "$CSV_HISTORY"

# Populate offload to PF_LOG
echo " Ir Dr Dw I1mr D1mr D1mw ILmr DLmr DLmw Bc Bcm Bi Bim Ge" | tee -a "$PF_LOG"
echo "########################################################" | tee -a "$PF_LOG"
echo | tee -a "$PF_LOG"
echo "Offload:" | tee -a "$PF_LOG"
echo "$offload_str" | tee -a "$PF_LOG"
echo | tee -a "$PF_LOG"

# Loaded launch one by one
echo "Start onload pvt..."
find $DOCUMENTSDIR -type f |  grep -Ev "\/\." | while read f; do
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
    if test -n "$GZIP"; then gzip "$cur_log" > /dev/null 2>&1; fi
    # Populate onload to PF_LOG
    echo "Load: $f" | tee -a "$PF_LOG"
    echo "$onload_str" | tee -a "$PF_LOG"

    # Populate onload delta to PF_LOG
    for i in $(seq 0 13); do
        onload_delta[$i]=$(expr ${onload[$i]} - ${offload[$i]})
        echo -n ${onload_delta[$i]} " " | tee -a "$PF_LOG"
    done

    #Construct the csv file name
    CSV_FN="$CSV_LOG_DIR"/"onload-${f#$DOCUMENTSDIR\/}".csv

    echo -n "$TESTDATE"$'\t'"$LOVERSION" >> "$CSV_FN"

    # Populate onload to CSV_FN
    for i in $(seq 0 13); do
        echo -n $'\t'${onload[$i]} >> "$CSV_FN"
    done

    # CEst = Ir + 10 Bm + 10 L1m + 20 Ge + 100 L2m + 100 LLm
    CEst=$(expr ${onload[0]} + 10 \* $(expr ${onload[12]} + ${onload[10]}) + 10 \* $(expr ${onload[3]} + ${onload[4]} + ${onload[5]}) + 20 \* ${onload[13]} + 100 \* $(expr ${onload[6]} + ${onload[7]} + ${onload[8]}))
    echo $'\t'$CEst >> "$CSV_FN"
    echo -n ",$CEst" >> "$CSV_HISTORY"

    echo | tee -a "$PF_LOG"
    echo | tee -a "$PF_LOG"

done
echo "" >> "$CSV_HISTORY"
$OFFICEBIN --headless --convert-to fods --outdir logs "$CSV_HISTORY"

# Clean old callgrind files
find "logs/callgrind" -type f -mtime +10 -exec rm {} \;

# Regression check
# echo "Regression Status:" | tee -a "$PF_LOG"
# echo "-----------------" | tee -a "$PF_LOG"
# find $(dirname $(readlink -f "$PF_LOG")) -type f | grep -v "$PF_LOG" | grep log$ | while read rf; do
#     check_regression "$PF_LOG" "$rf" | tee -a "$PF_LOG"
# done
# grep '^Regression found!$' "$PF_LOG" > /dev/null || echo "Congratulations, no regression found!" | tee -a "$PF_LOG"
