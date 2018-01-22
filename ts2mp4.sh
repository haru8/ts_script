#!/bin/bash

TSSPY="/usr/local/apps/foltia/perl/tool/tss.py_"
TSSPLITTER="/usr/local/apps/foltia/perl/tool/TsSplitter.exe"
BONTSDEMUX="/usr/local/apps/foltia/perl/tool/BonTsDemuxC.exe"
FFMPEG="/usr/local/bin/ffmpeg"
MPLAYER="/usr/local/bin/mplayer"
NEROAACENC="/usr/local/bin/neroAacEnc"
FAAC="/usr/local/bin/faac"
MP4BOX="/usr/local/bin/MP4Box"

THUMB_S='288x162'
THUMB_L='1280x720'
SUCCESS_SIZE=200

LOGPATH="/tmp/ts2mp4.log"

# 1だとsplitしない
SPLITOFF=0


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
        if [ $valid -le 45 ]; then
            log_out "ERR File split may be fail. split file size is under 45%."
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
        log_out ""
    else
        local -i sd1size=0
    fi
    if [ -e "$sd2file" ]; then
        local -i sd2size=`ls -lk "$sd2file" | awk '{print $5}'`
        log_out "`ls -lh $sd2file`"
        log_out ""
    else
        local -i sd2size=0
    fi
    if [ -e "$sd3file" ]; then
        local -i sd3size=`ls -lk "$sd3file" | awk '{print $5}'`
        log_out "`ls -lh $sd3file`"
        log_out ""
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
    local -i sec=1
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
        CMD1="nice -n 5 $FFMPEG -loglevel quiet -ss $sec -y -i \"$infile\" -vframes 1 -s $THUMB_S -f image2 \"${outdir}/${num_s}.jpg\""
        CMD2="nice -n 5 $FFMPEG -loglevel quiet -ss $sec -y -i \"$infile\" -vframes 1 -s $THUMB_L -f image2 \"${outdir}/l/${num_s}.jpg\""
        #CMD1="nice -n 5 $FFMPEG -y -i \"$infile\" -s $THUMB_S -f image2 -vcodec mjpeg -r 0.1 \"${outdir}/%08d.jpg\""
        #CMD2="nice -n 5 $FFMPEG -y -i \"$infile\" -s $THUMB_L -f image2 -vcodec mjpeg -r 0.1 \"${outdir}/l/%08d.jpg\""
        #log_out $CMD1
        #log_out $CMD2
        eval $CMD1
        eval $CMD2
        retval=$?

        # ファイルが出来ていなかったら動画の末尾まで到達したと判定
        if [ $num -gt 6 -a ! -e "${outdir}/${num_s}.jpg" ]; then
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
log_out ""

# TSのディレクトリに書き込めなかったら終わる
if [ ! -w "$SRCDIR" ]; then
    log_out "output dir write err."
    exit 3;
fi

SPSTARTDATE=`date '+%Y/%m/%d %H:%M:%S'`
# BonTsDemux 実行
#if [ $SPLITOFF -ne 1 ]; then
#  if [ -x "$BONTSDEMUX" ]; then
#    SPOUT="${FILEBODY}_dem"
#    SPM2V="${SRCDIR}/${SPOUT}.m2v"
#    SPWAV="${SRCDIR}/${SPOUT}.wav"
#    # 既に有ったら消しておく
#    if [ -e "$SPM2V" ]; then
#      log_out "rm $SPM2V"
#      rm -f "$SPM2V"
#    fi
#    if [ -e "$SPWAV" ]; then
#      log_out "rm $SPWAV"
#      rm -f "$SPWAV"
#    fi
#    log_out "$BONTSDEMUX $INFILE  start."
#    nice -n 15 wine "$BONTSDEMUX" -i "$INFILE" -o "$SPOUT" -encode "Demux(m2v+wav)" -start -quit -sound 0 -nd
#    RET=$?
#    log_out "$BONTSDEMUX $INFILE  end. :$RET"
#
#    # M2Vが無かったらら終わる
#    if [ -e "$SPM2V" ]; then
#      log_out "split m2v exist."
#      log_out "`ls -lh $SPM2V`"
#      SPLITFILE="$SPM2V"
#    else
#      log_out "split m2v not exist."
#      exit 4
#    fi
#    # WAVが無かったらら終わる
#    if [ -e "$SPWAV" ]; then
#      log_out "split wav exist."
#      log_out "`ls -lh $SPWAV`"
#    else
#      log_out "split wav not exist."
#      exit 5
#    fi
#  fi
#fi

