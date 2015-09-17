#!/bin/bash

TSSPY="/usr/local/apps/foltia/perl/tool/tss.py_"
TSSPLITTER="/usr/local/apps/foltia/perl/tool/TsSplitter.exe"
FFMPEG="/usr/local/bin/ffmpeg"
MPLAYER="/usr/local/bin/mplayer"
NEROAACENC="/usr/local/bin/neroAacEnc"
FAAC="/usr/local/bin/faac"
MP4BOX="/usr/local/bin/MP4Box"
THUMB_S='288x162'
THUMB_L='1280x720'
SUCCESS_SIZE=200

# 1だとsplitしない
SPLITOFF=1

LOGPATH="/tmp/ts2mp4.log"

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
	if [ ! -w "$LOGPATH" ]; then
		sudo chmod 666 "$LOGPATH"
	fi
	echo "$date: `printf %06d $$`: $mes" >> "$LOGPATH"
	echo "$mes"
}

# splitしたファイルのチェック
# 元のTSと比べて小さすぎるなら何かがおかしい
# P1     : TSファイル
# P2     : splitしたHDファイル
# 戻り値 : 0=正常、それ以外=異常
validationsplitfile () {
	local infile="$1"
	local spfile="$2"
	local -i valid=0
	local -i retval=10
	log_out "validationsplitfile() infile=$infile spfile=$spfile start."

	# ファイルサイズ取得
	if [ -e "$infile" ]; then
		local -i insize=`ls -lk "$infile" | awk '{print $5}'`
	else
		local -i insize=0
	fi
	if [ -e "$spfile" ]; then
		local -i spsize=`ls -lk "$spfile" | awk '{print $5}'`
	else
		local -i spsize=0
	fi
	log_out "insize=$insize spsize=$spsize"


	if [ $spsize -gt 0 ]; then
		valid=`perl -e "printf('%d', ($spsize / $insize) * 100)"`
		log_out "($spsize / $insize) * 100 = $valid"

		# 入力ファイルと比べて小さすぎるならsplitに失敗している
		if [ $valid -le 50 ]; then
			log_out "ERR File split may be fail. split file size is under 50%."
			rm -f $spfile
			retval=1
		else
			log_out "valid."
			retval=0
		fi
	else
		log_out "ERR File split may be fail. split file size is zero."
		rm -f $spfile
		retval=1
	fi

	log_out "validationsplitfile() end. retval = $retval"
	return $retval
}

# splitしたSDファイルのチェック
# SD1、SD2、SD3の内最もファイルサイズが大きいファイルを返す。
# P1     : TSファイル
# P2     : SD1ファイル
# P3     : SD2ファイル
# P4     : SD3ファイル
# 戻り値 : 1 or 2 or 3 、それ以外=異常
validationsplitfileSD () {
	local infile="$1"
	local sd1file="$2"
	local sd2file="$3"
	local sd3file="$4"
	local spfile=""
	local -i valid=0
	local -i retval=10

	# ファイルサイズ取得
	local -i insize=`ls -lk $infile | awk '{print $5}'`
	if [ -e "$sd1file" ]; then
		local -i sd1size=`ls -lk "$sd1file" | awk '{print $5}'`
		log_out "`ls -lh $sd1file`"
	else
		local -i sd1size=0
	fi
	if [ -e "$sd2file" ]; then
		local -i sd2size=`ls -lk "$sd2file" | awk '{print $5}'`
		log_out "`ls -lh $sd2file`"
	else
		local -i sd2size=0
	fi
	if [ -e "$sd3file" ]; then
		local -i sd3size=`ls -lk "$sd3file" | awk '{print $5}'`
		log_out "`ls -lh $sd3file`"
	else
		local -i sd3size=0
	fi

	# SD1 と SD2 を比較
	if [ $sd1size -gt $sd2size ]; then
		spfile="$sd1file"
		retval=1
	else
		spfile="$sd2file"
		retval=2
	fi

	# SD3 と比較
	local -i spsize=`ls -lk "$spfile" | awk '{print $5}'`
	if [ $spsize -gt $sd3size ]; then
		spfile="$spfile"
	else
		spfile="$sd3file"
		retval=3
	fi
	log_out "spfile = $spfile"
	local -i spsize=`ls -lk "$spfile" | awk '{print $5}'`

	if [ $spsize -gt 0 ]; then
		valid=`perl -e "printf('%d', ($spsize / $insize) * 100)"`
		log_out "($spsize / $insize) * 100 = $valid"

		# 入力ファイルと比べて小さすぎるならsplitに失敗している
		if [ $valid -ge 25 ]; then
			log_out "valid."
		else
			log_out "ERR File split may be fail. split file size is under 25%."
			rm -f $spfile
			retval=10
		fi
	else
		log_out "ERR File split may be fail. split file size is zero."
		rm -f $spfile
		retval=10
	fi

	log_out "validationsplitfileSD() retval = $retval"
	return $retval
}

