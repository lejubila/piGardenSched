#!/bin/bash
# piGardenSched
# "cron.include.sh"
# Author: androtto
# VERSION=0.3.3

pigardensched="$DIR_SCRIPT/$NAME_SCRIPT"
logpigardensched="$LOGDIR/${NAME_SCRIPT//[.]*/}.log"
tmpcronoutput="$TMPDIR/crontab.output"
cronentry="* * * * * $pigardensched >> $logpigardensched 2>&1"
echo "$cronentry" > "$DIR_SCRIPT/conf/line_to_add-crontab"


cron_add()
{
	$CRONTAB -l > $tmpcronoutput 2> /dev/null

	( cat $tmpcronoutput ; echo "$cronentry" ) | $CRONTAB -
	
}

cron_check()
{
	#cronentrychecked="$( $CRONTAB -l | $GREP "$cronentry" )"
	#echo "$cronentrychecked"

	if [ -n "$( $CRONTAB -l | $GREP "$cronentry" )" ] ; then
		echo "NORMAL: crontab entry for $NAME_SCRIPT found"
		return 0
	else
		echo "ERROR: crontab entry for $NAME_SCRIPT NOT found"
		echo -e "\tentry should be:\n\t\"$cronentry\""
		return 1
	fi
}

cron_del()
{
	$CRONTAB -l | $GREP -v $DIR_SCRIPT/$NAME_SCRIPT > $tmpcronoutput 2> /dev/null

	cat $tmpcronoutput | $CRONTAB -
}
