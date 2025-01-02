#!/bin/bash
NATPMP_IP="$1"

# Run natpmpc once to populate files
RES=$(natpmpc -a 1 0 udp 60 -g "$NATPMP_IP" && natpmpc -a 1 0 tcp 60 -g "$NATPMP_IP")

if [ $? -ne 0 ]; then
    echo -e "ERROR with natpmpc command \a"
    break
fi

if [ ! -f /shared/port.dat ]; then
    PORT=$(echo $RES | grep 'Mapped public port' | grep 'protocol TCP' | awk '{print $4}')
    PUBLIC_IP=$(echo $RES | grep 'Public IP address' | awk '{print $NF}' | head -1)

    echo "$PORT" > /shared/port.dat
    echo "$PUBLIC_IP" > /shared/public_ip.dat
fi

sleep 45
while true; do
    natpmpc -a 1 0 udp 60 -g "$NATPMP_IP" && natpmpc -a 1 0 tcp 60 -g "$NATPMP_IP"
    
    if [ $? -ne 0 ]; then
        echo -e "ERROR with natpmpc command \a"
        break
    fi
    
    sleep 45
done