## HDのストリームのみ抽出
#if [ -x "$TSSPY" -a $SPLITOFF -ne 1 ]; then
#   # 既に有ったら消しておく
#   if [ -e "${SRCDIR}/${FILEBODY}_tss.m2t" ]; then
#       rm -f  "${SRCDIR}/${FILEBODY}_tss.m2t"
#   fi
#   if [ -e "${SRCDIR}/${FILEBODY}_HD.m2t" ]; then
#       rm -f "${SRCDIR}/${FILEBODY}_HD.m2t"
#   fi
#   if [ -e "${SRCDIR}/${FILEBODY}_SD1.m2t" ]; then
#       rm -f "${SRCDIR}/${FILEBODY}_SD1.m2t"
#   fi
#   if [ -e "${SRCDIR}/${FILEBODY}_SD2.m2t" ]; then
#       rm -f "${SRCDIR}/${FILEBODY}_SD2.m2t"
#   fi
#   if [ -e "${SRCDIR}/${FILEBODY}_SD3.m2t" ]; then
#       rm -f "${SRCDIR}/${FILEBODY}_SD3.m2t"
#   fi
#   log_out "$TSSPY $INFILE  start."
#   nice -n 15 "$TSSPY" "$INFILE"
#   RET=$?
#   log_out "$TSSPY $INFILE  end. :$RET"
#fi
#
## ファイルの最初は不安定なので捨てる
#SSTIME=' -ss 00:00:02.000 '
#
#if [ -e "${SRCDIR}/${FILEBODY}_tss.m2t" ]; then
#   SPLITFILE="${SRCDIR}/${FILEBODY}_tss.m2t"
#   log_out "tss.py split file"
#   log_out "`ls -lh $SPLITFILE`"
#else
#   log_out "ERR. NOT Exist ${SRCDIR}/${FILEBODY}_tss.m2t"
#   SPLITFILE=""
#fi
#
## splitしたファイルのチェック
#log_out "call validationsplitfile $INFILE $SPLITFILE"
#validationsplitfile "$INFILE" "$SPLITFILE"
#VALID=$?

VALID=1
## tss.pyに失敗してたらwineでTsSplit.exe
if [ $VALID -ne 0 -a $SPLITOFF -ne 1 ]; then
   if [ -e $TSSPLITTER ]; then
       log_out "wine $TSSPLITTER -EIT -ECM -EMM -1SEG $INFILE  start."
       nice -n 15 wine "$TSSPLITTER" -EIT -ECM -EMM -1SEG "$INFILE"
       RET=$?
       log_out "$TSSPLITTER  end. :$RET"

       if [ -e "${SRCDIR}/${FILEBODY}_HD.m2t" ]; then
           SPLITFILE="${SRCDIR}/${FILEBODY}_HD.m2t"
           log_out "TsSplit.exe split file"
           log_out "`ls -lh $SPLITFILE`"
           log_out ""

           # splitしたファイルのチェック
           log_out "call validationsplitfile $INFILE $SPLITFILE"
           validationsplitfile "$INFILE" "$SPLITFILE"
           VALID=$?

           # ファイルの最初は不安定なので捨てる
           SSTIME='-ss 00:00:02.000'
       else
           log_out "ERR. NOT Exist ${SRCDIR}/${FILEBODY}_SD[123].m2t"
           SPLITFILE=""
       fi
   fi
else
   # ファイルの最初は不安定なので捨てる
   SSTIME='-ss 00:00:02.000'
fi

