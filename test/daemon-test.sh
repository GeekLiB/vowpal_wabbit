#!/bin/bash
# -- vw daemon test
#
NAME='vw-daemon-test'

export PATH="vowpalwabbit:../vowpalwabbit:${PATH}"
# The VW under test
VW=`which vw`

MODEL=$NAME.model
TRAINSET=$NAME.train
PREDREF=$NAME.predref
PREDOUT=$NAME.predict
PORT=54248

# -- make sure we can find vw first
if [ -x "$VW" ]; then
    : cool found vw at: $VW
else
    echo "$NAME: can not find 'vw' in $PATH - sorry"
    exit 1
fi

# -- and netcat
NETCAT=`which netcat`
if [ -x "$NETCAT" ]; then
    : cool found netcat at: $NETCAT
else
    NETCAT=`which nc`
    if [ -x "$NETCAT" ]; then
        : "no netcat but found 'nc' at: $NETCAT"
    else
        echo "$NAME: can not find 'netcat' not 'nc' in $PATH - sorry"
        exit 1
    fi
fi

# -- and pkill
PKILL=`which pkill`
if [ -x "$PKILL" ]; then
    : cool found pkill at: $PKILL
else
    echo "$NAME: can not find 'pkill' in $PATH - sorry"
    exit 1
fi


# A command (+pattern) that is unlikely to match anything but our own test
DaemonCmd="$VW -t -i $MODEL --daemon --num_children 1 --quiet --port $PORT"
# libtool may wrap vw with '.libs/lt-vw' so we need to be flexible
# on the exact process pattern we try to kill.
DaemonPat=`echo $DaemonCmd | sed 's/^[^ ]*vw /.*vw /'`

stop_daemon() {
    # Make sure we are not running. May ignore 'error' that we're not
    $PKILL -9 -f "$DaemonPat" 2>&1 | grep -q 'no process found'

    # relinquish CPU by forcing some context switches to be safe
    # (let existing vw daemon procs die)
    wait
}

start_daemon() {
    # echo starting daemon
    $DaemonCmd </dev/null >/dev/null &
    # give it time to be ready
    wait; wait; wait
}

cleanup() {
    /bin/rm -f $MODEL $TRAINSET $PREDREF $PREDOUT
    stop_daemon
}

# -- main
cleanup

# prepare training set
cat > $TRAINSET <<EOF
0.55 1 '1| a
0.99 1 '2| b c
EOF

# prepare expected predict output
cat > $PREDREF <<EOF
0.553585 1
0.733882 2
EOF

# Train
$VW -b 10 --quiet -d $TRAINSET -f $MODEL

start_daemon

# Test on train-set
# OpenBSD netcat quits immediately after stdin EOF
# nc.traditional does not, so let's use -q 1.
#$NETCAT -q 1 localhost $PORT < $TRAINSET > $PREDOUT
#wait
# However, GNU netcat does not know -q, so let's do a work-around
touch $PREDOUT
$NETCAT localhost $PORT < $TRAINSET > $PREDOUT &
# Wait until we recieve a prediction from the vw daemon then kill netcat
until [ `wc -l < $PREDOUT` -eq 2 ]; do :; done
$PKILL -9 $NETCAT

# We should ignore small (< $Epsilon) floating-point differences (fuzzy compare)
diff <(cut -c-5 $PREDREF) <(cut -c-5 $PREDOUT)
case $? in
    0)  echo "$NAME: OK"
        cleanup
        exit 0
        ;;
    1)  echo "$NAME FAILED: see $PREDREF vs $PREDOUT"
        stop_daemon
        exit 1
        ;;
    *)  echo "$NAME: diff failed - something is fishy"
        stop_daemon
        exit 2
        ;;
esac