# TSがあるディレクトリに [拡張子を除いたTSファイル名 + _img] でディレクトリを作成し、
# 10秒置きにサムネイルを作成。
# P1 : TSファイル
captureimage () {
	local infile="$1"
	local base=`dirname $infile`
	local outdir="${base}/${FILEBODY}_img"
	local -i num=0
	local -i sec=0
	local -i step=10
	local num_s=""

	mkdir -p "$outdir/l"

	local retval=0
	log_out "captureimage() start."
	log_out "infile = $infile " " outdir = $outdir"

	#$FFMPEG -loglevel quiet -ss 80 -i "$infile" -vframes 1 -s 160x120 -f image2 "${FILEBODY}.jpg"
	#mv "${FILEBODY}.jpg" "${FILEBODY}.THM"

	while [ $retval = 0 ];do
		num_s=`perl -e "printf('%08d', $num)"`
		nice -n 15 $FFMPEG -loglevel quiet -ss $sec -y -i "$infile" -vframes 1 -s $THUMB_S -f image2 "${outdir}/${num_s}.jpg"
		nice -n 15 $FFMPEG -loglevel quiet -ss $sec -y -i "$infile" -vframes 1 -s $THUMB_L -f image2 "${outdir}/l/${num_s}.jpg"
		retval=$?

		# ファイルが出来ていなかったら動画の末尾まで到達したと判定
		if [ ! -e "${outdir}/${num_s}.jpg" ]; then
			break
		fi
		num=$num+1
		sec=$sec+$step
	done
	log_out "num=$num: sec=$sec"
	log_out "file count = " "`ls -1 ${outdir}/* | wc -l`"
	log_out "captureimage() end."
}

