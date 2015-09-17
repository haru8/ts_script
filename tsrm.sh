#!/bin/sh

TSPATH=/usr/local/apps/foltia/php/tv/
TSOLDPATH=/usr/local/apps/foltia/php/tv/zero_m2t
LOGPATH=/tmp/tsrm.log
FFMPEG=/usr/local/bin/ffmpeg
#DAYS=0
OLDDAYS=186
THRESHOLD_SIZE_RATE=24
THRESHOLD_TIME_RATE=900

declare -i SUM=0

log_out () {
	local mes="$*"
	local dir=`dirname "$LOGPATH"`
	local date=`date '+%Y-%m-%d %H:%M:%S'`
	
	if [ ! -d $dir ]; then
		mkdir -p $dir
	fi
	
    if [ ! -f "$LOGPATH" ]; then
        touch "$LOGPATH"
        chmod 666 "$LOGPATH"
    fi
	if [ ! -w $LOGPATH ]; then
		sudo chmod 666 $LOGPATH
	fi
	#echo "$date: `printf %06d $$`: $mes" >> $LOGPATH
    LOGHEAD="$date: `printf %06d $$`: "
    #echo "$mes" | perl -pe "s/^/${LOGHEAD}/g" >> $LOGPATH
    echo "$mes" | sed "s/^/${LOGHEAD}/g" >> $LOGPATH
	echo "$mes"
}

movie_sec () {
	local file="$1"
	local time_s
	local -i h
	local -i m
	local -i s
	local -i sec
	time_s=`$FFMPEG -i $file 2>&1 | grep 'Duration:' | sed 's/  Duration: //g;s/,.*//;s/\.[0-9]*//' | grep -E '[0-9:]+'`
	h=`echo $time_s | awk -F: '{printf $1}' | sed 's/^0//'`
	m=`echo $time_s | awk -F: '{printf $2}' | sed 's/^0//'`
	s=`echo $time_s | awk -F: '{printf $3}' | sed 's/^0//'`
	h=$h*3600
	m=$m*60
	sec=$h+$m+$s
	
	echo $sec
	return 0
}

video_stream_count () {
	local file="$1"
	local video_count

	video_count=`$FFMPEG -i $file 2>&1 | grep 'Video: h264' | wc -l`

	echo $video_count
	return 0
}

audio_stream_count () {
	local file="$1"
	local audio_count

	audio_count=`$FFMPEG -i $file 2>&1 | grep 'Audio: aac' | wc -l`

	echo $audio_count
	return 0
}

