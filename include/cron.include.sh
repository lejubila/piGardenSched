#!/bin/bash
# piGardenSched
# "cron.include.sh"
# Author: androtto
# VERSION=0.3.6f
# 2020/09/19 cron_check fixed
# 2021/06/15 cron_check fixed, added 2nd entry (at boot)

pigardensched="$DIR_SCRIPT/$NAME_SCRIPT"
logpigardensched="$LOGDIR/${NAME_SCRIPT//[.]*/}.log"
tmpcronoutput="$TMPDIR/crontab.output"
cronentry[0]="* * * * * $pigardensched >> $logpigardensched 2>&1"
cronentry[1]="@reboot $pigardensched boot >> $logpigardensched 2>&1"
echo "${cronentry[0]}" > "$DIR_SCRIPT/conf/line_to_add-crontab"
echo "${cronentry[1]}" >> "$DIR_SCRIPT/conf/line_to_add-crontab"


cron_add()
{
	$CRONTAB -l > $tmpcronoutput 2> /dev/null

	( cat $tmpcronoutput ; echo -e "${cronentry[0]}\n${cronentry[1]}" ) | $CRONTAB -
	
}

cron_check()
{
	#cronentrychecked="$( $CRONTAB -l | $GREP "$cronentry" )"
	#echo "$cronentrychecked"
	(( i = 0 ))
	while (( i <= 1 ))
	do
		cron_entry="${cronentry[$i]}"
		if [[ -n "$( $CRONTAB -l | $GREP "$cron_entry" )" ]] ; then
			if [[ -n "$( $CRONTAB -l | awk -v linea="$cron_entry" '$0==linea {print "OK"}' )" ]] ; then
				echo "NORMAL: crontab entry #$i for $NAME_SCRIPT found and active"
			else
				echo "ERROR: crontab entry #$i for $NAME_SCRIPT found but INACTIVE"
				echo -e "\trun     $pigardensched crondel\n\t\t$pigardensched cronadd\n\tto fix"
				return 1
			fi
		else
			echo "ERROR: crontab entry for $NAME_SCRIPT NOT found"
			echo -e "\tentries should be:\n$(< "$DIR_SCRIPT/conf/line_to_add-crontab")"
			return 1
		fi
		(( i += 1 ))
	done
	return 0
}

cron_del()
{
	$CRONTAB -l | $GREP -v $DIR_SCRIPT/$NAME_SCRIPT > $tmpcronoutput 2> /dev/null

	cat $tmpcronoutput | $CRONTAB -
}
