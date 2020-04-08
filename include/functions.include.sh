#!/bin/bash
# piGardenSched
# "functions.include.sh"
# Author: androtto
# VERSION=0.3.6
# 2020/03/25: added check_testfile function & check
# 2020/01/19: added EV#_PROGRESSIVE variables parsing
# 2019/09/12: setTMP_PATH added
# 2019/09/02: rain delay fixed 
# 2019/09/02: irrigation history improved - now it accepts ev_alias to display
# 2019/08/13: irrigation history improved - now it accepts number of events to display
# 2019/07/25: log reading is improved
# 2019/07/15: help fixed
#
sec2date()
{
        date --date="@$1"
}

debug()
{
	if [[ $debug = "yes" ]] ; then
		return 0
	else
		return 1
	fi
}


verbose()
{
	if [[ $verbose = "yes" ]] ; then
		return 0
	else
		return 1
	fi
}


setTMP_PATH()
{
	if [[ $(df  | awk '$NF=="/tmp" {print $1}') != "tmpfs" ]] ; then
		echo "WARNING: /tmp isn't a tmp file system"
		echo "please add to your /etc/fstab file:\ntmpfs           /tmp            tmpfs   defaults,noatime,nosuid   0       0"
	fi
}

d() # short date & time
{
	date '+%X-%x'
}

en_echo() # enhanched echo - check verbose variable
{
        if [[ $1 =~ ERROR || $1 =~ WARNING || $verbose = yes ]] ; then
		 echo -e "$(date) - $*"
	fi
}

