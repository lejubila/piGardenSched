# integration with Driver rainsensorqty - driver for measure the rain volume, for rain meter, for rain gauge
# Author: androtto
# file "rain.include.sh"
# Version: 0.3.6d
# Data: 17/Jun/2020
# la pioggia può essere gestita con 3 modalita'- impostanod le variabili in /etc/piGarden.conf
# 1) con sensore gestito direttamente da piGarden. Impostanto la variabile con la GPIO da utilizzare:
#	RAIN_GPIO="25"
# 2) con servizio meteo valorizzando la seguente variabile:
#	WEATHER_SERVICE 
#	opzioni:
#	WEATHER_SERVICE="openweathermap"
#	WEATHER_SERVICE="wunderground"
# 3) con il driver rainsensorqty, valorizzando la variabile:
#	RAIN_GPIO="drv:rainsensorqty:25" , dove il secondo campo indica quale driver attivare sotto piGarden/drv e il 3° quale GPIO usare
# 2020/06/17: added IT WAS RAIN ONLY statement
# 2020/04/07: added raincheck silent option

rained()
# true no irrigation - false irrigation
#check rain in last 24h hours 
{
	if [[ ! -f $RAINSENSORQTY_HISTORYRAW ]] ; then
		en_echo "NORMAL: it NEVER RAINED"
		return 1
	fi
	now="$( date '+%s' )"
	(( before24h=now-24*60*60 ))
	if debug ; then
		echo $before24h ---- $now
		echo $( sec2date $before24h ) ---- $( sec2date $now )
		echo awk -F: \'"\$1>=$before24h && \$1<=$now"\' $RAINSENSORQTY_HISTORYRAW
		awk -F: "\$1>=$before24h && \$1<=$now" $RAINSENSORQTY_HISTORYRAW
	fi

	if ! rainlines="$(raintimeframe $before24h $now)" ; then
		echo "ERROR: in raintimeframe function"
		exit 99 
	fi

	if debug ; then
		echo "DEBUG: \$rainlines = $rainlines"
	fi

	if (( $rainlines >= $RAINSENSORQTY_LOOPSFORSETRAINING )) ; then
		printf "\nRAINED for %.2f mm between %s and %s \n" $( $JQ -n "$rainlines * $RAINSENSORQTY_MMEACH" ) "$(sec2date $before24h)" "$(sec2date $now)" 
                return 0 # rained
	else
		if verbose ; then
			if (( $rainlines == 0 )) ; then
				echo "NORMAL: not rained in last 24h"
			else
			#	printf "\nRAINED only for %.2f mm between %s and %s \n" $( $JQ -n "$rainlines * $RAINSENSORQTY_MMEACH" ) "$(sec2date $before24h)" "$(sec2date $now)" 
				printf "\nRAINED only for %.2f mm in last 24h \n" $( $JQ -n "$rainlines * $RAINSENSORQTY_MMEACH" )
			fi
		fi
       	        return 1 # not rained
        fi
}

