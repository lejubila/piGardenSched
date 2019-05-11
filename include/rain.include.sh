# integration with Driver rainsensorqty - driver for measure the rain volume, for rain meter, for rain gauge
# Author: androtto
# file "rain.include.sh"
# Version: 0.1.4
# Data: 20/Mar/2019
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


check_lastrain()
{
	if [ -f "$RAINSENSORQTY_LASTRAIN" ] ; then
		lastrain="$( cat "$RAINSENSORQTY_LASTRAIN" | $CUT -f 1 -d: )"
		counter="$( cat "$RAINSENSORQTY_LASTRAIN" | $CUT -f 2 -d: )"
		if [[ -z $lastrain || -z $counter ]] ; then
			echo -e "\nERROR: file $RAINSENSORQTY_LASTRAIN empty or wrong format"
			lastrain=0
			rainlevel=0
			counter=0
		fi
	        rainlevel=$( $JQ -n "$counter/$RAINSENSORQTY_LOOPSFORSETRAINING" | $JQ 'floor' )
	else
		lastrain=0
		rainlevel=0
		counter=0
	fi
}

# true no irrigation - false irrigation
#check rain in last 5 minures
rainornot()
{
	check_lastrain
	(( fiveminutesago = $(date +%s )-5*60 ))
	if ((  lastrain >= fiveminutesago )) ; then
                return 0 # rain
	else
                return 1 # norain
        fi
}

delayirrigation()
{
	if [[ ! -f $RAINSENSORQTY_HISTORY ]] ; then
		en_echo "NORMAL: no RAINSENSORQTY_HISTORY file"
		return 2
	fi

	#lst_irrgtn  #seconds of last irrigation
	#chk_irrgtn  #seconds of scheduled irrigaion

	(( from_time_irrgtn = chk_irrgtn - 24*60*60 )) # 24 h less than chk_irrgtn
	local counter=0
	while (( from_time_irrgtn >= lst_irrgtn ))
	do
		(( to_time_irrgtn = from_time_irrgtn + 24*60*60 )) # first cycle is equal chk_irrgtn
		for rainline in $( awk -F: "\$1>=$from_time_irrgtn && \$1<=$to_time_irrgtn" $RAINSENSORQTY_HISTORY | tac )
		do
			set -- ${rainline//:/ }
			raintime=$1
			rainlevel=$2
	                echo "EV ${EVLABEL[$numline]} would have next irrigation on $(date --date "@$chk_irrgtn")"
			printf "RAINED on %s for %.2f mm\n" "$(date --date="@$raintime")" $( $JQ -n "$rainlevel * $RAINSENSORQTY_MMEACH" )
			(( daydelayed = dayfreq - counter ))
			#echo "EV ${EVLABEL[$numline]} irrigation delayed $daydelayed day(s) from $(date --date="@$chk_irrgtn")"
			echo "EV ${EVLABEL[$numline]} irrigation delayed $daydelayed day(s)"
			(( chk_irrgtn += daydelayed*24*60*60 ))
			return 0
#			break 2
		done
		(( from_time_irrgtn -= 24*60*60 )) # decrease one day at time
		(( counter += 1 ))
		# DEBUG echo $from_time_irrgtn $to_time_irrgtn $counter
	done
	return 1
}

rain_integration()
{
	RAINCHECK=""
	# check which "rain" service is active
	if [[ -n $WEATHER_SERVICE && $WEATHER_SERVICE != "none" ]] ; then
		en_echo "NORMAL: WEATHER_SERVICE active ($WEATHER_SERVICE) - no integration with piGardenSched needed"
		RAINCHECK="WEATHER_SERVICE"
	elif [[ $RAIN_GPIO =~ ^[0-9]*$ ]] ; then
		en_echo "NORMAL: piGarden native RAIN sensor active - no integration with piGardenSched needed"
		RAINCHECK="native"
	elif [[ $RAIN_GPIO =~ ^drv:rainsensorqty: ]] ; then
		en_echo "NORMAL: piGarden drv_rainsensorqty service active - integration with piGardenSched is available"
		RAINCHECK="rainsensorqty"
	fi
}


raincheck()
{
        if [[ $RAINCHECK = "rainsensorqty" && $autostoprain = yes ]] ; then
                en_echo 'NORMAL: $RAIN_GPIO is "drv:rainsensorqty" and "$autostoprain" yes - raincheck'
                if [[ -z ${EVNORAINQTY[$idx]} || ${EVNORAINQTY[$idx]} = 0 ]] ; then
                        en_echo "NORMAL: \${EVNORAINQTY[$idx]} is 0 (or null) - raincheck QTY for ${EVLABEL[$idx]} is active"
			if [[ -z ${EVNORAINCLASSIC[$idx]} || ${EVNORAINCLASSIC[$idx]} = 0 ]] ; then
                        	en_echo "WARNING: \${EVNORAINCLASSIC[$idx]} is 0 (or null) - classic raincheck for ${EVLABEL[$idx]} enabled\n\tCONFLICTS with \${EVNORAINQTY[$idx]} - two methods will check rain"
				return 1
			else
                        	en_echo "NORMAL: \${EVNORAINCLASSIC[$idx]} is 1 - classic raincheck for ${EVLABEL[$idx]} is disabled"
                        	return 0
			fi
                else
                        en_echo "WARNING: \${EVNORAINQTY[$idx]} is 1 - no raincheck QTY for ${EVLABEL[$idx]}"
			if [[ -z ${EVNORAINCLASSIC[$idx]} || ${EVNORAINCLASSIC[$idx]} = 0 ]] ; then
                        	en_echo "WARNING: \${EVNORAINCLASSIC[$idx]} is 0 (or null) - classic raincheck for ${EVLABEL[$idx]} enabled"
			else
                        	en_echo "WARNING: \${EVNORAINCLASSIC[$idx]} is 1 - classic raincheck for ${EVLABEL[$idx]} is disabled"
			fi
			return 1
                fi
        else
                en_echo 'NORMAL: $RAIN_GPIO is not "drv:rainsensorqty" or "$autostoprain" - no raincheck'
		return 1
        fi
}
