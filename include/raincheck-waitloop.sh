#!/bin/bash
# piGardenSched
# loop script between open and close command
# Author: androtto
# VERSION=0.3.6
# 2020/04/07: calling raincheck silent inside loop


DIR_SCRIPT="$(cd `dirname $0` ; pwd )"
NAME_SCRIPT=${0##*/}
FUNCTIONS=$DIR_SCRIPT/functions.include.sh
RAINFUNCT=$DIR_SCRIPT/rain.include.sh

cfgfiles=$DIR_SCRIPT/../.cfgfiles
. $cfgfiles || { echo "ERROR: while executing $cfgfiles or not found" ; exit 1 ; }

for sourcefile in $PIGARDENSCHED_CONF $FUNCTIONS $RAINFUNCT $PIGARDEN_CONFIG_ETC
do
        . $sourcefile || { echo "ERROR: while executing $sourcefile or not found" ; exit 1 ; }
done

parsingfilesched $PIGARDENSCHED

if [[ $2 = raincheck && $# = 2 ]] ; then
	: # ok
elif [[ $2 = wait && $# = 3 ]] ; then
	: # ok
else
	echo -e "ERROR: $NAME_SCRIPT must be called in one of two modes\n\t$NAME_SCRIPT [EVLABEL] raincheck\n\t$NAME_SCRIPT [EVLABEL] wait [minutes]"
	exit 99
fi
	
evlabel=$1
if ! getidx evlabel $1 ; then
	echo "ERROR: getidx function - evlabel $1 is not present"
	exit 1
fi

rain_integration
[[ -z $RAINCHECK ]] && { echo "ERROR: \$RAINCHECK not set" ; exit 1 ; }

debug && echo DEBUG \$evlabel \$idx \${EVLABEL[$idx]} \${EVALIAS[$idx]} \${EVNORAINQTY[$idx]} \${EVNORAINCLASSIC[$idx]} 
debug && echo DEBUG $evlabel $idx ${EVLABEL[$idx]} ${EVALIAS[$idx]} ${EVNORAINQTY[$idx]} ${EVNORAINCLASSIC[$idx]}  

shift
case $1 in
	raincheck)
		if raincheck ; then
			if rained ; then
				exit 0 # 0 for rain	
			else
				exit 1 # 1 for not rain
			fi
		else
			exit 1 # no rain o raincheck disabled
		fi
		;;
	wait)	minutes=$2
		;;
esac

min=1

echo -e "waiting $minutes minutes \c"
while (( min <= minutes ))
do
	if raincheck silent ; then
		if rained ; then
			exit 0 # 0 for rain	
		fi 
	else
		raincheck_disabled="true"
	fi
	sleep 60
	(( min += 1 ))
	echo -e ".\c"
done
echo
exit 1 # 1 for not rain
