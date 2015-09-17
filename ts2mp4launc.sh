#!/bin/sh

TS2MP4=/usr/local/apps/foltia/bin/ts2mp4.sh
SLEEP=600
LOGPATH=/tmp/ts2mp4launc.log

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
	echo "$date: `printf %06d $$`: $mes" >> $LOGPATH
	echo "$mes"
}

processfind () {
	local list="$@"
	local -i count=0
	local -i psc

	for process in $list; do
		psc=`ps --no-headers -C "$process" | wc -l`
		count=$count+$psc
	done

	#echo $count
	return $count
}

TS="$@"
log_out ""
log_out "====================== $0 START ======================"

for file in $TS; do
	PROCESS=1
	while [ $PROCESS -ne 0 ]; do
		processfind ipodtranscode.pl ffmpeg
		PROCESS=$?
		if [ $PROCESS -eq 0 ]; then
			break
		else
			log_out "run process count=$PROCESS. sleep wait $SLEEP"
			sleep $SLEEP
		fi
	done
	log_out "  ================= launch START. $file ================="
	log_out "  $TS2MP4 $file"
	$TS2MP4 $file
	log_out "  ================= launch END.   $file ================="
	log_out ""
	
done

log_out "====================== $0 END   ======================"

