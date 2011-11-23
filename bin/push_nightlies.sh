#!/usr/bin/env bash

bin_dir=$(dirname "$0")
lock_file="/tmp/tinbuild-upload"
core_dir=$(pwd)

## subroutines
usage ()
{
	echo "Usage: $0 [options]"
	echo "Options:"
	echo "-a          push asynchronously"
	echo "-h          this help"
	echo "-t <time>   pull time of this checkout"
	echo "-n <name>   name of this tinderbox"
	echo "-l <kbps>   bandwidth limit for upload (KBps)"
}

do_lock()
{
    m="$(uname)"
    case "$m" in
        Darwin)
            ${bin_dir?}/flock "$@"
            ;;
        *)
            flock "$@"
    esac
}


BUILDER_NAME=
PULL_TIME=
BANDWIDTH_LIMIT=20
ASYNC=0

while getopts aht:n:l: opt ; do
	case "$opt" in
        a) ASYNC=1 ;;
		h) usage; exit ;;
		t) PULL_TIME="${OPTARG// /_}" ;;
		n) BUILDER_NAME="${OPTARG// /_}" ;;
		l) BANDWIDTH_LIMIT="$OPTARG" ;;
		?) usage; exit ;;
	esac
done

if [ -z "$PULL_TIME" -o -z "$BUILDER_NAME" ] ; then
	echo "missing argument. syntax $0 -t <git_pull_timestap> -n <tinderbox_name>" 1>&2
    exit 1;
else
    PULL_TIME="${PULL_TIME//:/.}"
fi

if [ ! -d "instsetoo_native" ] ; then
	echo "current working directory is not, or not a valid bootstrap git repo" 1>&2
	exit 1;
fi

CURR_HEAD=$(<".git/HEAD")
BRANCH="${CURR_HEAD#*/*/}"
tag="${BRANCH}~${PULL_TIME}"
ssh upload@gimli.documentfoundation.org "mkdir -p \"/srv/www/dev-builds.libreoffice.org/daily/${BUILDER_NAME}/${BRANCH}/${PULL_TIME}\"" || exit 1

if [ -f Env.Host.sh ] ; then
    . Env.Host.sh
else
    . ./*[Ee]nv.[Ss]et.sh
fi

cd instsetoo_native/${INPATH}

if [ "$ASYNC" = "1" ] ; then
    stage="/tmp"
else
    mkdir push 2>/dev/null
    stage="./push"
fi

echo "find packages"
for file in $(find . -name "*.dmg" -o -name "LibO*.tar.gz" -o -name "LibO*.exe" -o -path '*/LibreOffice_Dev/native/install/*.msi' | grep -v "/push/")
do
	target=$(basename $file)
	target="${tag}_${target}"
    if [ "$ASYNC" = "1" ] ; then
	    cp $file "$stage/$target"
    else
	    mv $file "$stage/$target"
    fi
done;

if [ -f ${core_dir}/build_info.txt ] ; then
    target="${tag}_build_info.txt"
    if [ "$ASYNC" = "1" ] ; then
	    cp ${core_dir}/build_info.txt  "$stage/$target"
    else
	    mv ${core_dir}/build_info.txt  "$stage/$target"
    fi
fi

if [ "$ASYNC" = "1" ] ; then
(
    (
#        do_flock -x 200
        rsync --bwlimit=${BANDWIDTH_LIMIT} -avPe ssh ${stage}/${tag}_* "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${BUILDER_NAME}/${BRANCH}/${PULL_TIME}/" || exit 1
        if [ "$?" == "0" ] ; then
	        ssh upload@gimli.documentfoundation.org "cd \"/srv/www/dev-builds.libreoffice.org/daily/${BUILDER_NAME}/${BRANCH}/\" && { rm current; ln -s \"${PULL_TIME}\" current ; }"
        fi
        rm -fr ${stage}/${tag}_*
    )# 200>${lock_file?}
) &
else
    rsync --bwlimit=${BANDWIDTH_LIMIT} -avPe ssh ${stage}/${tag}_* "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${BUILDER_NAME}/${BRANCH}/${PULL_TIME}/" || exit 1
    if [ "$?" == "0" ] ; then
	    ssh upload@gimli.documentfoundation.org "cd \"/srv/www/dev-builds.libreoffice.org/daily/${BUILDER_NAME}/${BRANCH}/\" && { rm current; ln -s \"${PULL_TIME}\" current ; }"
    fi
fi