# 引数のチェック
if [ $# = 1 ] ; then
	if [ $1 = '-t' ] ; then
		TESTMODE=1
		TESTTXT="TEST MODE"
	else
		TESTMODE=0
		TESTTXT=""
	fi
else
	TESTMODE=0
	TESTTXT=""
fi

log_out "=============== `date` $TESTTXT start ==============="
log_out ""

BEFOREDF=`df -h $TSPATH`
if [ "${DAYS:-undef}" = "undef" ]; then
	TS=`find $TSPATH -maxdepth 1 -name '*.m2t' -type f -size +1k | xargs ls -1tr /dev/null | grep -v /dev/null`
else
	TS=`find $TSPATH -maxdepth 1 -name '*.m2t' -type f -size +1k -mtime +$DAYS | xargs ls -1tr /dev/null | grep -v /dev/null`
fi

for file in $TS; do
	MP4FOUND=-1
	MP4SIZERATE=-1
	SIZERATE=0
	MP4SIZE=0
	M2TSIZE=0
	MP4TIME_RATE=-1
	TIME_RATE=-1
	TSTIME=-1
	MP4TIME=0
	IMGCHECK=-1
	VIDEOST=-1
	AUDIOST=-1
	VIDEO=-1
	AUDIO=-1
	STREAM=-1
	
	NAME=`basename "$file"`
	TSFILE="$TSPATH"/"$NAME"
	BODY=`echo "$NAME" | sed 's/\.m2t$//'`
	PID=`echo "$NAME" | sed 's/\(^[0-9]*\)-.*/\1/'`
	LOCALIZED="/usr/local/apps/foltia/php/tv/${PID}.localized"
	MP4="${LOCALIZED}/mp4/MAQ-${BODY}.MP4"
	IMGDIR="${LOCALIZED}/img/${BODY}"
	IMG="${IMGDIR}/00000001.jpg"
	IMG_EXPCOUNT=-1
	IMG_COUNT=0
	SUM=$SUM+1
	if [ -s "$TSFILE" ]; then
		M2TSIZE=`\ls -lk "$file" | awk '{print $5}'`
		TSTIME=`movie_sec "$TSFILE"`
		if [ -s "$MP4" ]; then
			MP4FOUND=0
			MP4SIZE=`\ls -lk "$MP4" | awk '{print $5}'`
			if [ $M2TSIZE -ne 0 ]; then
				SIZERATE=`perl -e "print int($MP4SIZE / $M2TSIZE * 1000)"`
			fi
			if [ $SIZERATE -ge $THRESHOLD_SIZE_RATE ]; then
				MP4SIZERATE=0
			fi

			MP4TIME=`movie_sec "$MP4"`
			if [ $TSTIME -ne 0 ]; then
				TIME_RATE=`perl -e "print int($MP4TIME / $TSTIME * 1000)"`
			fi
			if [ $? -ne 0 ]; then
				TIME_RATE=0
			fi
			if [ $TIME_RATE -ge $THRESHOLD_TIME_RATE ] ; then
				MP4TIME_RATE=0
			fi

			VIDEOST=`video_stream_count $MP4`
			if [ $VIDEOST -eq 1 ]; then
				VIDEO=0
			fi
			AUDIOST=`audio_stream_count $MP4`
			if [ $AUDIOST -eq 1 ]; then
				AUDIO=0
			fi
			if [ $VIDEO -eq 0 -a $AUDIO -eq 0 ]; then
				STREAM=0;
			fi

		fi
		if [ -s "$IMG" ]; then
			if [ $TSTIME -ne 0 ] ; then
				IMG_EXPCOUNT=`perl -e "print int($TSTIME / 10 * 0.8)"`
				IMG_COUNT=`\ls -1 ${IMGDIR}/000*.jpg 2>/dev/null | wc -l`
				if [ $IMG_COUNT -ge $IMG_EXPCOUNT ] ; then
					IMGCHECK=0
				fi
			fi
		fi

		FMP4FOUND=`if [ $MP4FOUND -eq 0 ]; then echo 'OK'; else echo 'NG'; fi`
		FNAME=`printf '%28s' $NAME`
		FTSTIME=`printf '%4d' $TSTIME`
		FM2TSIZE=`perl -e "printf('%-2.1f', $M2TSIZE/1024/1024/1024)"`
		FM2TSIZE=`printf '%4s' $FM2TSIZE`
		FIMGCHECK=`if [ $IMGCHECK -eq 0 ]; then echo 'OK'; else echo 'NG'; fi`
		FIMG_COUNT=`printf '%3d' $IMG_COUNT`
		if [ $FMP4FOUND == 'NG' ]; then
			FMP4SIZERATE='--'
			FMP4SIZE='---'
			FSIZERATE='---'
			FMP4TIME_RATE='--'
			FMP4TIME='----'
			FTIME_RATE='-----'
			FSTREAM='--'
			FAUDIOST='--'
			FVIDEOST='--'
		else
			FMP4SIZERATE=`if [ $MP4SIZERATE -eq 0 ]; then echo 'OK'; else echo 'NG'; fi`
			FMP4SIZE=`perl -e "printf('%-3d', int($MP4SIZE/1024/1024))"`
			FMP4SIZE=`printf '%3s' $FMP4SIZE`
			#FTIME_RATE=`printf '%3d' $TIME_RATE`
			FTIME_RATE=`perl -e "printf('%5.1f', $TIME_RATE / 10)"`
			FMP4TIME_RATE=`if [ $MP4TIME_RATE -eq 0 ]; then echo 'OK'; else echo 'NG'; fi`
			FMP4TIME=`printf '%4d' $MP4TIME`
			FSIZERATE=`perl -e "printf("%s", $SIZERATE/10)"`
			FSIZERATE=`printf '%2.1f' $FSIZERATE`
			FVIDEOST=`printf '%2d' $VIDEOST`
			FAUDIOST=`printf '%2d' $AUDIOST`
			FSTREAM=`if [ $STREAM -eq 0 ]; then echo 'OK'; else echo 'NG'; fi`
		fi
		#LOG='log_out "$MES $FNAME MP4=$FMP4FOUND SIZEC=$FMP4SIZERATE IMGC=$FIMGCHECK MP4T_RATE=$FMP4TIME_RATE SIZER=$FSIZERATE% MG_COUNT=$FIMG_COUNT TST=${FTSTIME}s MP4T=${FMP4TIME}s T_RATE=$FTIME_RATE% VST=$FVIDEOST AST=$FAUDIOST"'
		LOG='log_out "$MES $FNAME MP4=$FMP4FOUND SIZE=$FMP4SIZERATE:[ MP4=${FMP4SIZE}MB TS=${FM2TSIZE}GB R=${FSIZERATE}% ] TIME=$FMP4TIME_RATE:[ MP4=${FMP4TIME}s TS=${FTSTIME}s R=$FTIME_RATE% ] STREAM=$FSTREAM:[ A=$FAUDIOST V=$FVIDEOST ] THU=$FIMGCHECK:[$FIMG_COUNT]"'
		if [ $MP4FOUND -eq 0 -a $MP4SIZERATE -eq 0 -a $IMGCHECK -eq 0 -a $MP4TIME_RATE -eq 0 -a $VIDEO -eq 0 -a $AUDIO -eq 0 ]; then 
			MES=`printf '%-11s' 'delete.'`
			eval $LOG
			if [ $TESTMODE -eq 0 ]; then
				ID=`id -un`
				if [ $ID = 'apache' ]; then
					touch -r "$TSFILE" "${TSFILE}_tmp"
					rm -f "$TSFILE"
					mv "${TSFILE}_tmp" "$TSFILE"
				else
					sudo -u apache touch -r "$TSFILE" "${TSFILE}_tmp"
					sudo -u apache rm -f "$TSFILE"
					sudo -u apache mv "${TSFILE}_tmp" "$TSFILE"
				fi
			fi
		else
			MES=`printf '%-11s' 'not delete.'`
			eval $LOG
		fi
	else
		#log_out "$NAME is size zero. skipped."
		ZERO="$NAME"
	fi
	#echo $SUM : $NAME : $BODY : $PID
	#echo $LOCALIZED
	#echo $MP4 : $MP4SIZE
	#echo $IMG : $IMGCHECK
	#echo $file: $M2TSIZE
	#echo SIZERATE=$SIZERATE : $MP4CHECK
	#echo
done

ID=`id -un`
if [ $ID = 'apache' ]; then
	find $TSPATH -maxdepth 1 -name '*.m2t' -type f -size -1k -mtime +$OLDDAYS -exec mv {} $TSOLDPATH \;
#else
	#sudo -u apache find $TSPATH -maxdepth 1 -name '*.m2t' -type f -size -1k -mtime +$OLDDAYS -exec mv {} $TSOLDPATH \;
fi

AFTERDF=`df -h $TSPATH`

log_out ""
log_out "===== BEFORE DF ====="
log_out "$BEFOREDF"
log_out ""
log_out "===== AFTER DF ====="
log_out "$AFTERDF"
log_out "=============== `date` $TESTTXT end   ==============="
log_out ""
log_out ""
log_out ""

