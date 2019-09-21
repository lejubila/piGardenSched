#!/bin/bash
# piGardenSched
# irrigating script - call piGarden.sh open/close
# Author: androtto
# VERSION=0.3.3
# 2019/08/18: called script with absolute path


DIR_SCRIPT="$(cd `dirname $0` ; pwd )"
NAME_SCRIPT=${0##*/}
FUNCTIONS=$DIR_SCRIPT/functions.include.sh
RAINFUNCT=$DIR_SCRIPT/rain.include.sh

LOGDIR="$DIR_SCRIPT/../log" 
TMPDIR="$DIR_SCRIPT/../tmp"
STATDIR="$DIR_SCRIPT/../state"

cfgfiles=$DIR_SCRIPT/../.cfgfiles
. $cfgfiles || { echo "ERROR: while executing $cfgfiles or not found" ; exit 1 ; }

for sourcefile in $PIGARDENSCHED_CONF $FUNCTIONS $RAINFUNCT $PIGARDEN_CONFIG_ETC
do
        . $sourcefile || { echo "ERROR: while executing $sourcefile or not found" ; exit 1 ;
}
done

# needed for getting relation between EVALIAS & EVLABEL
parsingfilesched $PIGARDENSCHED

if [[ $# = 0 ]] ; then
	echo "ERROR: $NAME_SCRIPT mush be called with parameters, at least one like this: EVLABEL:DURATION"
	exit 1
fi

echo "called $DIR_SCRIPT/$NAME_SCRIPT $*"

if [[ $# = 1 ]] ; then
	type=SINGLE
	echo "----- STARTING $type IRRIGATION -----"
else
	type=MULTI
	echo "----- STARTING $type IRRIGATION - $# EVs CONCATENATED -----"
fi

for parm in $*
do
	set -- ${parm//:/ }
	evlabel=$1
	duration=$2

	if ! getidx evlabel $evlabel ; then
        	echo "ERROR: getidx function - evlabel $1 is not present"
	        exit 1
	fi
	evalias=${EVALIAS[$idx]}

	
	if $DIR_SCRIPT/raincheck-waitloop.sh $evlabel raincheck ; then
		# RAIN
		echo "$(d) WARNING: irrigation EV $evlabel is suspended for rain"
	else
		# NO RAIN
		start_secs=$( date '+%s' )
		echo "$(d) NORMAL: starting irrigation EV $evlabel"
		if [[ ! -f $DIR_SCRIPT/TEST ]] ; then
			 $PIGARDEN_HOME/piGarden.sh open $evlabel 
		else
			 echo "TEST flag \"$DIR_SCRIPT/TEST\" found - piGarden.sh open $evlabel not executed"
		fi
		$DIR_SCRIPT/raincheck-waitloop.sh $evlabel wait $duration 
		if [[ ! -f $DIR_SCRIPT/TEST ]] ; then
			 $PIGARDEN_HOME/piGarden.sh close $evlabel 
		else
			 echo "TEST flag \"$DIR_SCRIPT/TEST\" found - piGarden.sh close $evlabel not executed"
		fi
		end_secs=$( date '+%s' )
		(( irrigation_mins=(end_secs-start_secs)/60 ))
		echo "$(d) NORMAL: end irrigation EV $evlabel after $irrigation_mins mins"
		statupdate_irrigation $evalias $start_secs $irrigation_mins
	fi
	sleep 2
done

echo "----- FINISHED $type IRRIGATION -----"
