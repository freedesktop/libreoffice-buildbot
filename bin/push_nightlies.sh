#!/usr/bin/env bash

## subroutines
usage ()
{
	echo "Usage: $0 [options]"
	echo "Options:"
	echo "-h          this help"
	echo "-t <time>   pull time of this checkout"
	echo "-n <name>   name of this tinderbox"
	echo "-l <kbps>   bandwidth limit for upload (KBps)"
}

BUILDER_NAME=
PULL_TIME=
BANDWIDTH_LIMIT=20
while getopts ht:n:l: opt ; do
	case "$opt" in
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
fi

if [ ! -d "instsetoo_native" ] ; then
	echo "current working directory is not, or not a valid bootstrap git repo" 1>&2
	exit 1;
fi

CURR_HEAD=$(<".git/HEAD")
BRANCH="${CURR_HEAD#*/*/}"
tag="${BRANCH}~${PULL_TIME}"
ssh upload@gimli.documentfoundation.org "mkdir -p \"/srv/www/dev-builds.libreoffice.org/daily/${BUILDER_NAME}/${BRANCH}/${PULL_TIME}\"" || exit 1

. ./*[Ee]nv.[Ss]et.sh
cd instsetoo_native
mkdir ${INPATH}/push 2>/dev/null

for file in $(find . -name "*.dmg" -o -name "*.tar.gz" -o -name "*.exe" | grep -v "/push/")
do
	target=$(basename $file)
	target="${tag}_${target}"

	mv $file "${INPATH}/push/$target"
done;

rsync --bwlimit=${BANDWIDTH_LIMIT} -avsPe ssh ${INPATH}/push/* "upload@gimli.documentfoundation.org:/srv/www/dev-builds.libreoffice.org/daily/${BUILDER_NAME}/${BRANCH}/${PULL_TIME}/" || exit 1
if [ "$?" == "0" ] ; then
	ssh upload@gimli.documentfoundation.org "cd \"/srv/www/dev-builds.libreoffice.org/daily/${BUILDER_NAME}/${BRANCH}/\" && ln -sf \"${PULL_TIME}\" current"
fi