raintimeframe()
{
	[[ $# != 2 ]] && return 1
	local from=$1
	local to=$2
 	awk -F: "\$1>=$from && \$1<=$to" $RAINSENSORQTY_HISTORYRAW | wc -l
}

delayirrigation()
{
#set -x
	if [[ ! -f $RAINSENSORQTY_HISTORYRAW ]] ; then
		en_echo "NORMAL: it NEVER RAINED"
		return 1
	fi

	#lst_irrgtn  #seconds of last irrigation
	#chk_irrgtn  #seconds of scheduled irrigation
	(( to_time_irrgtn = chk_irrgtn ))
	
	debug && echo now $now $(sec2date $now) 
	debug && echo lst_irrgtn $lst_irrgtn $(sec2date $lst_irrgtn)
	debug && echo chk_irrgtn $chk_irrgtn $(sec2date $chk_irrgtn)
	debug && echo to_time_irrgtn $to_time_irrgtn $(sec2date $to_time_irrgtn) prima

	#TZ change check
	if [[ $( date --date="@$now" '+%Z' ) != $( date --date="@$lst_irrgtn" '+%Z' ) ]] ; then
		echo "ERROR: timezone changed - daylight savings time known issue: please reset $statfile file"
		return 3
	fi


	# correct time frame to check if chk_irrgtn isn't now
	local delay_coefficient=0
	while (( now != to_time_irrgtn ))
	do
		(( to_time_irrgtn += 24*60*60 ))

		debug && echo to_time_irrgtn $to_time_irrgtn $(sec2date $to_time_irrgtn) dopo
		(( delay_coefficient += 1 )) # needed because to_time_irrgtn was at first loop equal to chk_irrgtn

	done
	verbose && (( delay_coefficient > 0 )) && echo "$(date) - EV ${EVLABEL[$numline]} previous irrigation was delayed (now is $delay_coefficient day(s) later)"

	(( from_time_irrgtn = to_time_irrgtn - 24*60*60 )) # 24 h less than chk_irrgtn
	debug && echo from_time_irrgtn $from_time_irrgtn $(sec2date $from_time_irrgtn)
	local counter=0
	declare -g progressive_factor
	(( progressive_factor = 1 ))
	while (( from_time_irrgtn >= lst_irrgtn ))
	do
		(( to_time_irrgtn = from_time_irrgtn + 24*60*60 )) # first cycle is equal chk_irrgtn
		if debug  ; then
			echo $from_time_irrgtn ---- $to_time_irrgtn
			echo $( sec2date $from_time_irrgtn ) ---- $( sec2date $to_time_irrgtn )
			echo awk -F: \'"\$1>=$from_time_irrgtn && \$1<=$to_time_irrgtn"\' $RAINSENSORQTY_HISTORYRAW
#			awk -F: "\$1>=$from_time_irrgtn && \$1<=$to_time_irrgtn" $RAINSENSORQTY_HISTORYRAW
		fi
		if ! rainlines="$(raintimeframe $from_time_irrgtn $to_time_irrgtn)" ; then
			echo "ERROR: in raintimeframe function"
			exit 99 
		fi
		debug && echo "DEBUG: \$rainlines = $rainlines"
		if (( counter == 0 )) ; then
			timeframe="in last 24 hours"
			# progressive session:
			if ((  $rainlines > 0 && $rainlines < $RAINSENSORQTY_LOOPSFORSETRAINING )) ; then
				rainlines_last24=$rainlines # only for debug, not needed
				progressive_factor=$( $JQ -n "1-($rainlines / $RAINSENSORQTY_LOOPSFORSETRAINING )" )
#				echo \$rainlines_last24 \$RAINSENSORQTY_LOOPSFORSETRAINING \$progressive_factor
#				echo $rainlines_last24 $RAINSENSORQTY_LOOPSFORSETRAINING $progressive_factor
			fi
		else
			timeframe="ranging from within $(( counter*24 )) to $(( (counter+1)*24 )) hours ago"
		fi

		if (( $rainlines >= $RAINSENSORQTY_LOOPSFORSETRAINING )) ; then
#			printf "it WAS RAINING for %.2f mm between %s and %s \n" $( $JQ -n "$rainlines * $RAINSENSORQTY_MMEACH" ) "$(sec2date $from_time_irrgtn)" "$(sec2date $to_time_irrgtn)" 
			printf "it WAS RAINING for %.2f mm %s \n" $( $JQ -n "$rainlines * $RAINSENSORQTY_MMEACH" ) "$timeframe"
	                echo "EV ${EVLABEL[$numline]} would have next irrigation on $(sec2date $chk_irrgtn)"
			(( daydelayed = dayfreq + delay_coefficient - counter ))
			#echo "EV ${EVLABEL[$numline]} irrigation delayed $daydelayed day(s) from $(sec2date $chk_irrgtn)"
			echo "EV ${EVLABEL[$numline]} irrigation delayed $daydelayed day(s) from previous scheduling (on $(sec2date $chk_irrgtn) )"
			(( chk_irrgtn += daydelayed*24*60*60 ))
			return 0
		elif (( $rainlines > 0 )) ; then
			printf "it WAS RAINING ONLY for %.2f mm %s \n" $( $JQ -n "$rainlines * $RAINSENSORQTY_MMEACH" ) "$timeframe"
		else
#			verbose && printf "it WAS NOT RAINING between %s and %s \n" "$(sec2date $from_time_irrgtn)" "$(sec2date $to_time_irrgtn)" 
			verbose && echo "it WAS NOT RAINING $timeframe"
		fi
		(( from_time_irrgtn -= 24*60*60 )) # decrease one day at time
		(( counter += 1 ))
		debug && echo "DEBUG $from_time_irrgtn $to_time_irrgtn $counter"
	done
	if [[ ${EVPROGRESSIVE[$numline]} = 1 ]] ; then
		if [[ $progressive_factor < 1 ]] ; then
			printf "PROGRESSIVE ENABLED - irrigation will be reduced to %.2f %s because it WAS RAINING for %.2f mm %s \n" $( $JQ -n "$progressive_factor * 100") '%' $( $JQ -n "$rainlines_last24 * $RAINSENSORQTY_MMEACH" ) "in last 24 hours"
		else
			verbose && echo "PROGRESSIVE ENABLED - no irrigation reduction because of no partial raining"
		fi
#		echo "progressive enabled, \$progressive_factor = $progressive_factor"
		return 2
	fi
#	echo 'no progressive / no rain (end loop)'
	return 1
}

rain_integration()
{
	RAINCHECK=""
	# check which "rain" service is active
	if [[ -n $WEATHER_SERVICE && $WEATHER_SERVICE != "none" ]] ; then
		#en_echo "NORMAL: WEATHER_SERVICE active ($WEATHER_SERVICE) - no integration with piGardenSched needed"
		en_echo "NORMAL: WEATHER_SERVICE active $WEATHER_SERVICE - no integration with piGardenSched needed"
		RAINCHECK="WEATHER_SERVICE"
	elif [[ $RAIN_GPIO =~ ^[0-9]*$ ]] ; then
		en_echo "NORMAL: piGarden native RAIN sensor active - no integration with piGardenSched needed"
		RAINCHECK="native"
	elif [[ $RAIN_GPIO =~ ^drv:rainsensorqty: ]] ; then
		en_echo "NORMAL: piGarden drv_rainsensorqty service active - integration with piGardenSched is available"
		RAINCHECK="rainsensorqty"
	fi
}

silent()
{
	[[ $silent == yes ]] && return 0 || return 1
}

raincheck()
{
	[[ $1 == "silent" ]] && silent=yes
        if [[ $RAINCHECK = "rainsensorqty" && $autostoprain = yes ]] ; then
                silent || en_echo 'NORMAL: $RAIN_GPIO is "drv:rainsensorqty" and "$autostoprain" yes - raincheck'
                if [[ -z ${EVNORAINQTY[$idx]} || ${EVNORAINQTY[$idx]} = 0 ]] ; then
                        silent || en_echo "NORMAL: \${EVNORAINQTY[$idx]} is 0 (or null) - raincheck QTY for ${EVLABEL[$idx]} is active"
			if [[ -z ${EVNORAINCLASSIC[$idx]} || ${EVNORAINCLASSIC[$idx]} = 0 ]] ; then
                        	silent || en_echo "WARNING: \${EVNORAINCLASSIC[$idx]} is 0 (or null) - classic raincheck for ${EVLABEL[$idx]} enabled\n\tCONFLICTS with \${EVNORAINQTY[$idx]} - two methods will check rain"
				return 1
			else
                        	silent || en_echo "NORMAL: \${EVNORAINCLASSIC[$idx]} is 1 - classic raincheck for ${EVLABEL[$idx]} is disabled"
                        	return 0
			fi
                else
                        silent || en_echo "WARNING: \${EVNORAINQTY[$idx]} is 1 - no raincheck QTY for ${EVLABEL[$idx]}"
			if [[ -z ${EVNORAINCLASSIC[$idx]} || ${EVNORAINCLASSIC[$idx]} = 0 ]] ; then
                        	silent || en_echo "WARNING: \${EVNORAINCLASSIC[$idx]} is 0 (or null) - classic raincheck for ${EVLABEL[$idx]} enabled"
			else
                        	silent || en_echo "WARNING: \${EVNORAINCLASSIC[$idx]} is 1 - classic raincheck for ${EVLABEL[$idx]} is disabled"
			fi
			return 1
                fi
        else
                silent || en_echo 'NORMAL: $RAIN_GPIO is not "drv:rainsensorqty" or "$autostoprain" - no raincheck'
		return 1
        fi
}
