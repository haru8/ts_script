#!/bin/sh

INFILE="$1"
STEP=$2
OUTDIR="$3"
FFMPEG='/usr/local/bin/ffmpeg'
THUMB_S='288x162'
THUMB_L='1280x720'

FILEBODY=`basename $INFILE | sed 's/\.[^.]*$//'`
INDIR=`dirname $INFILE`

movie_sec () {
	local file="$1"
	local time_s
	local -i h
	local -i m
	local -i s
	local -i sec
	time_s=`$FFMPEG -i $file 2>&1 | grep 'Duration:' | sed 's/  Duration: //g;s/,.*//;s/\.[0-9]*//'`
	h=`echo $time_s | awk -F: '{printf $1}' | sed 's/^0//'`
	m=`echo $time_s | awk -F: '{printf $2}' | sed 's/^0//'`
	s=`echo $time_s | awk -F: '{printf $3}' | sed 's/^0//'`
	h=$h*3600
	m=$m*60
	sec=$h+$m+$s
	
	echo $sec
	return 0
}

#echo $#
if [ $# != 3 ]; then
  echo err.
  echo "$0" inputfilename step outdir
  exit 1
fi

mkdir -p "$OUTDIR/l"

declare -i NUM=0
declare -i SEC=0
declare -i PLAYSEC=0
declare -i NUMS=0

PLAYSEC=`movie_sec "$INFILE"`
NUMS=$PLAYSEC/$STEP
echo "PLAYSEC=$PLAYSEC  NUMS=$NUMS"

RETVAL1=0

$FFMPEG -y -loglevel quiet -ss 80 -i "$INFILE" -vframes 1 -s 160x120 -f image2 "${FILEBODY}.jpg"
mv "${FILEBODY}.jpg" "${FILEBODY}.THM"

while [ $RETVAL1 = 0 ]; do
  NUM_S=`perl -e "printf('%08d', $NUM)"`
  TIME=`perl -e "printf(\"%02d:%02d:%02d\", int($SEC/3600), int($SEC/60), $SEC%60);"`
  CMD1="$FFMPEG -y -loglevel quiet -ss $SEC -i \"$INFILE\" -vframes 1 -s $THUMB_S -f image2 \"${OUTDIR}/${NUM_S}.jpg\""
  CMD2="$FFMPEG -y -loglevel quiet -ss $SEC -i \"$INFILE\" -vframes 1 -s $THUMB_L -f image2 \"${OUTDIR}/l/${NUM_S}.jpg\""
  echo $CMD1
  eval $CMD1
  echo $CMD2
  eval $CMD2
  #sleep 1
  RETVAL1=$?

  #if [ ! -e "${OUTDIR}/${NUM_S}.jpg" ]; then
  #  echo "${OUTDIR}/${NUM_S}.jpg" not found.
  #  break
  #fi
  if [ $NUM -gt $NUMS ]; then
    break
  fi

  NUM=$NUM+1
  SEC=$SEC+$STEP
done