## HDがだめならSDかも
#if [ $VALID -ne 0 -a $SPLITOFF -ne 1 ]; then
#   if [ -e "${SRCDIR}/${FILEBODY}_SD1.m2t" -o -e "${SRCDIR}/${FILEBODY}_SD2.m2t" -o -e "${SRCDIR}/${FILEBODY}_SD3.m2t" ]; then
#       log_out "call validationsplitfileSD $INFILE ${SRCDIR}/${FILEBODY}_SD1.m2t ${SRCDIR}/${FILEBODY}_SD2.m2t ${SRCDIR}/${FILEBODY}_SD3.m2t"
#       validationsplitfileSD "$INFILE" "${SRCDIR}/${FILEBODY}_SD1.m2t" "${SRCDIR}/${FILEBODY}_SD2.m2t" "${SRCDIR}/${FILEBODY}_SD3.m2t"
#       RET=$?
#       if [ $RET -eq 1 ]; then
#           SPLITFILE="${SRCDIR}/${FILEBODY}_SD1.m2t"
#           VALID=0
#           SSTIME=' -ss 00:00:00.000 '
#       elif [ $RET -eq 2 ]; then
#           SPLITFILE="${SRCDIR}/${FILEBODY}_SD2.m2t"
#           VALID=0
#           SSTIME=' -ss 00:00:00.000 '
#       elif [ $RET -eq 3 ]; then
#           SPLITFILE="${SRCDIR}/${FILEBODY}_SD3.m2t"
#           VALID=0
#           SSTIME=' -ss 00:00:00.000 '
#       else
#           SPLITFILE="$INFILE"
#           SSTIME=' -ss 00:00:02.000 '
#       fi
#   fi
#fi
#if [ $SPLITOFF -eq 1 ]; then
#   SPLITFILE="$INFILE"
#   SSTIME=' -ss 00:00:02.000 '
#   log_out "SPLITOFF = $SPLITOFF, Split OFF."
#fi
SPENDDATE=`date '+%Y/%m/%d %H:%M:%S'`
log_out "SPLITFILE = $SPLITFILE"


#CROPOPT=' -vf crop=in_w-16:in_h-12:8:6 '
CROPOPT=''
#SSTIME="-ss 00:00:02.000"
SSTIME=""
THREADS="-threads 0"
RESOLUTION="-s 640x360"
ASPECT="-aspect 16:9"
FRAMERATE="-r 30000/1001"
MAXRATE="-bufsize 1152K -maxrate 1152K"
REFS="-refs 13"
#PRESET="-preset ultrafast"
PRESET="-preset veryslow"
#TUNE="-tune film"
TUNE="-tune animation"
CRF="-crf 22"
#QCOMP=" -qcomp 0.7 "
QCOMP=""
X264OPTS="-x264opts merange=32:no-dct-decimate"
VF="-vf yadif"
AACOPT="-ac 2 -ar 48000 -vbr 4"
#SYNC="-async 200"
SYNC="-vsync 1"
BENCH="-ssim 1 -benchmark"
OUTPUTFILE="${SRCDIR}/${FILEBODY}.base.mp4"

FFMPEGOPT="$THREADS $RESOLUTION $ASPECT $FRAMERATE -f mp4
  -vcodec libx264 $PRESET $CRF $MAXRATE $REFS $TUNE $QCOMP $X264OPTS $VF
  -acodec libfdk_aac $AACOPT $SYNC $BENCH $OUTPUTFILE"

# H.264 エンコード開始
ENCSTARTDATE=`date '+%Y/%m/%d %H:%M:%S'`
log_out "ffmpeg $SPLITFILE 264<mp4> start."
FFMPEGEXEC="nice -n 15 $FFMPEG -y -i \"$SPLITFILE\" $CROPOPT $SSTIME $FFMPEGOPT"
log_out "$FFMPEGEXEC"
eval $FFMPEGEXEC
RET=$?
log_out "ffmpeg $SPLITFILE 264<mp4> end :$RET"

## エラーになってたらcrop止めてみる。
#if [ ! -e "$OUTPUTFILE" ]; then
#    log_out "ffmpeg no crop $SPLITFILE 264<mp4> start."
#    FFMPEGEXEC="nice -n 15 $FFMPEG -y -i \"$SPLITFILE\" $SSTIME $FFMPEGOPT"
#    log_out "$FFMPEGEXEC"
#    eval $FFMPEGEXEC
#    RET=$?
#    log_out "ffmpeg no crop $SPLITFILE 264<mp4> end :$RET"
#fi

# それでもエラーならsplitしてないファイルをターゲットに
#if [ ! -e "$OUTPUTFILE" ]; then
#    SPLITFILE="$INFILE"
#    SSTIME='';
#
#    log_out "ffmpeg no splited ts $SPLITFILE 264<mp4> start."
#    FFMPEGEXEC="nice -n 15 $FFMPEG -y -i \"$SPLITFILE\" $SSTIME $FFMPEGOPT"
#    log_out "$FFMPEGEXEC"
#    eval $FFMPEGEXEC
#    RET=$?
#    log_out "ffmpeg no splited ts  $SPLITFILE 264<mp4> end :$RET"
#fi

# 終わり
if [ ! -e "$OUTPUTFILE" ]; then
    log_out "ffmpeg err."
    exit 6
else
    log_out "H.264<mp4> encode file"
    log_out "`ls -lh $OUTPUTFILE`"
    log_out ""
fi
ENCENDDATE=`date '+%Y/%m/%d %H:%M:%S'`

