pigardensched="$DIR_SCRIPT/$NAME_SCRIPT"
logpigardensched="$LOGDIR/${NAME_SCRIPT//[.]*/}.log"
tmpcronoutput="$TMPDIR/crontab.output"
cronentry="* * * * * $pigardensched >> $logpigardensched 2>&1"


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
		return 1
	fi
}

cron_del()
{
	$CRONTAB -l | $GREP -v $NAME_SCRIPT > $tmpcronoutput 2> /dev/null

	cat $tmpcronoutput | $CRONTAB -
}
