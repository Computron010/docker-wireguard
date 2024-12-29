#!/bin/bash
NATPMP_IP="$1"

while true; do
    RES=$(natpmpc -a 1 0 udp 60 -g "$NATPMP_IP" && natpmpc -a 1 0 tcp 60 -g "$NATPMP_IP")

    if [ $? -ne 0 ]; then
        echo -e "ERROR with natpmpc command \a"
        break
    fi

    echo "$RES" > /tmp/natpmp_output

    sleep 45
done