AACSTARTDATE=`date '+%Y/%m/%d %H:%M:%S'`
# 存在してたら消す
#if [ -e "${SRCDIR}/${FILEBODY}.aac" ]; then
#    rm -f "${SRCDIR}/${FILEBODY}.aac"
#fi
#if [ -e "${SRCDIR}/${FILEBODY}.wav" ]; then
#    rm -f "${SRCDIR}/${FILEBODY}.wav"
#fi

# splitしてないファイルがターゲットだったらwav抽出
#if [ "$SPLITFILE" = "$INFILE" ]; then
#  # TS -> WAV抽出
#  log_out "ffmpeg ts -> wav $SPLITFILE start."
#  log_out "$FFMPEG -i $SPLITFILE $SSTIME -map 0:1 -vn -acodec pcm_s16le -ac 2 ${SRCDIR}/${FILEBODY}.wav"
#  nice -n 15 $FFMPEG -i "$SPLITFILE" $SSTIME -map 0:1 -vn -acodec pcm_s16le -ac 2 "${SRCDIR}/${FILEBODY}.wav"
#  RET=$?
#  log_out "ffmpeg aac -> wav $SPLITFILE end. :$RET"
#
#  EXTWAV="${SRCDIR}/${FILEBODY}.wav"
#
#  ## 失敗してたらmplayerで試してみる
#  #if [ ! -e "${SRCDIR}/${FILEBODY}.wav" ]; then
#  # log_out "mplayer aac -> wav start."
#  # log_out "$MPLAYER $SPLITFILE -vc null -vo null -ao pcm:file=${SRCDIR}/${FILEBODY}.wav:fast"
#  # nice -n 15 $MPLAYER "$SPLITFILE" -vc null -vo null -ao "pcm:file=${SRCDIR}/${FILEBODY}.wav:fast"
#  # RET=$?
#  # log_out "mplayer aac -> wav end. :$RET"
#  #fi
#else
#  EXTWAV="${SPWAV}"
#fi

#if [ -e $EXTWAV ]; then
#  log_out "EXTWAV = $EXTWAV"
#  log_out "`ls -lh $EXTWAV`"
#else
#  log_out "extract wav not exist."
#  exit 7
#fi

#log_out "ffmpeg aac $SPLITFILE start."
#log_out "$FFMPEG -i $SPLITFILE $SSTIME -map 0:1 -vn -acodec copy ${SRCDIR}/${FILEBODY}.aac"
#$FFMPEG -i "$SPLITFILE" $SSTIME -map 0:1 -vn -acodec copy "${SRCDIR}/${FILEBODY}.aac"
#RET=$?
#log_out "ffmpeg aac $SPLITFILE end. :$RET"
#
## 終わり
#if [ ! -e "${SRCDIR}/${FILEBODY}.aac" ]; then
#   log_out "ffmpeg aac err."
#   exit 5
#else
#   log_out "aac file"
#   log_out "`ls -lh ${SRCDIR}/${FILEBODY}.aac`"
#fi

#
## 終わり
#if [ ! -e "${SRCDIR}/${FILEBODY}.wav" ]; then
#   log_out "m2t -> aac err."
#   exit 5
#else
#   log_out "wav file"
#   log_out "`ls -lh ${SRCDIR}/${FILEBODY}.wav`"
#fi
#
## WAV -> AACエンコード
#if [ -e "${SRCDIR}/${FILEBODY}.aac" ]; then
#   rm -f "${SRCDIR}/${FILEBODY}.aac"
#fi
#log_out "neroAacEnc wav -> aac start."
#log_out "$NEROAACENC -q 0.4 -hev2 -if ${EXTWAV} -of ${SRCDIR}/${FILEBODY}.aac"
##$NEROAACENC -br 128000 -if "${SRCDIR}/${FILEBODY}.wav" -of "${SRCDIR}/${FILEBODY}.aac"
#nice -n 15 $NEROAACENC -q 0.4 -hev2 -if "${EXTWAV}" -of "${SRCDIR}/${FILEBODY}.aac"
#RET=$?
#log_out "neroAacEnc wav -> aac end. :$RET"

## 失敗してたらfaacで試してみる
#if [ ! -e "${SRCDIR}/${FILEBODY}.aac" ]; then
#   log_out "faac wav -> aac start."
#   log_out "$FAAC -w -q 100 -o ${SRCDIR}/${FILEBODY}.aac ${SRCDIR}/${FILEBODY}.wav"
#   nice -n 15 $FAAC -w -q 100 -o "${SRCDIR}/${FILEBODY}.aac" "${SRCDIR}/${FILEBODY}.wav"
#   RET=$?
#   log_out "faac wav -> aac end. :$RET"
#fi

