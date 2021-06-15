#!/bin/bash
# piGardenSched
# irrigating script - call piGarden.sh open/close
# Author: androtto
# VERSION=0.3.6b
# 2020/05/05: log more readable...
# 2020/04/08: TEST flag ignored if added while irrigating
# 2020/04/08: dir variables changed
# 2020/04/08: check_openev function added
# 2020/04/07: calling raincheck silent inside loop
# 2020/04/07: new verbose output
# 2020/04/03: lock for overlapped schedules
# 2019/08/18: called script with absolute path

start_irrigation()
{
	verbose && echo running \" $pigarden open $evlabel \" command
	$pigarden open $evlabel 
}

stop_irrigation()
{
	verbose && echo running \" $pigarden close $evlabel \" command
	$pigarden close $evlabel 
}

check_openev()
{
	for evfile in $STATUS_DIR/ev*
	do
		evstatus=$(< $evfile)
		ev=$(basename $evfile)
		evalias=${ev^^}
        	if ! getidx evalias $evalias ; then
                	echo "ERROR: getidx function - evalias $1 is not present"
                	exit 1
        	fi
        	evlabel=${EVLABEL[$idx]}

		if (( evstatus == 1 )) ; then
			echo "WARNING: $evlabel ($evalias) seems to be open from piGarden status dir (file $evfile)"
		fi
	done
}


INCLUDE_DIR_SCRIPT="$(cd `dirname $0` ; pwd )"
NAME_SCRIPT=${0##*/}

FUNCTIONS=$INCLUDE_DIR_SCRIPT/functions.include.sh
RAINFUNCT=$INCLUDE_DIR_SCRIPT/rain.include.sh

DIR_SCRIPT="$(dirname $INCLUDE_DIR_SCRIPT )" # one level upper ..
LOGDIR="$DIR_SCRIPT/log" 
TMPDIR="$DIR_SCRIPT/tmp"
STATDIR="$DIR_SCRIPT/state"

raincheck_waitloop=$INCLUDE_DIR_SCRIPT/raincheck-waitloop.sh
TEST=$INCLUDE_DIR_SCRIPT/TEST

cfgfiles=$DIR_SCRIPT/.cfgfiles
. $cfgfiles || { echo "ERROR: while executing $cfgfiles or not found" ; exit 1 ; }

for sourcefile in $PIGARDENSCHED_CONF $FUNCTIONS $RAINFUNCT $PIGARDEN_CONFIG_ETC
do
        . $sourcefile || { echo "ERROR: while executing $sourcefile or not found" ; exit 1 ;
}
done

pigarden=$PIGARDEN_HOME/piGarden.sh
if [ ! -x $pigarden ] ; then
	echo "ERROR: $pigarden not found"
	exit 1
fi

# needed for getting relation between EVALIAS & EVLABEL
parsingfilesched $PIGARDENSCHED

if [[ $# = 0 ]] ; then
	echo "ERROR: $NAME_SCRIPT mush be called with parameters, at least one like this: EVLABEL:DURATION"
	exit 1
fi

echo -e "\ncalled $INCLUDE_DIR_SCRIPT/$NAME_SCRIPT $*"

if [[ $# = 1 ]] ; then
	type=SINGLE
	echo "----- STARTING $type IRRIGATION -----"
else
	type=MULTI
	echo "----- STARTING $type IRRIGATION - $# EVs CONCATENATED -----"
fi

for parm in $*
do
	opendone=false

	set -- ${parm//:/ }
	evlabel=$1
	duration=$2

	if ! getidx evlabel $evlabel ; then
        	echo "ERROR: getidx function - evlabel $1 is not present"
	        exit 1
	fi
	evalias=${EVALIAS[$idx]}

#	lockfile=$DIR_SCRIPT/.${evalias}.lock
	lockfile=$STATDIR/.${evalias}.lock

	if [[ -f $lockfile ]] ; then
		echo "ERROR: lockfile $lockfile is present"
		echo "WARNING: check $evlabel ($evalias) and close EV in case with following command"
		echo "         $pigarden close $evlabel "
		echo "         then you can delete lockfile $lockfile"
		check_openev
		exit 1
	fi
	
	if $raincheck_waitloop $evlabel raincheck ; then
		# RAIN
		echo "$(d) WARNING: irrigation EV $evlabel is suspended for rain"
	else
		# NO RAIN
		start_secs=$( date '+%s' )
		echo "$(d) NORMAL: starting irrigation EV $evlabel for $duration minutes"
		touch $lockfile
		verbose && echo "NORMAL: lockfile $lockfile created"
		if [[ ! -f $TEST ]] ; then
			start_irrigation
			opendone=true
		else
			echo "TEST flag \"$TEST\" found - \"piGarden.sh open $evlabel\" is not executed"
		fi

		# wait loop
		if $raincheck_waitloop $evlabel wait $duration ; then
			# RAIN
			echo "$(d) WARNING: irrigation EV $evlabel is suspended for rain while irrigating"
		fi

		if [[ ! -f $TEST ]] ; then
			stop_irrigation
		else
			if [[ $opendone = true ]] ; then
				echo "TEST flag \"$TEST\" found but added while irrigating"
				echo "WARNING: stop irrigation anyway"
				stop_irrigation
			else
				echo "TEST flag \"$TEST\" found - \"piGarden.sh close $evlabel\" is not executed"
			fi
			
		fi
		end_secs=$( date '+%s' )
		rm $lockfile
		verbose && echo "NORMAL: lockfile $lockfile removed"
		(( irrigation_mins=(end_secs-start_secs)/60 ))
		echo "$(d) NORMAL: end irrigation EV $evlabel after $irrigation_mins mins"
		statupdate_irrigation $evalias $start_secs $irrigation_mins
	fi
	sleep 2
done

echo "----- FINISHED $type IRRIGATION -----"
