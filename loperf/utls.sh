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

function get_lo_build {

     #TODO: get the build for binary build
     echo -n "4.0"
}

function get_lo_commit_hash {

    LOGITDIR=$(echo -n $(echo -n "$1" | sed 's/core.*//')core/.git)
    
    echo -n $(git --git-dir="$LOGITDIR" log -1 --date=iso --pretty=format:"%H")
}

function is_delta_regress {
    # input two arrays and return an array of regression or 1

    a1=($1)
    a2=($2)

    if test ${#a1[@]} -eq ${#a2[@]}; then
        for i in $(seq 0 $(expr ${#a2[@]} - 1)); do
            arr_result[$i]=$(expr ${a1[$i]} - ${a2[$i]})
        done

        if [ ${arr_result[0]} -gt 0 ] && [ ${arr_result[3]} -gt 0 ] && [ ${arr_result[6]} -gt 0 ]; then
            echo -n ${arr_result[@]}
            return 0
        else
            return 2
        fi
    else
        echo "Error: log files format is probably not consistent."
        return 1
    fi

    echo "Error: Something was wrong when checking regression"
    return 1

}

# compare two logs $1 and $2 side by side
function check_regression {

    # check if logfile $1 has regression against logfile $2
    # append the regression stat in PF_LOG

    grep 'Reg:' "$1" > /dev/null && echo "Warning: Regression status already in $1"

    # find offload regression


    # find onload regression

    i=0
    grep "^Load:" "$1" > /tmp/$$
    while read fn; do
        arr_onload_files[$i]="$fn"
        let i=i+1
    done< "/tmp/$$"

    arr_onload_files_lens=${#arr_onload_files[@]}

    for j in $(seq 0 $(expr $arr_onload_files_lens - 1)); do

        delta1="$(grep -A2 "${arr_onload_files[$j]}" "$1" | tail -n1)"
        delta2="$(grep -A2 "${arr_onload_files[$j]}" "$2" | tail -n1)"

        r=$(is_delta_regress "$delta1" "$delta2")

        if test $? -eq 0; then
            echo "Regression found!"
            echo "Document : ${arr_onload_files[$j]#Load: }"
            echo "Reference: $2"
            echo "Diffstats: $r"
            echo "--------------------------------------"            
            return 0
        fi 

    done

    return 1

}