# 終わり
#if [ ! -e "${SRCDIR}/${FILEBODY}.aac" ]; then
#    log_out "wav -> aac err."
#    exit 7
#else
#    log_out "wav -> aac file"
#    log_out "`ls -lh ${SRCDIR}/${FILEBODY}.aac`"
#fi
AACENDDATE=`date '+%Y/%m/%d %H:%M:%S'`

# MP4 mux 264
MUXSTARTDATE=`date '+%Y/%m/%d %H:%M:%S'`
#log_out "MP4Box -add 264 -new ${SRCDIR}/${FILEBODY}.base.mp4  start."
#log_out "$MP4BOX -tmp /tmp -fps 29.97 -add ${SRCDIR}/${FILEBODY}.264 -new ${SRCDIR}/${FILEBODY}.base.mp4"
#nice -n 15 $MP4BOX -tmp /tmp -fps 29.97 -add "${SRCDIR}/${FILEBODY}.264" -new "${SRCDIR}/${FILEBODY}.base.mp4"
#RET=$?
#log_out "MP4Box -add 264 -new ${SRCDIR}/${FILEBODY}.base.mp4  end. :$RET"
#
#if [ ! -e "${SRCDIR}/${FILEBODY}.base.mp4" ]; then
#    log_out "MP4Box 264 add err."
#    exit 7
#else
#    log_out "mp4 add 264"
#    log_out "`ls -lh ${SRCDIR}/${FILEBODY}.base.mp4`"
#fi

# MP4 mux aac
#log_out "MP4Box -add aac ${SRCDIR}/${FILEBODY}.base.mp4  start."
#log_out "$MP4BOX -tmp /tmp -add ${SRCDIR}/${FILEBODY}.aac ${SRCDIR}/${FILEBODY}.base.mp4"
#nice -n 15 $MP4BOX -tmp /tmp -add "${SRCDIR}/${FILEBODY}.aac" "${SRCDIR}/${FILEBODY}.base.mp4"
#RET=$?
#log_out "MP4Box -add aac ${SRCDIR}/${FILEBODY}.base.mp4  end. :$RET"
#log_out "`ls -lh ${SRCDIR}/${FILEBODY}.base.mp4`"

# iPodヘッダ付加
#log_out "MP4Box -ipod $OUTPUTFILE"
#log_out "$MP4BOX -tmp /tmp -ipod $OUTPUTFILE"
#nice -n 15 $MP4BOX -tmp /tmp -ipod "$OUTPUTFILE"
#log_out "`ls -lh $OUTPUTFILE`"
#log_out ""
MUXENDDATE=`date '+%Y/%m/%d %H:%M:%S'`

# rename  base.mp4 -> .MP4
if [ -e "${SRCDIR}/${FILEBODY}.MP4" ]; then
    rm -f "${SRCDIR}/${FILEBODY}.MP4"
fi
log_out "mv $OUTPUTFILE ${SRCDIR}/${FILEBODY}.MP4"
mv "$OUTPUTFILE" "${SRCDIR}/${FILEBODY}.MP4"
log_out "`ls -lh ${SRCDIR}/${FILEBODY}.MP4`"
log_out ""

# サムネイル作成
THUSTARTDATE=`date '+%Y/%m/%d %H:%M:%S'`
log_out "call captureimage $SPLITFILE"
captureimage "$SPLITFILE"
THUENDDATE=`date '+%Y/%m/%d %H:%M:%S'`

# 結果表示
ENDDATE=`date '+%Y/%m/%d %H:%M:%S'`
declare -i PROCSEC=`date -d "$ENDDATE" '+%s'`-`date -d "$STARTDATE" '+%s'`
PROCESS=`perl -e "printf(\"%02d:%02d:%02d\", int($PROCSEC/3600), int($PROCSEC%3600/60), $PROCSEC%60);"`

declare -i SPSEC=`date -d "$SPENDDATE" '+%s'`-`date -d "$SPSTARTDATE" '+%s'`
SPTIME=`perl -e "printf(\"%02d:%02d:%02d\", int($SPSEC/3600), int($SPSEC%3600/60), $SPSEC%60);"`

