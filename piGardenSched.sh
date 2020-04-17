#!/bin/bash
#
# pigarden sched
# main script "piGardenSched.sh"
# Author: androtto
# VERSION=0.3.6c
VERSION=0
SUB_VERSION=3
RELEASE_VERSION=6c
# 2020/04/17: fixed cron calls
# 2019/09/13: TMPDIR changed
# 2019/08/13: irrigation option has improved

##### MAIN
now=$(date +%s )
# for testing only
if [[ $1 = "run" ]] ; then
	now=$2 
	echo "DEBUG: now is overrided with $2 $(date --date="@$now")"
fi

DIR_SCRIPT="$(cd `dirname $0` ; pwd )"
NAME_SCRIPT=${0##*/}
FUNCTIONS=$DIR_SCRIPT/include/functions.include.sh
RAINFUNCT=$DIR_SCRIPT/include/rain.include.sh
CRONFUNCT=$DIR_SCRIPT/include/cron.include.sh
LOGDIR="$DIR_SCRIPT/log" ; [ ! -d "$LOGDIR" ] && mkdir $LOGDIR
TMPDIR="/tmp/${NAME_SCRIPT/.sh/}" ; [ ! -d "$TMPDIR" ] && mkdir $TMPDIR
STATDIR="$DIR_SCRIPT/state" ; [ ! -d "$STATDIR" ] && mkdir $STATDIR
BCKDIR="$DIR_SCRIPT/bck" ; [ ! -d "$BCKDIR" ] && mkdir $BCKDIR
irrigating=$DIR_SCRIPT/include/irrigating.sh
cfgfiles=$DIR_SCRIPT/.cfgfiles
. $cfgfiles || { echo "ERROR: while executing $cfgfiles or not found" ; exit 1 ; }

for sourcefile in $PIGARDENSCHED_CONF $FUNCTIONS $RAINFUNCT $CRONFUNCT $PIGARDEN_CONFIG_ETC
do
	. $sourcefile || { echo "ERROR: while executing $sourcefile or not found" ; exit 1 ; }
done


# help:
if [[ $1 = "help" || $1 = "-help" || $1 = "-h" ]] ; then
	help
	exit 0
fi

# corregge l'orario al secondo 00
now=$(echo $now | $JQ './60' | $JQ 'floor' | $JQ '.*60' )
date_now=$(date --date="@$now")
time_now="$(date --date="@$now" '+%R')"
day_now="$(date --date="@$now" '+%d')"

declare -a EV LONG TIME_SCHED DAYFREQ EVLABEL
declare -g maxline

PIGARDENSCHED_save=$TMPDIR/${NAME_SCRIPT/.sh/}_save$$ 
PIGARDENSCHED_TMP=$TMPDIR/${NAME_SCRIPT/.sh/} ; > $PIGARDENSCHED_TMP
#cp -p $PIGARDENSCHED $PIGARDENSCHED_save
if [ ! -f $PIGARDENSCHED ] ; then
        echo "WARNING: piGarden_sched Config file not found in $PIGARDENSCHED"
	echo -e "\tcreating empty file"
	update_cfgfile
fi

#### body script
parsingfilesched "$PIGARDENSCHED"

case $1 in
	stat|status)  
		status
		;;
	reset)  en_echo "NORMAL: resetting irrigation status for all EVs"
		tar cvf $BCKDIR/bck_STATDIR_$$.tar $STATDIR
		rm $STATDIR/*
		;;
	add)    shift
		[[ $# -ne 4 ]] && { en_echo "ERROR: 4 parameters needed\n$NAME_SCRIPT add EV? duration time frequency" ; exit 1 ; }
		check_evalias $1 || { en_echo "ERROR: $1 is not a valid EV" ; exit 1 ; }
		check_number $2 || { echo "ERROR: $2 is not a valid duration in minutes" ; exit 1 ; }
		check_timeformat $3 || { en_echo "ERROR: $3 is not a valid time" ; exit 1 ; }
		check_number $4 || { echo "ERROR: $4 is not a valid frequency in days" ; exit 1 ; }
		if insert $1 $2 $3 $4 ; then
			en_echo "SUCCESS adding new schedule for $1"
			exit 0
		else
			en_echo "ERROR adding new schedule for $1"
			exit 1
		fi
		;;
	seq)    shift
		[[ $# -eq 1 ]] && { echo "ERROR: at least 2 parameters needed" ; exit 1 ; }
		if sequential $* ; then
			en_echo "SUCCESS creating sequence $*"
		else
			exit 1
		fi
		;;
	noseq)  if convert ; then
			en_echo "NORMAL: change done"
		else
			en_echo "$err_msg"
			exit 1
		fi
		;;
	change_dur)	shift
		[[ $# -ne 2 ]] && { echo "ERROR: 2 parameters needed after change_dur option" ; exit 1 ; }
		check_evalias $1 || { echo "ERROR: $1 is not a valid EV" ; exit 1 ; }
		check_number $2 || { echo "ERROR: $2 is not a valid duration in minutes" ; exit 1 ; }
		if modify duration $1 $2 ; then
			en_echo "NORMAL: change done"
		else
			en_echo "ERROR: action aborted"
			exit 1
		fi
		;;
	change_freq)	shift
		[[ $# -ne 2 ]] && { echo "ERROR: 2 parameters needed after change_freq option" ; exit 1 ; }
		check_evalias $1 || { echo "ERROR: $1 is not a valid EV" ; exit 1 ; }
		check_number $2 || { echo "ERROR: $2 is not a valid frequency in days" ; exit 1 ; }
		if modify freq $1 $2 ; then
			en_echo "NORMAL: change done"
		else
			en_echo $err_msg
			exit 1
		fi
		;;
	change_time)	shift
		[[ $# -ne 2 ]] && { echo "ERROR: 2 parameters needed after change_time option" ; exit 1 ; }
		check_evalias $1 || { echo "ERROR: $1 is not a valid EV" ; exit 1 ; }
		check_timeformat $2 || { echo "ERROR: $2 is not a valid time" ; exit 1 ; }
		if modify time $1 $2 ; then
			en_echo "NORMAL: change done"
		else
			en_echo $err_msg
			exit 1
		fi
		;;
	del_time)	shift
		[[ $# -ne 2 ]] && { echo "ERROR: 2 parameters needed after change_time option" ; exit 1 ; }
		check_evalias $1 || { echo "ERROR: $1 is not a valid EV" ; exit 1 ; }
		check_timeformat $2 || { echo "ERROR: $2 is not a valid time" ; exit 1 ; }
		if remove_time $1 $2 ; then
			en_echo "NORMAL: $2 removed from $1 entry"
		else
			en_echo "$err_msg"
			exit 1
		fi
		;;
	add_time)	shift
		[[ $# -ne 2 ]] && { echo "ERROR: 2 parameters needed after add_time option" ; exit 1 ; }
		check_evalias $1 || { echo "ERROR: $1 is not a valid EV" ; exit 1 ; }
		check_timeformat $2 || { echo "ERROR: $2 is not a valid time" ; exit 1 ; }
		if add_time $1 $2 ; then
			en_echo "NORMAL: $2 added to $1 entry"
		else
			en_echo "$err_msg"
			exit 1
		fi
		;;
	show|sched)	grep -v ^# $PIGARDENSCHED
		;;
 	del)	shift
		[[ $# -ne 1 ]] && { echo "ERROR: 1 parameter needed" ; exit 1 ; }
		check_evalias $1 || { echo "error check_evalias" ; exit 1 ; }
		if remove $1 ; then
			en_echo "$msg"
		else
			en_echo "$msg"
			exit 1
		fi
		;;
	history) history ;;
	irrigation) shift 
		case $# in
			2)
				check_evalias $2 || { echo "ERROR: $2 is not a valid EV" ; exit 1 ; }
				[[ $1 =~ ^[0-9]*$ ]] || { echo "ERROR: irrigation history parameter must be an integer" ; exit 1 ; }
				irrigation_history $1 $2
				;;
			1)
				[[ $1 =~ ^[0-9]*$ ]] || { echo "ERROR: irrigation history parameter must be an integer" ; exit 1 ; }
				irrigation_history $1
				;;
			0) irrigation_history 
				;;
		esac
		;;
	enable) shift
		[[ $# -ne 1 ]] && { echo "ERROR: 1 parameter needed after enable option" ; exit 1 ; }
		check_evalias $1 || { echo "ERROR: $1 is not a valid EV" ; exit 1 ; }
		if modify enable $1 ; then
			en_echo "NORMAL: change done"
		else
			en_echo $err_msg
			exit 1
		fi
		;;
	disable) shift
		[[ $# -ne 1 ]] && { echo "ERROR: 1 parameter needed after disable option" ; exit 1 ; }
		check_evalias $1 || { echo "ERROR: $1 is not a valid EV" ; exit 1 ; }
		if modify disable $1 ; then
			en_echo "NORMAL: change done"
		else
			en_echo $err_msg
			exit 1
		fi
		;;
	cronadd) cron_del ; cron_add ; echo "NORMAL: cronadd done" ;;
	crondel) cron_del ; echo "NORMAL: crondel done" ;;
	croncheck) cron_check && exit 0 || exit 1  ;;
	run|*)  
		schedule
		;;
esac	

exit 0