# 引数が一つ以外だと終わる
if [ $# != 1 ]; then
	log_out "  usage: `basename $0` input.m2t"
	exit 1;
fi

STARTDATE=`date '+%Y/%m/%d %H:%M:%S'`

INFILE="$1"
SPLITFILE="$INFILE"
FILEBODY=`basename $INFILE | sed 's/\.[^.]*$//'`
SRCDIR=`dirname $INFILE`

log_out ""
log_out "$0 $INFILE Start."

# TSが無かったら終わる
if [ ! -e "$INFILE" ]; then
	log_out "$INFILE not found."
	exit 2;
fi
log_out "input TS file"
log_out "`ls -lh $INFILE`"

# TSのディレクトリに書き込めなかったら終わる
if [ ! -w "$SRCDIR" ]; then
	log_out "output dir write err."
	exit 3;
fi

# HDのストリームのみ抽出
if [ -x "$TSSPY" -a $SPLITOFF -ne 1 ]; then
	# 既に有ったら消しておく
	if [ -e "${SRCDIR}/${FILEBODY}_tss.m2t" ]; then
		rm -f  "${SRCDIR}/${FILEBODY}_tss.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}_HD.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_HD.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}_SD1.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_SD1.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}_SD2.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_SD2.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}_SD3.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_SD3.m2t"
	fi
	log_out "$TSSPY $INFILE  start."
	nice -n 15 "$TSSPY" "$INFILE"
	RET=$?
	log_out "$TSSPY $INFILE  end. :$RET"
fi

# ファイルの最初は不安定なので捨てる
SSTIME=' -ss 00:00:02.000 '

if [ -e "${SRCDIR}/${FILEBODY}_tss.m2t" ]; then
	SPLITFILE="${SRCDIR}/${FILEBODY}_tss.m2t"
	log_out "tss.py split file"
	log_out "`ls -lh $SPLITFILE`"
else
	log_out "ERR. NOT Exist ${SRCDIR}/${FILEBODY}_tss.m2t"
	SPLITFILE=""
fi

# splitしたファイルのチェック
log_out "call validationsplitfile $INFILE $SPLITFILE"
validationsplitfile "$INFILE" "$SPLITFILE"
VALID=$?

# tss.pyに失敗してたらwineでTsSplit.exe
if [ $VALID -ne 0 -a $SPLITOFF -ne 1 ]; then
	if [ -e $TSSPLITTER ]; then
		log_out "wine $TSSPLITTER -EIT -ECM -EMM -1SEG $INFILE  start."
		#wine "$TSSPLITTER" -EIT -ECM -EMM -SD -1SEG "$INFILE"
		nice -n 15 wine "$TSSPLITTER" -EIT -ECM -EMM -1SEG "$INFILE"
		RET=$?
		log_out "$TSSPLITTER  end. :$RET"

		if [ -e "${SRCDIR}/${FILEBODY}_HD.m2t" ]; then
			SPLITFILE="${SRCDIR}/${FILEBODY}_HD.m2t"
			log_out "TsSplit.exe split file"
			log_out "`ls -lh $SPLITFILE`"
		
			# splitしたファイルのチェック
			log_out "call validationsplitfile $INFILE $SPLITFILE"
			validationsplitfile "$INFILE" "$SPLITFILE"
			VALID=$?
		
			# ストリームの最初からのはずなので捨てない。
			SSTIME=' -ss 00:00:00.000 '
		else
			log_out "ERR. NOT Exist ${SRCDIR}/${FILEBODY}_SD[123].m2t"
			SPLITFILE=""
		fi
	fi
else
	# ファイルの最初は不安定なので捨てる
	SSTIME=' -ss 00:00:02.000 '
fi

# HDがだめならSDかも
if [ $VALID -ne 0 -a $SPLITOFF -ne 1 ]; then
	if [ -e "${SRCDIR}/${FILEBODY}_SD1.m2t" -o -e "${SRCDIR}/${FILEBODY}_SD2.m2t" -o -e "${SRCDIR}/${FILEBODY}_SD3.m2t" ]; then
		log_out "call validationsplitfileSD $INFILE ${SRCDIR}/${FILEBODY}_SD1.m2t ${SRCDIR}/${FILEBODY}_SD2.m2t ${SRCDIR}/${FILEBODY}_SD3.m2t"
		validationsplitfileSD "$INFILE" "${SRCDIR}/${FILEBODY}_SD1.m2t" "${SRCDIR}/${FILEBODY}_SD2.m2t" "${SRCDIR}/${FILEBODY}_SD3.m2t"
		RET=$?
		if [ $RET -eq 1 ]; then
			SPLITFILE="${SRCDIR}/${FILEBODY}_SD1.m2t"
			VALID=0
			SSTIME=' -ss 00:00:00.000 '
		elif [ $RET -eq 2 ]; then
			SPLITFILE="${SRCDIR}/${FILEBODY}_SD2.m2t"
			VALID=0
			SSTIME=' -ss 00:00:00.000 '
		elif [ $RET -eq 3 ]; then
			SPLITFILE="${SRCDIR}/${FILEBODY}_SD3.m2t"
			VALID=0
			SSTIME=' -ss 00:00:00.000 '
		else
			SPLITFILE="$INFILE"
			SSTIME=' -ss 00:00:02.000 '
		fi
	fi
fi
if [ $SPLITOFF -eq 1 ]; then
	SPLITFILE="$INFILE"
	SSTIME=' -ss 00:00:02.000 '
	log_out "SPLITOFF = $SPLITOFF, Split OFF."
fi
log_out "SPLITFILE = $SPLITFILE"

CROPOPT=' -vf crop=in_w-16:in_h-12:8:6 '
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset medium -g 100 -crf 21 -bufsize 768k -maxrate 700k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset slow -g 100 -crf 21 -bufsize 768k -maxrate 700k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset faster -g 100 -crf 25 -bufsize 768k -maxrate 700k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset ultrafast -g 100 -crf 25 -bufsize 768k -maxrate 700k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset fast -g 100 -crf 25 -bufsize 768k -maxrate 768k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset fast -g 100 -crf 21 -bufsize 768k -maxrate 768k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
FFMPEGOPT=" -threads 0 -s 640x360 -r 29.97 -vcodec libx264 -preset fast -g 100 -crf 21 -bufsize 1024k -maxrate 768k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset fast -tune film -g 100 -crf 25 -bufsize 768k -maxrate 768k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset fast -tune animation -g 100 -crf 25 -bufsize 768k -maxrate 768k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset veryslow -g 100 -crf 25 -bufsize 768k -maxrate 768k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"
#FFMPEGOPT=" -threads 0 -s 640x352 -r 29.97 -vcodec libx264 -preset placebo -g 100 -crf 25 -bufsize 768k -maxrate 768k -level 30 -sc_threshold 60 -refs 3 -async 50 -f h264 ${SRCDIR}/${FILEBODY}.264"

#CROPOPT=' -vf crop=in_w-16:in_h-12:8:6 '
#CROPOPT=''
#RESOLUTION=" -s 640x360 "
#MAXRATE=" -bufsize 768k -maxrate 768k "
#PRESET=" -preset medium "
#CRF=" -crf 21 "
#QCOMP=" -qcomp 0.7 "
#X264OPTS=" -x264opts me=umh:rc-lookahead=50:bframes=5 "
#BENCH=" -ssim 1 -benchmark "
#FFMPEGOPT=" -threads 0 $RESOLUTION -r 29.97 -vcodec libx264 $PRESET -g 250 $CRF $MAXRATE -level 30 -sc_threshold 50 -refs 5 -direct-pred auto -async 50 $QCOMP $X264OPTS $BENCH -f h264 ${SRCDIR}/${FILEBODY}.264"

# H.264 エンコード開始
log_out "ffmpeg $SPLITFILE 264 start."
log_out "$FFMPEG -y -i $SPLITFILE $CROPOPT $SSTIME $FFMPEGOPT"
nice -n 15 $FFMPEG -y -i "$SPLITFILE" $CROPOPT $SSTIME $FFMPEGOPT
RET=$?
log_out "ffmpeg $SPLITFILE 264 end :$RET"

# エラーになってたらcrop止めてみる。
if [ ! -e "${SRCDIR}/${FILEBODY}.264" ]; then
	log_out "ffmpeg no crop $SPLITFILE 264 start."
	log_out "$FFMPEG -y -i $SPLITFILE $SSTIME $FFMPEGOPT"
	nice -n 15 $FFMPEG -y -i "$SPLITFILE" $SSTIME $FFMPEGOPT
	RET=$?
	log_out "ffmpeg no crop $SPLITFILE 264 end :$RET"
fi

# それでもエラーならsplitしてないファイルをターゲットに
if [ ! -e "${SRCDIR}/${FILEBODY}.264" ]; then
	SPLITFILE="$INFILE"
	SSTIME=' -ss 00:00:02.000 ';

	log_out "ffmpeg no splited ts $SPLITFILE 264 start."
	log_out "$FFMPEG -y -i $SPLITFILE $SSTIME $FFMPEGOPT"
	nice -n 15 $FFMPEG -y -i "$SPLITFILE" $SSTIME $FFMPEGOPT
	RET=$?
	log_out "ffmpeg no splited ts  $SPLITFILE 264 end :$RET"
fi

# 終わり
if [ ! -e "${SRCDIR}/${FILEBODY}.264" ]; then
	log_out "ffmpeg err."
	exit 4
else
	log_out "H.264 encode file"
	log_out "`ls -lh ${SRCDIR}/${FILEBODY}.264`"
fi

# AAC抽出
#if [ -e "${SRCDIR}/${FILEBODY}.aac" ]; then
#	rm -f "${SRCDIR}/${FILEBODY}.aac"
#fi
#log_out "ffmpeg aac $SPLITFILE start."
#log_out "$FFMPEG -i $SPLITFILE $SSTIME -map 0:1 -vn -acodec copy ${SRCDIR}/${FILEBODY}.aac"
#$FFMPEG -i "$SPLITFILE" $SSTIME -map 0:1 -vn -acodec copy "${SRCDIR}/${FILEBODY}.aac"
#RET=$?
#log_out "ffmpeg aac $SPLITFILE end. :$RET"
#
## 終わり
#if [ ! -e "${SRCDIR}/${FILEBODY}.aac" ]; then
#	log_out "ffmpeg aac err."
#	exit 5
#else
#	log_out "aac file"
#	log_out "`ls -lh ${SRCDIR}/${FILEBODY}.aac`"
#fi

# AAC -> WAV抽出
if [ -e "${SRCDIR}/${FILEBODY}.wav" ]; then
	rm -f "${SRCDIR}/${FILEBODY}.wav"
fi
log_out "ffmpeg aac -> wav $SPLITFILE start."
log_out "$FFMPEG -i $SPLITFILE $SSTIME -map 0:1 -vn -acodec pcm_s16le -ac 2 ${SRCDIR}/${FILEBODY}.wav"
nice -n 15 $FFMPEG -i "$SPLITFILE" $SSTIME -map 0:1 -vn -acodec pcm_s16le -ac 2 "${SRCDIR}/${FILEBODY}.wav"
RET=$?
log_out "ffmpeg aac -> wav $SPLITFILE end. :$RET"

# 失敗してたらmplayerで試してみる
if [ ! -e "${SRCDIR}/${FILEBODY}.wav" ]; then
	log_out "mplayer aac -> wav start."
	log_out "$MPLAYER $SPLITFILE -vc null -vo null -ao pcm:file=${SRCDIR}/${FILEBODY}.wav:fast"
	nice -n 15 $MPLAYER "$SPLITFILE" -vc null -vo null -ao "pcm:file=${SRCDIR}/${FILEBODY}.wav:fast"
	RET=$?
	log_out "mplayer aac -> wav end. :$RET"
fi

# 終わり
if [ ! -e "${SRCDIR}/${FILEBODY}.wav" ]; then
	log_out "m2t -> aac err."
	exit 5
else
	log_out "wav file"
	log_out "`ls -lh ${SRCDIR}/${FILEBODY}.wav`"
fi

# WAV -> AACエンコード
if [ -e "${SRCDIR}/${FILEBODY}.aac" ]; then
	rm -f "${SRCDIR}/${FILEBODY}.aac"
fi
log_out "neroAacEnc wav -> aac start."
log_out "$NEROAACENC -br 128000 -if ${SRCDIR}/${FILEBODY}.wav -of ${SRCDIR}/${FILEBODY}.aac"
#$NEROAACENC -br 128000 -if "${SRCDIR}/${FILEBODY}.wav" -of "${SRCDIR}/${FILEBODY}.aac"
nice -n 15 $NEROAACENC -q 0.4 -hev2 -if "${SRCDIR}/${FILEBODY}.wav" -of "${SRCDIR}/${FILEBODY}.aac"
RET=$?
log_out "neroAacEnc wav -> aac end. :$RET"

# 失敗してたらfaacで試してみる
if [ ! -e "${SRCDIR}/${FILEBODY}.aac" ]; then
	log_out "faac wav -> aac start."
	log_out "$FAAC -w -q 100 -o ${SRCDIR}/${FILEBODY}.aac ${SRCDIR}/${FILEBODY}.wav"
	nice -n 15 $FAAC -w -q 100 -o "${SRCDIR}/${FILEBODY}.aac" "${SRCDIR}/${FILEBODY}.wav"
	RET=$?
	log_out "faac wav -> aac end. :$RET"
fi

# 終わり
if [ ! -e "${SRCDIR}/${FILEBODY}.aac" ]; then
	log_out "wav -> aac err."
	exit 6
else
	log_out "wav -> aac file"
	log_out "`ls -lh ${SRCDIR}/${FILEBODY}.aac`"
fi

# MP4 mux 264
log_out "MP4Box -add 264 -new ${SRCDIR}/${FILEBODY}.base.mp4  start."
log_out "$MP4BOX -tmp /tmp -fps 29.97 -add ${SRCDIR}/${FILEBODY}.264 -new ${SRCDIR}/${FILEBODY}.base.mp4"
nice -n 15 $MP4BOX -tmp /tmp -fps 29.97 -add "${SRCDIR}/${FILEBODY}.264" -new "${SRCDIR}/${FILEBODY}.base.mp4"
RET=$?
log_out "MP4Box -add 264 -new ${SRCDIR}/${FILEBODY}.base.mp4  end. :$RET"

if [ ! -e "${SRCDIR}/${FILEBODY}.base.mp4" ]; then
	log_out "MP4Box 264 add err."
	exit 7
else
	log_out "mp4 add 264"
	log_out "`ls -lh ${SRCDIR}/${FILEBODY}.base.mp4`"
fi

# MP4 mux aac
log_out "MP4Box -add aac ${SRCDIR}/${FILEBODY}.base.mp4  start."
log_out "$MP4BOX -tmp /tmp -add ${SRCDIR}/${FILEBODY}.aac ${SRCDIR}/${FILEBODY}.base.mp4"
nice -n 15 $MP4BOX -tmp /tmp -add "${SRCDIR}/${FILEBODY}.aac" "${SRCDIR}/${FILEBODY}.base.mp4"
RET=$?
log_out "MP4Box -add aac ${SRCDIR}/${FILEBODY}.base.mp4  end. :$RET"
log_out "`ls -lh ${SRCDIR}/${FILEBODY}.base.mp4`"

# iPodヘッダ付加
log_out "MP4Box -ipod ${SRCDIR}/${FILEBODY}.base.mp4"
log_out "$MP4BOX -tmp /tmp -ipod ${SRCDIR}/${FILEBODY}.base.mp4"
nice -n 15 $MP4BOX -tmp /tmp -ipod "${SRCDIR}/${FILEBODY}.base.mp4"
log_out "`ls -lh ${SRCDIR}/${FILEBODY}.base.mp4`"

# rename  base.mp4 -> .MP4
if [ -e "${SRCDIR}/${FILEBODY}.MP4" ]; then
	rm -f "${SRCDIR}/${FILEBODY}.MP4"
fi
log_out "mv ${SRCDIR}/${FILEBODY}.base.mp4 ${SRCDIR}/${FILEBODY}.MP4"
mv "${SRCDIR}/${FILEBODY}.base.mp4" "${SRCDIR}/${FILEBODY}.MP4"
log_out "`ls -lh ${SRCDIR}/${FILEBODY}.MP4`"

# サムネイル作成
log_out "call captureimage $SPLITFILE"
captureimage "$SPLITFILE"

# 結果表示
ENDDATE=`date '+%Y/%m/%d %H:%M:%S'`
declare -i PROCSEC=`date -d "$ENDDATE" '+%s'`-`date -d "$STARTDATE" '+%s'`
PROCESS=`perl -e "printf(\"%02d:%02d:%02d\", int($PROCSEC/3600), int($PROCSEC%3600/60), $PROCSEC%60);"`

INFILESIZE=`ls -lh "$INFILE"    | awk {'print $5'}`
SPFILESIZE=`ls -lh "$SPLITFILE" | awk {'print $5'}`
VIFILESIZE=`ls -lh "${SRCDIR}/${FILEBODY}.264" | awk {'print $5'}`
AUFILESIZE=`ls -lh "${SRCDIR}/${FILEBODY}.aac" | awk {'print $5'}`
M4FILESIZE=`ls -lh "${SRCDIR}/${FILEBODY}.MP4" | awk {'print $5'}`
THMDIRSIZE=`du -sh "${SRCDIR}/${FILEBODY}_img" | awk '{print $1}'`
THCOUNT=`ls -1 "${SRCDIR}/${FILEBODY}_img/" | wc -l`
COMP=`perl -e "\\$ts = -s \"$INFILE\"; \\$mp4 = -s \"${SRCDIR}/${FILEBODY}.MP4\"; printf(\"%s\n\", int(\\$mp4 / \\$ts * 100 * 100) / 100);"`
COMPP=`perl -e "print int($COMP * 100)"`

SUCCESS=1
if [ $COMPP -ge $SUCCESS_SIZE ]; then
	SUCCESS=0
fi
log_out "COMPP=$COMPP  SUCCESS_SIZE=$SUCCESS_SIZE  SUCCESS=$SUCCESS"

log_out ""
log_out "=========================== TS to MP4 ENCODE RESULT ==========================="
log_out "  TS    FILE      : `printf '%06s' $INFILESIZE` : $INFILE"
log_out "  SPLIT FILE      : `printf '%06s' $SPFILESIZE` : $SPLITFILE"
log_out "  VIDEO FILE      : `printf '%06s' $VIFILESIZE` : ${SRCDIR}/${FILEBODY}.264"
log_out "  AUDIO FILE      : `printf '%06s' $AUFILESIZE` : ${SRCDIR}/${FILEBODY}.aac"
log_out "  MP4   FILE      : `printf '%06s' $M4FILESIZE` : ${SRCDIR}/${FILEBODY}.MP4"
log_out "  THUMBNAIL DIR   : `printf '%06s' $THMDIRSIZE` : ${THCOUNT} files : ${SRCDIR}/${FILEBODY}_img"
log_out "  COMPRESSION RATE: `printf '%06s' $COMP`%"
log_out "  START   TIME    : ${STARTDATE}"
log_out "  END     TIME    : $ENDDATE"
log_out "  PROCESS TIME    : $PROCESS"
log_out "=========================== TS to MP4 ENCODE RESULT ==========================="
log_out ""

# 中間ファイル消す
if [ $SUCCESS -eq 0 ]; then
	if [ -e "${SRCDIR}/${FILEBODY}_tss.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_tss.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}_HD.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_HD.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}_SD1.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_SD1.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}_SD2.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_SD2.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}_SD3.m2t" ]; then
		rm -f "${SRCDIR}/${FILEBODY}_SD3.m2t"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}.264" ]; then
		rm -f "${SRCDIR}/${FILEBODY}.264"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}.aac" ]; then
		rm -f "${SRCDIR}/${FILEBODY}.aac"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}.wav" ]; then
		rm -f "${SRCDIR}/${FILEBODY}.wav"
	fi
	if [ -e "${SRCDIR}/${FILEBODY}.base.mp4" ]; then
		rm -f "${SRCDIR}/${FILEBODY}.base.mp4"
	fi
fi


log_out "$0 $INFILE End."
log_out ""

#vim: ts=4:sw=4