declare -i ENCSEC=`date -d "$ENCENDDATE" '+%s'`-`date -d "$ENCSTARTDATE" '+%s'`
ENCTIME=`perl -e "printf(\"%02d:%02d:%02d\", int($ENCSEC/3600), int($ENCSEC%3600/60), $ENCSEC%60);"`

declare -i AACSEC=`date -d "$AACENDDATE" '+%s'`-`date -d "$AACSTARTDATE" '+%s'`
AACTIME=`perl -e "printf(\"%02d:%02d:%02d\", int($AACSEC/3600), int($AACSEC%3600/60), $AACSEC%60);"`

declare -i MUXSEC=`date -d "$MUXENDDATE" '+%s'`-`date -d "$MUXSTARTDATE" '+%s'`
MUXTIME=`perl -e "printf(\"%02d:%02d:%02d\", int($MUXSEC/3600), int($MUXSEC%3600/60), $MUXSEC%60);"`

declare -i THUSEC=`date -d "$THUENDDATE" '+%s'`-`date -d "$THUSTARTDATE" '+%s'`
THUTIME=`perl -e "printf(\"%02d:%02d:%02d\", int($THUSEC/3600), int($THUSEC%3600/60), $THUSEC%60);"`


INFILESIZE=`ls -lh "$INFILE"    | awk {'print $5'}`
SPFILESIZE=`ls -lh "$SPLITFILE" | awk {'print $5'}`
#EXTWAVSIZE=`ls -lh "$EXTWAV"    | awk {'print $5'}`
#VIFILESIZE=`ls -lh "${SRCDIR}/${FILEBODY}.264" | awk {'print $5'}`
#AUFILESIZE=`ls -lh "${SRCDIR}/${FILEBODY}.aac" | awk {'print $5'}`
M4FILESIZE=`ls -lh "${SRCDIR}/${FILEBODY}.MP4" | awk {'print $5'}`
THMDIRSIZE=`du -sh "${SRCDIR}/${FILEBODY}_img" | awk '{print $1}'`
THCOUNT=`ls -1 "${SRCDIR}/${FILEBODY}_img/" | wc -l`
COMP=`perl -e "\\$ts = -s \"$INFILE\"; \\$mp4 = -s \"${SRCDIR}/${FILEBODY}.MP4\"; printf(\"%s\n\", int(\\$mp4 / \\$ts * 100 * 100) / 100);"`
COMPP=`perl -e "print int($COMP * 100);"`

SUCCESS=1
if [ $COMPP -ge $SUCCESS_SIZE ]; then
    SUCCESS=0
fi
log_out "COMPP=$COMPP  SUCCESS_SIZE=$SUCCESS_SIZE  SUCCESS=$SUCCESS"

log_out ""
log_out "=========================== TS to MP4 ENCODE RESULT ==========================="
log_out "  TS    FILE      : `printf '%06s' $INFILESIZE` : $INFILE"
log_out "  SPLIT FILE      : `printf '%06s' $SPFILESIZE` : $SPLITFILE"
#log_out "  EXT WAV FILE    : `printf '%06s' $EXTWAVSIZE` : $EXTWAV"
#log_out "  VIDEO FILE      : `printf '%06s' $VIFILESIZE` : ${SRCDIR}/${FILEBODY}.264"
#log_out "  AUDIO FILE      : `printf '%06s' $AUFILESIZE` : ${SRCDIR}/${FILEBODY}.aac"
log_out "  MP4   FILE      : `printf '%06s' $M4FILESIZE` : ${SRCDIR}/${FILEBODY}.MP4"
log_out "  THUMBNAIL DIR   : `printf '%06s' $THMDIRSIZE` : ${THCOUNT} files : ${SRCDIR}/${FILEBODY}_img"
log_out "  COMPRESSION RATE: `printf '%06s' $COMP`%"
log_out "  START   TIME    : ${STARTDATE}"
log_out "  END     TIME    : ${ENDDATE}"
log_out "  PROCESS TIME    : ${PROCESS}"
log_out "    SP TIME       : ${SPTIME}"
log_out "    ENC TIME      : ${ENCTIME}"
#log_out "    AAC TIME      : ${AACTIME}"
#log_out "    MUX TIME      : ${MUXTIME}"
log_out "    THU TIME      : ${THUTIME}"
log_out "=========================== TS to MP4 ENCODE RESULT ==========================="
log_out ""

# 中間ファイル消す
if [ $SUCCESS -eq 0 ]; then
    if [ -e "$SPM2V" ]; then
        rm -f "$SPM2V"
    fi
    if [ -e "$SPWAV" ]; then
        rm -f "$SPWAV"
    fi
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

