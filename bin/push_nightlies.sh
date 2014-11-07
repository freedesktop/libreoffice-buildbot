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
	echo "-s          staging dir for async upload (default /tmp/${B}"
	echo "-t <time>   pull time of this checkout"
	echo "-n <name>   name of this tinderbox"
	echo "-l <kbps>   bandwidth limit for upload (KBps)"
	echo "-p <dir>    location of the pdb symbol store to update and upload"
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
STAGE_DIR=/tmp
SYMBOLS_DIR=
SYMSTORE="/cygdrive/c/Program Files/Debugging Tools for Windows (x64)/symstore"


while getopts aht:n:l:p: opt ; do
	case "$opt" in
        a) ASYNC=1 ;;
		h) usage; exit ;;
        s) STAGE_DIR="${OPTARG}";;
		t) PULL_TIME="${OPTARG// /_}" ;;
		n) BUILDER_NAME="${OPTARG// /_}" ;;
		l) BANDWIDTH_LIMIT="$OPTARG" ;;
		p) SYMBOLS_DIR="${OPTARG}";;
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
ssh upload@gimli.documentfoundation.org "mkdir -p \"/srv/www/dev-builds.libreoffice.org/daily/${BRANCH}/${BUILDER_NAME}/${PULL_TIME}\"" || exit 1

if [ -f config_host.mk ] ; then
    INPATH=$(grep INPATH= config_host.mk | sed -e "s/.*=//")
fi

topdir="$PWD"

if [ -z "$INPATH" ] ; then
    false
else
    cd instsetoo_native/${INPATH}
fi

if [ $? != 0 ]; then
    cd workdir
fi

if [ "$ASYNC" = "1" ] ; then
    stage="$STAGE_DIR"
else
    mkdir push 2>/dev/null
    stage="./push"
fi

echo "find packages"
for file in $(find . -name "*.dmg" -o -name '*.apk' -o -name "Lib*O*.tar.gz" -o -name "Lib*O*.exe" -o -name "Lib*O*.zip" -o -path '*/installation/*/msi/install/*.msi' | grep -v "/push/")
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


# Add pdb files for binaries of the given extension (exe,dll)
# and type (Library/Executable) to the given list.
add_pdb_files()
{
    extension=$1
    type=$2
    list=$3
    for file in `find install/ -name *.${extension}`; do
        filename=`basename $file .${extension}`
        pdb=`echo workdir/*/LinkTarget/${type}/${filename}.pdb`
        if test -f "$pdb"; then
            echo `cygpath -w $pdb` >>$list
        fi
    done

}

if [ -n "$SYMBOLS_DIR" ] ; then
    pushd "$topdir" >/dev/null
    ssh upload@gimli.documentfoundation.org "mkdir -p \"/srv/www/dev-builds.libreoffice.org/daily/${BRANCH}/${BUILDER_NAME}/symbols\"" || exit 1
    echo "update symbols"
    rm -f symbols-pdb-list.txt
    mkdir -p $SYMBOLS_DIR
    add_pdb_files dll Library symbols-pdb-list.txt
    add_pdb_files exe Executable symbols-pdb-list.txt
    "${SYMSTORE}" add /f @symbols-pdb-list.txt /s `cygpath -w $SYMBOLS_DIR` /t LibreOffice /v "$PULL_TIME"
    rm symbols-pdb-list.txt

    # The maximum number of versions of symbols to keep, older revisions will be removed.
    # Unless the .dll/.exe changes, the .pdb should be shared, so with incremental tinderbox several revisions should
    # not be that space-demanding.
    KEEP_MAX_REVISIONS=5
    to_remove=`ls -1 ${SYMBOLS_DIR}/000Admin | grep -v '\.txt' | grep -v '\.deleted' | sort | head -n -${KEEP_MAX_REVISIONS}`
    for revision in $to_remove; do
        "${SYMSTORE}" del /i ${revision} /s `cygpath -w $SYMBOLS_DIR`
    done
    popd >/dev/null
fi

if [ "$ASYNC" = "1" ] ; then
(
    (
#        do_flock -x 200
        rsync --bwlimit=${BANDWIDTH_LIMIT} -avPe ssh ${stage}/${tag}_* "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${BRANCH}/${BUILDER_NAME}/${PULL_TIME}/" || exit 1
        if [ "$?" == "0" ] ; then
	        ssh upload@gimli.documentfoundation.org "cd \"/srv/www/dev-builds.libreoffice.org/daily/${BRANCH}/${BUILDER_NAME}/\" && { rm current; ln -s \"${PULL_TIME}\" current ; }"
        fi
        rm -fr ${stage}/${tag}_*
        if [ -n "$SYMBOLS_DIR" ] ; then
            rsync --bwlimit=${BANDWIDTH} --fuzzy --delete-after -ave ssh ${SYMBOLS_DIR}/ "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${BRANCH}/${BUILDER_NAME}/symbols/" || exit 1
        fi
    )# 200>${lock_file?}
) &
else
    rsync --bwlimit=${BANDWIDTH_LIMIT} -avPe ssh ${stage}/${tag}_* "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${BRANCH}/${BUILDER_NAME}/${PULL_TIME}/" || exit 1
    if [ "$?" == "0" ] ; then
	    ssh upload@gimli.documentfoundation.org "cd \"/srv/www/dev-builds.libreoffice.org/daily/${BRANCH}/${BUILDER_NAME}/\" && { rm current; ln -s \"${PULL_TIME}\" current ; }"
    fi
    if [ -n "$SYMBOLS_DIR" ] ; then
        rsync --bwlimit=${BANDWIDTH} --fuzzy --delete-after -ave ssh ${SYMBOLS_DIR}/ "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${BRANCH}/${BUILDER_NAME}/symbols/" || exit 1
    fi
fi
