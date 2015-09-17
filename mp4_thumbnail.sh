#!/bin/sh

MP4_PATH="/usr/local/apps/foltia/php/tv/*/mp4/*.MP4"
#MP4_PATH="/usr/local/apps/foltia/php/tv/3363.localized/mp4/*.MP4"
FFMPEG="/usr/local/bin/ffmpeg"
MPLAYER="/usr/local/bin/mplayer"

for mp4 in $MP4_PATH; do
	FILEBODY=`echo $mp4 | sed 's/\.[^.]*$//'`
	if [ ! -e "${FILEBODY}.THM" ]; then
		#echo $mp4
		#echo $FILEBODY
		#$FFMPEG -loglevel quiet -ss 80 -i "$mp4" -vframes 1 -s 160x120 -f image2 "${FILEBODY}.jpg"
		#mv "${FILEBODY}.jpg" "${FILEBODY}.THM"

		OUTDIR="${FILEBODY}_THM_$$"
		mkdir -p "$OUTDIR"
		$MPLAYER -ss 00:01:20 -vo jpeg:outdir="$OUTDIR" -nosound -vf framestep=300step,scale=160:90,expand=160:120 -frames 1 "$mp4"
		if [ -e "${OUTDIR}/00000001.jpg" ]; then
			mv "${OUTDIR}/00000001.jpg" "${FILEBODY}.THM"
		fi
		rm -fr "$OUTDIR"
		echo "create ${FILEBODY}.THM"
	fi
done

