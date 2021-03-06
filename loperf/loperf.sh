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
rm -f $DOCUMENTSDIR/.~lock*

TESTDATE=$(date --rfc-3339=second)

test ! -f "$OFFICEBIN" && exit 1
LOVERSION="$(get_lo_version "$OFFICEBIN")"
DT=$(echo "$TESTDATE" | tr -s '\ \+\-\:' "_")

CG_LOG="logs/callgrind/cg-lo-$DT-$LOVERSION"
ERR_LOG="logs/error.log"
CSV_LOG_DIR="logs/csv/"
CSV_HISTORY="logs/history.csv"

mkdir -p logs/callgrind > /dev/null 2>&1
mkdir -p "$CSV_LOG_DIR" > /dev/null 2>&1
test -f "$CSV_HISTORY" || echo "time,git-commit,offload-first,offload-second$(ls ${DOCUMENTSDIR}/* | sed "s%${DOCUMENTSDIR}/% %g" | while read f; do echo -n ",$f-load,$f-convert"; done)" > "$CSV_HISTORY"

function launch {

    if test "$1" = "offload"; then
        export OOO_EXIT_POST_STARTUP=1
        CG_OUT_FILE="${CG_LOG}-offload-${2}.log"
        valgrind --tool=callgrind --callgrind-out-file="${CG_OUT_FILE}" --simulate-cache=yes --dump-instr=yes --collect-bus=yes --branch-sim=yes "$OFFICEBIN" --splash-pipe=0 --headless > /dev/null 2>&1
        unset OOO_EXIT_POST_STARTUP
    else
        fn=${1#$DOCUMENTSDIR\/}
        CG_OUT_FILE="${CG_LOG}-onload-${fn}-${2}.log"
        if test "$2" = "load"; then
            export OOO_EXIT_POST_STARTUP=1
            valgrind --tool=callgrind --callgrind-out-file="${CG_OUT_FILE}" --simulate-cache=yes --dump-instr=yes --collect-bus=yes --branch-sim=yes "$OFFICEBIN" --splash-pipe=0 --headless "$1" > /dev/null 2>&1
            unset OOO_EXIT_POST_STARTUP
        else
            ext=${fn##*.}
            valgrind --tool=callgrind --callgrind-out-file="${CG_OUT_FILE}" --simulate-cache=yes --dump-instr=yes --collect-bus=yes --branch-sim=yes "$OFFICEBIN" --splash-pipe=0 --headless --convert-to "$ext" --outdir tmp "$1" > /dev/null 2>&1
        fi
    fi
    echo -n "${CG_OUT_FILE}"
}

# Mapping the data to array:
#
# data[0] -> Ir
# data[1] -> Dr
# data[2] -> Dw
# data[3] -> I1mr
# data[4] -> D1mr
# data[5] -> D1mw
# data[6] -> ILmr
# data[7] -> DLmr
# data[8] -> DLmw
# data[9] -> Bc
# data[10] -> Bcm
# data[11] -> Bi
# data[12] -> Bim
# data[13] -> Ge

echo -n "$TESTDATE","$LOVERSION" >> "$CSV_HISTORY"

function write_data {
    cur_log=$(launch "${1}" "${2}")

    data=($(grep '^summary:' "$cur_log" | sed s/"summary: "//))
    
    test -n "$GZIP" && gzip "$cur_log" > /dev/null 2>&1

    #Collect data to csv file
    if test "$1" = "offload"; then
        CSV_FN="${CSV_LOG_DIR}/offload-${2}.csv"
    else
        CSV_FN="${CSV_LOG_DIR}/onload-${1#$DOCUMENTSDIR\/}-${2}.csv"
    fi

    echo -n "$TESTDATE"$'\t'"$LOVERSION" >> "$CSV_FN"
    for i in $(seq 0 13); do
        echo -n $'\t'${data[$i]} >> "$CSV_FN"
    done

    # CEst = Ir + 10 Bm + 10 L1m + 20 Ge + 100 L2m + 100 LLm
    CEst=$(expr ${data[0]} + 10 \* $(expr ${data[12]} + ${data[10]}) + 10 \* $(expr ${data[3]} + ${data[4]} + ${data[5]}) + 20 \* ${data[13]} + 100 \* $(expr ${data[6]} + ${data[7]} + ${data[8]}))
    echo $'\t'$CEst >> "$CSV_FN"
    echo -n ",$(expr ${CEst} / 1000000)" >> "$CSV_HISTORY"
}

# Do a clean launch
rm -rf ${1/program\/soffice.bin/user}
echo "First start offload pvt..."
$(write_data "offload" "first")
echo "Second start offload pvt..."
$(write_data "offload" "second")

# Loaded launch one by one
echo "Start onload pvt..."
ls ${DOCUMENTSDIR}/* | while read f; do
    echo "loading ${f}.."
    $(write_data "$f" "load")
    echo "converting ${f}.."
    $(write_data "$f" "convert")
done

echo "" >> "$CSV_HISTORY"
$OFFICEBIN --headless --convert-to fods --outdir logs "$CSV_HISTORY"

# Clean old callgrind files
find "logs/callgrind" -type f -mtime +10 -exec rm {} \;