help()
{
echo "SYNOPSIS:
$NAME_SCRIPT cronadd|crondel|croncheck
	manages cron entry in crontab - add, delete or check
$NAME_SCRIPT show|sched
	shows sched config file without comments
$NAME_SCRIPT stat|status
	gets status of last scheduled irrigation
$NAME_SCRIPT reset
	resetting status of last irrigations
$NAME_SCRIPT add EV? duration time frequency
	add schedule to $PIGARDENSCHED schedule file 
	example $NAME_SCRIPT add EV5 10 10:30 1
$NAME_SCRIPT del EV?
	remove EV? from schedule file $PIGARDENSCHED
	example $NAME_SCRIPT del EV5
$NAME_SCRIPT change_dur EV? minutes
	changes duration (only first occurance)
	example $NAME_SCRIPT change_dur EV5 10
$NAME_SCRIPT change_freq EV? days
	changes frequency (only first occurance)
	example $NAME_SCRIPT change_freq EV5 1
$NAME_SCRIPT change_time EV? time
	changes schedule (removed if more than one)
	example $NAME_SCRIPT change_time EV5 10:30 
$NAME_SCRIPT add_time EV? time (frequency must be 1)
	add new schedule time to $PIGARDENSCHED schedule file
	example $NAME_SCRIPT add_time EV5 13:50
$NAME_SCRIPT del_time EV? time (frequency must be 1)
	delete schedule time from $PIGARDENSCHED schedule file
	example $NAME_SCRIPT del_time EV5 13:50
$NAME_SCRIPT seq EV1 EV2
        create sequential irrigation as per indicated
	example $NAME_SCRIPT seq EV1 EV2 EV3 EV4
$NAME_SCRIPT noseq
        convert sequential irrigation in scheduled irrigation (each EV with its scheduling)
$NAME_SCRIPT enable EV?
	enable EV? for scheduling in file $PIGARDENSCHED
	example $NAME_SCRIPT enable EV5
$NAME_SCRIPT disable EV?
	disable EV? for scheduling in file $PIGARDENSCHED
	example $NAME_SCRIPT disable EV5
$NAME_SCRIPT history
	showing history for scheduled irrigations
$NAME_SCRIPT irrigation [# events] [EV?]
	gets status of effective irrigations per each EV
		number events is optional and if present it lists irrigations just for those numbers of events
		EV? is optional and can be used to filter output
$NAME_SCRIPT help|-h
	print [this] help
$NAME_SCRIPT 
	no args, execute scheduling
"
}

parsingfilesched()
{
	unset EVALIAS LONG TIME_SCHED DAYFREQ ACTIVE EVLABEL SEQ SEQLABEL numline seqnum
#	unset SEQ SEQLABEL seqnum
	declare -g SEQ SEQLABEL seqnum

	cfg_file="$1"
	(( numline=0 ))
	(( seqnum = 0 )) # be initialized outside of the loop
	while read line
	do
		[[ "$line" =~ ^# ]] && continue #ignore line if comented
		(( numline+=1 ))

		if [[ "$line" != "${line//[[:blank:]]/}" ]] ; then
			echo "ERROR: space(s)/blank(s) NOT allowed in $cfg_file config file"
			echo "       in line $line"
			exit 1 
		fi

		set -- ${line//;/ }
		EVALIAS[$numline]=$1
		LONG[$numline]=$2
		TIME_SCHED[$numline]=$3
		DAYFREQ[$numline]=$4
		ACTIVE[$numline]=$5

		local alias=${EVALIAS[numline]}_ALIAS
		EVLABEL[$numline]=${!alias}
		local alias=${EVALIAS[numline]/_*/}_NORAIN_RAINSENSORQTY
		EVNORAINQTY[$numline]=${!alias}
		local alias=${EVALIAS[numline]/_*/}_NORAIN
		EVNORAINCLASSIC[$numline]=${!alias}

		local alias=${EVALIAS[numline]/_*/}_PROGRESSIVE_RAINSENSORQTY
		EVPROGRESSIVE[$numline]=${!alias}

		check_number ${LONG[$numline]} >/dev/null 2>&1 || { echo "ERROR: evalias $1 has duration with wrong format ($2)" ; exit 1 ; }

		check_evalias ${EVALIAS[$numline]} >/dev/null 2>&1 || { echo "ERROR: evalias $1 is wrong format or NOT in range (EV_TOTAL = $EV_TOTAL )" ; exit 1 ; }
		
		(( num_timesched = 0 ))
		for time_sched in ${TIME_SCHED[$numline]//,/ }
		do
			(( num_timesched += 1 ))
			if check_evalias $time_sched >/dev/null 2>&1 ; then
				if [[ -z ${SEQ[$seqnum]} ]] ; then
					SEQ[$seqnum]="$3 $1"
					SEQLABEL[$seqnum]="$evlabelprev ${EVLABEL[$numline]}"
				else
					if [[ $3 = $aliasprev ]] ; then
						SEQ[$seqnum]="${SEQ[$seqnum]} $1"
						SEQLABEL[$seqnum]="${SEQLABEL[$seqnum]} ${EVLABEL[$numline]}"
					else
						echo "ERROR: $line is not referenced correctly to previous line $lineprev"
	 					exit 1
					fi
				fi
			else
				[[ ! -z ${SEQ[$seqnum]} ]] && (( seqnum += 1 ))
				if ! check_timeformat $time_sched >/dev/null 2>&1 ; then
					echo "ERROR: $time_sched - time format in #$num_timesched position in $line is NOT correct"
					exit 1
				fi
				if [[ $# != 5 ]] ; then
					echo "ERROR: there are not 5 fields (; separated) in $line line"
					exit 1
				fi
				case ${ACTIVE[$numline]} in
					"active") : ;; #ok
					"inactive") : ;; #ok
					*) echo "ERROR: 5th field is not 'active' or 'inactive' (line is $line)"
					   exit 1
					   ;;
				esac
			fi
		done
		if (( num_timesched >= 2 )) ; then
			if [[ ${DAYFREQ[$numline]} -ne 1 ]] ; then
				echo "ERROR: $num_timesched scheduled time ( ${TIME_SCHED[$numline]} ) in line $line, dayfreq MUST be 1"
				exit 1
			fi
		fi
			
		evlabelprev=${EVLABEL[$numline]}

		lineprev=$line
		aliasprev=${EVALIAS[$numline]}

	done < $cfg_file


	# numero linee totali: - numline incremento in testa - corretto in uscita dal loop il numero degli elementi totali
	# vecchio (( maxline=numline-1 ))
	(( maxline = numline ))

#	en_echo "NORMAL: $cfg_file successfully parsed & validated"

	for ((seqnum=0;seqnum<${#SEQ[@]};seqnum++))
	do
#		echo DEBUG $seqnum
#		echo DEBUG "${SEQ[$seqnum]}" 
#		echo DEBUG "${SEQLABEL[$seqnum]}" 
		if ! check_sequential "${SEQ[$seqnum]}" ; then
			echo "ERROR: wrong sequential/concatenation found in $cfg_file config file"
			exit 1
		fi
	done
	
	#debugshowparsed ; exit

}

debugshowparsed()
{
	echo DEBUG
	for ((numline=1;numline<=maxline;numline++))
        do
		echo \${EVALIAS[$numline]} ${EVALIAS[$numline]}
		echo \${LONG[$numline]} ${LONG[$numline]}
		echo \${TIME_SCHED[$numline]} ${TIME_SCHED[$numline]}
		echo \${DAYFREQ[$numline]} ${DAYFREQ[$numline]}
		echo \${ACTIVE[$numline]} ${ACTIVE[$numline]}
		echo \${EVLABEL[$numline]} ${EVLABEL[$numline]}
		echo \${EVNORAINQTY[$numline]} ${EVNORAINQTY[$numline]}
		echo \${EVNORAINCLASSIC[$numline]} ${EVNORAINCLASSIC[$numline]}
		echo \${EVPROGRESSIVE[$numline]} ${EVPROGRESSIVE[$numline]}
		echo
	done
	echo \${#SEQ[\@]} \${SEQ[\*]} ${#SEQ[@]} ${SEQ[*]}
	read x
}


getidx()
{
	declare -g idx
	local where=$1
	local what=$2
	for ((ii=1;ii<=maxline;ii++))
        do
		case $where in
			evlabel) if [[ $what = ${EVLABEL[$ii]} ]] ; then
					(( idx = ii ))
					return 0
				 fi
				 ;;
			evalias) if [[ $what = ${EVALIAS[$ii]} ]] ; then
					(( idx = ii ))
					return 0
				 fi
		esac
	done
	return 1
}

statupdate_sched()
{
	echo $now > $statfile
	echo $now >> $histfile
}

statupdate_irrigation()
{
	#echo DEBUG $2:$3 $STATDIR/${1}-irrigationhistory
	#called statupdate_irrigation $evlabel $start_secs $irrigation_mins
	echo $2:$3 >> $STATDIR/${1}-irrigationhistory
}

reduce_irrigation()
{
if [[ -z $progressive_factor ]] ; then
	progressive_factor=1
fi
$JQ -n "$1 * $progressive_factor " | $JQ 'if . == (.|floor) then
.
else
(.|floor)+1
end'
}

irrigazione()
{

	declare -g irrigated
	local logfile=$LOGDIR/${EVLABEL[$numline]}-${time_sched}.log

	#check if concatenated
	if check_concatenated ${EVALIAS[$numline]} ; then
		type=multi
	else
		type=single
	fi
	#seqnum variable set by check_concatenated function 

	evlist=""
	evlist_label=""
	if [[ $type = single ]] ; then
		if [[ ${EVPROGRESSIVE[$numline]} == 1 ]] ; then
			newlong=$( reduce_irrigation ${LONG[$numline]} )
			if (( $newlong < ${LONG[$numline]} )) ; then
				echo "${EVLABEL[$numline]} EV irrigation will be reduced from ${LONG[$numline]} to $newlong minutes because of partial rain and PROGRESSIVE irrigation settings"
				LONG[$numline]=$newlong
			fi
		fi
		evlist="${EVLABEL[$numline]}:${LONG[$numline]}"
		evlist_label="${EVLABEL[$numline]}"
	else # concatenated
		prevprog=0 # use to heritage progressive settings from main EV of concatenation
		for evalias in ${SEQ[$seqnum]}
		do
	                if ! getidx evalias $evalias ; then
				echo "ERROR: in function \"getidx evalias \$evalias ($evalias)\" "
			fi

			if [[ ${EVPROGRESSIVE[$idx]} == 1 || $prevprog == 1 ]] ; then
				prevprog=1
				#verbose && echo "progressive irrigation enabled"
				#echo ${LONG[$idx]} prima
				newlong=$( reduce_irrigation ${LONG[$idx]} )
				if (( $newlong < ${LONG[$idx]} )) ; then
					echo "${EVLABEL[$idx]} EV irrigation will be reduced from ${LONG[$idx]} to $newlong minutes because of partial rain and PROGRESSIVE irrigation settings"
					LONG[$idx]=$newlong
				fi
				#echo ${LONG[$idx]} dopo
			fi

			evlist="$evlist ${EVLABEL[$idx]}:${LONG[$idx]}"
			evlist_label="$evlist_label ${EVLABEL[$idx]}"
		done
	fi

	if [[ ${ACTIVE[$numline]} = inactive ]] ; then
		echo "$(date) - WARNING: $type irrigation for $evlist_label EV ( scheduled EV is ${EVLABEL[$numline]} ) is INACTIVE - irrigation skipped"
		return 1
	else
		echo "$(date) - $type irrigation for $evlist_label EV(s) ( scheduled EV is ${EVLABEL[$numline]} ) is running"

		echo "$(date) - EV ${EVLABEL[$numline]} lastrun updated with \"${date_now}\" timestamp"
		statupdate_sched
	
		echo -e "$(date) - running nohup command\n\t\t\"$irrigating $evlist\"\n\t\tcheck logfile $logfile "
		nohup $irrigating $evlist >> $logfile 2>&1 &
		irrigated="yes"
	fi
	return 0
}

schedule()
{
# gestione schedulazione
(( numline=1 ))
while (( numline <= maxline ))
do
   for time_sched in ${TIME_SCHED[$numline]//,/ }
   do
		if [[ "$time_sched" == "$time_now" ]] ; then
			echo # per rendere leggibile il log file
			debug && echo "DEBUG: now is $now"
			echo "DEBUG: now is $now"

			check_testflag

			statfile=$STATDIR/${EVALIAS[$numline]}-${time_sched}.lastrun
			histfile=$STATDIR/${EVALIAS[$numline]}-${time_sched}.history
#			echo DEBUG "$date_now - ${EVALIAS[$numline]} presente schedulazione - verifico se compatibile con frequenza"
			dayfreq=${DAYFREQ[$numline]}
			if [[ -f $statfile ]] ; then
				# se c'e' il file con l'ultima irrigazione ne leggo il contenuto
				lst_irrgtn="$(<$statfile)"
				(( now == lst_irrgtn )) && { echo "ERROR in DEBUG: now = lst_irrgtn"; exit 1; }
				(( chk_irrgtn=lst_irrgtn+dayfreq*24*60*60 ))
				echo "$(date) - EV ${EVLABEL[$numline]} last irrigation was on \"$(sec2date $lst_irrgtn)\" "
			else
				# non c'e' il file con l'ultima erogazione
				(( lst_irrgtn = now-dayfreq*24*60*60 ))
				(( chk_irrgtn = lst_irrgtn+dayfreq*24*60*60 )) # = now
			fi
			echo "$(date) - EV ${EVLABEL[$numline]} irrigation is every $dayfreq day(s) at $time_sched"

			if (( now < chk_irrgtn )) ; then 
				echo "$(date) - EV ${EVLABEL[$numline]} next irrigation will be on $(sec2date $chk_irrgtn)"
				break
			fi
	
			rain_integration
			[[ -z $RAINCHECK ]] && { echo "ERROR: \$RAINCHECK not set" ; exit 1 ; }

			if [[ $RAINCHECK = "rainsensorqty" && $autodelayrain = yes ]] ; then
				delayirrigation # if rain in previous days, it changes chk_irrgtn if needed
				exit_stat=$?
				case $exit_stat in
					0) : #delay because of rain
						;;
					1) : #no delay
						;;
					2) : #progressive enabled 
						;;
				esac
			fi
				
			#echo DEBUG chk_irrgtn $chk_irrgtn lst_irrgtn $lst_irrgtn
			#echo DEBUG now $now
			# after # as set in sched config file
			if (( now > chk_irrgtn )) ; then 
				(( days_late = (now-chk_irrgtn)/86400 ))
				echo "$(date) - START IRRIGATION ${EVLABEL[$numline]} after $days_late day(s) late (would be on $(sec2date $chk_irrgtn)"
				irrigazione
			elif (( now == chk_irrgtn )) ; then 
				echo "$(date) - START IRRIGATION ${EVLABEL[$numline]} after $(( (now-lst_irrgtn)/86400 )) day(s)"
				irrigazione
			elif (( now < chk_irrgtn )) ; then 
				echo "$(date) - EV ${EVLABEL[$numline]} next irrigation will be on $(sec2date $chk_irrgtn) - delayed"
			fi
		fi
#	echo DEBUG ${EVALIAS[$numline]} ${LONG[$numline]} ${TIME_SCHED[$numline]} ${DAYFREQ[$numline]}
   done
   (( numline+=1 ))
done
# [[ -z $irrigated ]] && en_echo "NORMAL: no irrigation run at $time_now"
}

add_cfgheader()
{
echo "#piGarden.sched config file 
#author: androtto
#version $VERSION.$SUB_VERSION.$RELEASE_VERSION
#format file
#1st field;2nd field;3rd field;4th field;5th field
#EV?;duration;time;every_X_days;active|inactive
#EV?;duration;EV? #(previous)
#time is HH:MM 24h format
#every_X_days means daily frequency, 1= every day, 2=every three days (first yes, second no)),3= every three days (first yes, second and third no), etc..."
#active or inactive enable|disable scheduling
}


check_evalias()
{
	local evalias=$1
 	if [[ $evalias =~ ^EV[0-9]$ || $evalias =~ ^EV[0-9][0-9]$ ]] ; then
		# en_echo "NORMAL: $evalias format is right \"EV[0-9] or EV[0-9][0-9]\"" 
		: # do nothing
	else
		en_echo "ERROR: $evalias format is NOT right \"EV[0-9] or EV[0-9][0-9]\"" >&2
		return 1
	fi
       
	
#	evnumber=$(echo $evalias | tr -dc '0-9')
	evnumber="${evalias//[!0-9]/}"
	if (( evnumber <= EV_TOTAL )) ; then
		#en_echo "NORMAL: $evalias is in range (EV_TOTAL = $EV_TOTAL )" 
		: # do nothing
	else
		en_echo "ERROR: $evalias is NOT in range (EV_TOTAL = $EV_TOTAL )" >&2
		return 1
	fi
	return 0
}

update_cfgfile()
{
	sort -k1.3n $PIGARDENSCHED_TMP > ${PIGARDENSCHED_TMP}_2
	parsingfilesched ${PIGARDENSCHED_TMP}_2
	( add_cfgheader ; cat ${PIGARDENSCHED_TMP}_2 ) > ${PIGARDENSCHED_TMP}_3
	sudo cp -p ${PIGARDENSCHED_TMP}_3 $PIGARDENSCHED
}

insert()
{
	local evalias=$1
	local duration=$2
	local time=$3
	local freq=$4

	> $PIGARDENSCHED_TMP # init new sched file

	(( numline=1 ))
	while (( numline <= maxline ))
	do
		if [[ ${EVALIAS[$numline]} == $evalias ]] ; then
			echo "ERROR: $evalias is already present; use \"add_time, change_time, change_freq or change_dur\" option"
			return 1
		fi
		(( numline+=1 ))
	done 

        if check_concatenated $evalias ; then
                "$evalias is an ACTIVE concatenated irrigation: ${SEQLABEL[$seqnum]}"
		echo -e "ERROR: $evalias is in a concatenate scheduling (${SEQLABEL[$seqnum]})\n\tuse \"add_time, change_time, change_freq or change_dur\" option"
		return 1
	fi

	echo "$evalias;$duration;$time;$freq;active" >> $PIGARDENSCHED_TMP
	grep -v ^# $PIGARDENSCHED >> $PIGARDENSCHED_TMP
	update_cfgfile
}

remove_time()
{
	evalias=$1
	oldtimesched=$2
	local found=false

	err_msgA="ERROR: no $1 entry found"
	err_msgB="ERROR: no $2 found in $1 entry"
	foundA=false
	foundB=false

	(( numline=1 ))
	while (( numline <= maxline ))
	do
		if [[ ${EVALIAS[$numline]} == $evalias ]] ; then
			foundA=true
			newtimesched=""
			for time_sched in ${TIME_SCHED[$numline]//,/ }
			do
				if [[ $time_sched = $oldtimesched ]] ; then
					foundB=true
				else
					newtimesched="$newtimesched,$time_sched"
				fi
			done
			echo "${EVALIAS[$numline]};${LONG[$numline]};${newtimesched/,/};${DAYFREQ[$numline]};${ACTIVE[$numline]}"
		else
			echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};${ACTIVE[$numline]}"
		fi
		
		(( numline+=1 ))
	done > $PIGARDENSCHED_TMP
	if [[ $foundA = false ]] ; then
		err_msg=$err_msgA
		return 1
	fi
	if [[ $foundB = false ]] ; then
		err_msg=$err_msgB
		return 1
	fi
	update_cfgfile
}

add_time()
{
	evalias=$1
	newtimesched=$2
	local found=false

	err_msg="ERROR: no $1 found"

	(( numline=1 ))
	while (( numline <= maxline ))
	do
		if [[ ${EVALIAS[$numline]} == $evalias ]] ; then
			found=true
			if [[ ${DAYFREQ[$numline]} -ne 1 ]] ; then
				err_msg="ERROR: cannot add $newtimesched for $evalias because frequency is not 1 day"
				return 1
			fi
			for time_sched in ${TIME_SCHED[$numline]//,/ }
			do
				if [[ $time_sched = $newtimesched ]] ; then
					err_msg="ERROR: $newtimesched for $evalias already present"
					return 1
				fi
			done
			timesched="${TIME_SCHED[$numline]},$newtimesched"
			echo "${EVALIAS[$numline]};${LONG[$numline]};$timesched;${DAYFREQ[$numline]};${ACTIVE[$numline]}"
		else
			echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};${ACTIVE[$numline]}"
		fi
		
		(( numline+=1 ))
	done > $PIGARDENSCHED_TMP
	[[ $found = "false" ]] && return 1
	update_cfgfile
}

convert()
{
	local evaliasprev=""
	local timeschedprev=""
	local longprev=""
	local dayfreqprev=""
	local activeprev=""

	(( numline=1 ))
	while (( numline <= maxline ))
	do
		if [[ ${TIME_SCHED[$numline]} == $evaliasprev ]] ; then
#			if ! check_timeformat $timeschedprev >/dev/null 2>&1 ; then
#				err_msg="ERROR: timeschedprev $timeschedprev not allowed"
#				return 1
#			fi

			timesched=""
			for prevtimesched in ${timeschedprev//,/ }
			do
				hour=$( echo $prevtimesched | cut -f1 -d:)
				min=$( echo $prevtimesched | cut -f2 -d:)
				(( secs = 10#$hour*3600+10#$min*60+10#$longprev*60 ))
				timesched="$timesched $(date -u --date="@$secs" '+%R')" # uso date -u per ottenere i nuovi orari partendo dal calcolo dei secondi
			done
			timesched=${timesched/ /} # rimuovo il primo spazio
			timesched=${timesched// /,} # sostituisco gli spazi con le virgole
			echo "${EVALIAS[$numline]};${LONG[$numline]};$timesched;$dayfreqprev;$activeprev"
			evaliasprev=${EVALIAS[$numline]}
			longprev=${LONG[$numline]}
			timeschedprev=$timesched
		else
			echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};${ACTIVE[$numline]}"
			evaliasprev=${EVALIAS[$numline]}
			longprev=${LONG[$numline]}
			timeschedprev=${TIME_SCHED[$numline]}
			dayfreqprev=${DAYFREQ[$numline]}
			activeprev=${ACTIVE[$numline]}
		fi
		
		(( numline+=1 ))
	done > $PIGARDENSCHED_TMP
	update_cfgfile
}


remove()
{
	local evalias=$1

	local evaliasprev=""
	local timeschedprev=""
	local longprev=""
	local dayfreqprev=""
	local activeprev=""

	msg="WARNING: no line removed for $evalias entry"

	(( numline=1 ))
	while (( numline <= maxline ))
	do
		if [[ ${EVALIAS[$numline]} == $evalias ]] ; then
			evaliasprev=${EVALIAS[$numline]}
			longprev=${LONG[$numline]}
			timeschedprev=${TIME_SCHED[$numline]}
			dayfreqprev=${DAYFREQ[$numline]}
			activeprev=${ACTIVE[$numline]}
			if [[ ${TIME_SCHED[$numline]} == EV* ]] ; then
				msg="ERROR: found $evalias in part of a concatenated irrigation"
				return 1
			else
				msg="NORMAL: found $evalias in line $numline - removed"
				(( numline+=1 ))
				continue
			fi
		fi
		if [[ ${TIME_SCHED[$numline]} == $evaliasprev ]] ; then
			newtimesched=""
			for time_sched in ${timeschedprev//,/ }
                	do
				if ! check_timeformat $time_sched ; then
					msg="ERROR: $time_sched is not a valid time"
					return 1
				fi
				hour=$( echo $time_sched | cut -f1 -d:)
				min=$( echo $time_sched | cut -f2 -d:)
				(( secs = 10#$hour*3600+10#$min*60+10#$longprev*60 ))
				newtimesched="$newtimesched,$(date -u --date="@$secs" '+%R')"
			done
			
			echo "${EVALIAS[$numline]};${LONG[$numline]};${newtimesched/,/};$dayfreqprev;$activeprev"
			(( numline+=1 ))
			continue
		fi
		echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};${ACTIVE[$numline]}"
		(( numline+=1 ))
	done > $PIGARDENSCHED_TMP
	update_cfgfile
}

check_number()
{
        [[ $1 =~ ^[1-9][0-9]*$ ]] || return 1 && return 0
}

check_timeformat()
{
        [[ $1 =~ ^[0-2][0-9][:][0-5][0-9]$ ]] || return 1
	timearray=(${1/:/ })
	(( $((10#${timearray[0]})) <= 23 && $((10#${timearray[1]})) <= 59 )) || return 1 && return 0
}

modify()
{
	#parameter $1 is duration|freq|time
	#parameter $3 is value for duration|freq|time
	local what=$1
	local evalias=$2
	local parm=$3
	declare -g err_msg
	err_msg=""
	
	found=no
	(( numline=1 ))
	while (( numline <= maxline ))
	do
                if [[ ${EVALIAS[$numline]} == $evalias ]] ; then
			found=yes
			case $what in
				duration)
					echo "${EVALIAS[$numline]};$parm;${TIME_SCHED[$numline]};${DAYFREQ[$numline]};${ACTIVE[$numline]}"
					;;
				freq)
					if check_evalias ${TIME_SCHED[$numline]} >/dev/null 2>&1 ; then
						err_msg="ERROR: cannot change frequency for a sequential irrigation - ${EVALIAS[$numline]} will run after ${TIME_SCHED[$numline]}"
						return 1
					fi
					if ! check_timeformat ${TIME_SCHED[$numline]} >/dev/null 2>&1 ; then
						err_msg="ERROR: cannot change frequency for an entry with more one scheduled time - ${TIME_SCHED[$numline]} has 2 parms or more"
						return 1
					fi
					echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};$parm;${ACTIVE[$numline]}"
					;;
				time)
					if check_evalias ${TIME_SCHED[$numline]} >/dev/null 2>&1 ; then
						err_msg="ERROR: cannot change scheduled time for a sequential irrigation - ${EVALIAS[$numline]} will run after ${TIME_SCHED[$numline]}"
						return 1
					fi
					echo "${EVALIAS[$numline]};${LONG[$numline]};$parm;${DAYFREQ[$numline]};${ACTIVE[$numline]}"
					;;
				enable)
					if check_evalias ${TIME_SCHED[$numline]} >/dev/null 2>&1 ; then
						err_msg="ERROR: cannot enable ${EVALIAS[$numline]} because it's part of a sequential irrigation"
						return 1
					fi
					
					if [[ ${ACTIVE[$numline]} = inactive ]] ; then
						echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};active"
					else
						err_msg="ERROR: cannot enable ${EVALIAS[$numline]} because it's not in INACTIVE status"
						return 1
					fi
					;;
				disable)
					if check_evalias ${TIME_SCHED[$numline]} >/dev/null 2>&1 ; then
						err_msg="ERROR: cannot enable ${EVALIAS[$numline]} because it's part of a sequential irrigation"
						return 1
					fi

					if [[ ${ACTIVE[$numline]} = active ]] ; then
						echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};inactive"
					else
						err_msg="ERROR: cannot enable ${EVALIAS[$numline]} because it's not in ACTIVE status"
						return 1
					fi
					;;
				*)
					err_msg="ERROR: wrong $what option"
					return 1
					;;
			esac
		else
			echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};${ACTIVE[$numline]}"
                fi
		(( numline+=1 ))
	done > $PIGARDENSCHED_TMP
	if [[ $found = yes ]] ; then
		update_cfgfile
		return 0
	else
		err_msg="ERROR: entry $evalias not found"
		return 1
	fi
}

check_concatenated()
{
	declare -g seqnum
        for ((seqnum=0;seqnum<${#SEQ[@]};seqnum++))
        do
                #echo $seqnum
                #echo "${SEQ[$seqnum]}"
                if [[ "${SEQ[$seqnum]}" =~ $1 ]] ; then
                        return 0
                fi
        done
	return 1
}


check_sequential()
{
	# one single parameter mush be passed
	local evlist="$1"
#	evlist_sorted="$(echo $evlist | tr " " "\\n" | sort -k1.3n | tr "\n" " " )"
#	if [[ "$evlist" != "$evlist_sorted" ]] ; then
#		echo -e "ERROR: wrong sequence given $evlist\n\tright sequence should be $evlist_sorted"
#		return 1
#	fi
#	echo $evlist_sorted
#	echo  ${evlist_sorted//[!0-9 ]/} 

	numbers="${evlist//[!0-9 ]/}"
	local seqnumber
	for number in $numbers
	do
		if [[ -z $seqnumber ]] ; then
			(( seqnumber = number ))
			continue
		fi
		(( seqnumber += 1 ))
		#echo DEBUG $number $seqnumber
		if (( number != seqnumber )) ; then
			echo -e "ERROR: wrong sequence given $evlist\n\tnumber are not contiguous or repeated ($numbers)"
			set +x
			return 1
		fi
	done
	return 0
}

sequential()
{
	evlist="$* "
	for ev in $evlist
	do
		if ! check_evalias $ev >/dev/null 2>&1 ; then
			en_echo "ERROR: $ev is NOT a valid EV#/EV##"
		 	return 1
		fi
	done
	
	if ! check_sequential "$evlist" ; then
		return 1
	fi

	evarray=($evlist)
	evindex=1

	> $PIGARDENSCHED_TMP # init new sched file
	found=false
	(( numline=1 ))
	while (( numline <= maxline ))
	do
		if [[ ${EVALIAS[$numline]} == ${evarray[0]} ]] ; then
			en_echo "NORMAL: first member ${evarray[0]} of sequence is present"
			long=${LONG[$numline]}
			echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};${ACTIVE[$numline]}" >> $PIGARDENSCHED_TMP
			found=true
		fi
		(( numline+=1 ))
	done 
	if [[ $found = false ]] ; then
		en_echo "ERROR:first member ${evarray[0]} of sequence NOT found"
		return 1
	fi

	# build sequence except #1
	(( counter = 1  ))# skip first array member [0]
	while (( counter < ${#evarray[@]} )) # not <= because array index starts from 0
	do
		(( counterprev = counter-1 ))
		(( numline=1 ))
		while (( numline <= maxline ))
		do
#			se lo trovo cambio la sequenza e mantengo la durata
#			se non lo trovo lo inserisco con durata del primo della sequenza
			if [[ ${EVALIAS[$numline]} == ${evarray[$counter]} ]] ; then
				echo "${EVALIAS[$numline]};${LONG[$numline]};${evarray[$counterprev]};;" >> $PIGARDENSCHED_TMP
				(( counter += 1 ))
				continue 2
			fi
			(( numline+=1 ))
		done
		echo "${evarray[$counter]};$long;${evarray[$counterprev]};;" >> $PIGARDENSCHED_TMP
		(( counter += 1 ))
	done 
	
	# add line with no member of sequence
	(( numline=1 ))
	while (( numline <= maxline ))
	do
		(( counter = 0  ))# including first array member [0]
		while (( counter < ${#evarray[@]} )) # not <= because array index starts from 0
		do
			if [[ ${EVALIAS[$numline]} == ${evarray[$counter]} ]] ; then
				(( numline+=1 ))
				continue 2
			fi
			(( counter += 1 ))
		done
		echo "${EVALIAS[$numline]};${LONG[$numline]};${TIME_SCHED[$numline]};${DAYFREQ[$numline]};${ACTIVE[$numline]}" >> $PIGARDENSCHED_TMP
		(( numline+=1 ))
	done 

	update_cfgfile
}


status()
{
	
	(( numline=1 ))
	while (( numline <= maxline ))
	do
  		for time_sched in ${TIME_SCHED[$numline]//,/ }
   		do
			if check_timeformat $time_sched >/dev/null 2>&1 ; then
				if [[ "${ACTIVE[$numline]}" = "active" ]] ; then
					echo -e "\nNORMAL: irrigation for ${EVLABEL[$numline]} is at $time_sched every ${DAYFREQ[$numline]} day(s) - ACTIVE" 
				elif [[ "${ACTIVE[$numline]}" = "inactive" ]] ; then
					echo -e "\nWARNING: irrigation for ${EVLABEL[$numline]} is at $time_sched every ${DAYFREQ[$numline]} day(s) - INACTIVE" 
				fi
				
				statfile="${STATDIR}/${EVALIAS[$numline]}-${time_sched}.lastrun"
				if [[ -f $statfile ]] ; then
                			lst_irrgtn="$(<$statfile)"
                			echo "        last irrigation was     on $(sec2date $lst_irrgtn)"
					dayfreq=${DAYFREQ[$numline]}
					(( nxt_irrgtn=lst_irrgtn+dayfreq*24*60*60 ))
					echo "        next irrigation will be on $(sec2date $nxt_irrgtn)"
				else
                			echo "        no previous irrigation"
					echo "        next irrigation will be today/tomorrow at $time_sched"
				fi

                                #check if concatenated
                                if check_concatenated ${EVALIAS[$numline]} ; then
                                        echo "this is an ACTIVE concatenated irrigation: ${SEQLABEL[$seqnum]}"
                                fi

#			else
#				echo "${EVLABEL[$numline]} is concatenated with $evlabelprev"
			fi
		done
		evlabelprev=${EVLABEL[$numline]}
		(( numline+=1 ))
	done
}

history()
{
	#set -x
	cd $STATDIR
	for evlabel in $( ls *.history | cut -d- -f1 | sort -u )
	do
		local found=no
		(( numline=1 ))
		while (( numline <= maxline ))
		do
			if [[ $evlabel = ${EVLABEL[$numline]} ]] ; then
				case ${ACTIVE[$numline]} in
					active) echo -e "\nNORMAL: irrigation for $evlabel is at ${TIME_SCHED[$numline]//,/ } every ${DAYFREQ[$numline]} day(s) - ACTIVE" 
						;;
					inactive) echo -e "\nWARNING: irrigation for $evlabel is at ${TIME_SCHED[$numline]//,/ } every ${DAYFREQ[$numline]} day(s) - INACTIVE" 
						;;
					*) echo -e "\nERROR: irrigation for $evlabel is at ${TIME_SCHED[$numline]//,/ } every ${DAYFREQ[$numline]} day(s) - neither ACTIVE or INACTIVE" 
					exit 1
						;;
				esac
				found=yes

        			#check if concatenated
        			if check_concatenated ${EVALIAS[$numline]} ; then
					echo "this is an ACTIVE concatenated irrigation: ${SEQLABEL[$seqnum]}"
        			fi

				break
			fi
			(( numline+=1 ))
		done
		[[ $found = no ]] && echo -e "\nWARNING: $evlabel is NOT scheduled"
		echo "history of irrigations:"
		for file in $( ls -rt ${evlabel}*.history )
		do
			#set -- ${file//[.-]/ }
			#evlabel=$1
			#timesched=$2
			for date in $(< $file ) 
			do
				sec2date $date
			done 
		done
	done
}

show_irrigations()
{
# it works passing standard input
	cat - | while read line
	do
		set -- ${line//:/ }
		start=$1
		mins=$2
		echo "$(sec2date $start) for $mins mins"
	done 
}

irrigation_history()
{
	# if $1 passed, that's number of events
	number_of_events=$1
	# if $2 passed, that's EV
	if [[ -n $2 ]] ; then
		if getidx evalias $2 ; then
			evlabel=${EVLABEL[$idx]}
			filelist="${evlabel}-irrigationhistory"
		else
			echo "ERROR in funct getidx"
		fi
	else
		filelist='*-irrigationhistory'
	fi
	#set -x

	cd $STATDIR
	#for histfile in *-irrigationhistory 
	for histfile in $filelist
	do
		if [[ ! -f $histfile ]] ; then
			echo "Skipping EV $evlabel history ($filelist not found)"
			continue
		fi
		evlabel=${histfile//-*/}
		echo -e "\nEV $evlabel history of effective irrigations"
		if [[ -z $number_of_events ]] ; then
			cat $histfile | show_irrigations
		else
			tail -$number_of_events $histfile | show_irrigations
		fi
	done
}

check_testflag()
{
		local testflag=$DIR_SCRIPT/include/TEST
                if [[ -f $testflag ]] ; then
                         echo "WARNING: TEST flag \"$testflag\" found - piGarden.sh open/close will NOT executed"
                fi
}
