#!/bin/ash

set -e

default_route_ip=$(ip route | grep default | awk '{print $3}')
if [[ -z "$default_route_ip" ]]; then
	echo "No default route configured" >&2
	exit 1
fi

configs=`find /etc/wireguard -type f -printf "%f\n"`
if [[ -z "$configs" ]]; then
	echo "No configuration file found in /etc/wireguard" >&2
	exit 1
fi

config=`echo $configs | head -n 1`
interface="${config%.*}"

if [[ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark)" != "1" ]]; then
	echo "sysctl net.ipv4.conf.all.src_valid_mark=1 is not set" >&2
	exit 1
fi

# The net.ipv4.conf.all.src_valid_mark sysctl is set when running the container, so don't have WireGuard also set it
sed -i "s:sysctl -q net.ipv4.conf.all.src_valid_mark=1:echo Skipping setting net.ipv4.conf.all.src_valid_mark:" /usr/bin/wg-quick

# Start WireGuard
wg-quick up $interface

# IPv4 kill switch: traffic must be either (1) to the WireGuard interface, (2) marked as a WireGuard packet, (3) to a local address, or (4) to the container network
container_ipv4_network="$(ip -o addr show dev eth0 | awk '$3 == "inet" {print $4}')"
container_ipv4_network_rule=$([ ! -z "$container_ipv4_network" ] && echo "! -d $container_ipv4_network" || echo "")
iptables -I OUTPUT ! -o $interface -m mark ! --mark $(wg show $interface fwmark) -m addrtype ! --dst-type LOCAL $container_ipv4_network_rule -j REJECT

# IPv6 kill switch: traffic must be either (1) to the WireGuard interface, (2) marked as a WireGuard packet, (3) to a local address, or (4) to the container network
container_ipv6_network="$(ip -o addr show dev eth0 | awk '$3 == "inet6" && $6 == "global" {print $4}')"
if [[ "$container_ipv6_network" ]]; then
	container_ipv6_network_rule=$([ ! -z "$container_ipv6_network" ] && echo "! -d $container_ipv6_network" || echo "")
	ip6tables -I OUTPUT ! -o $interface -m mark ! --mark $(wg show $interface fwmark) -m addrtype ! --dst-type LOCAL $container_ipv6_network_rule -j REJECT
else
	echo "IPv6 interface not found, skipping IPv6 kill switch" >&2
fi

# Allow traffic to local subnets
for local_subnet in ${LOCAL_SUBNETS//,/$IFS}
do
	echo "Allowing traffic to local subnet ${local_subnet}" >&2
	ip route add $local_subnet via $default_route_ip
	iptables -I OUTPUT -d $local_subnet -j ACCEPT
done

if [ -n "$NATPMP_ENABLE" ]; then
  bash natpmp.sh ${NATPMP_IP:-10.2.0.1} &
  
  sleep 2
fi

if [ -n "$PF_PORT" ] && [ -n "$PF_DEST_IP" ]; then
  if [ "$NATPMP_ENABLE" -eq 1 ]; then
    PORT=$(grep 'Mapped public port' /tmp/natpmp_output | grep 'protocol TCP' | awk '{print $4}')
    PUBLIC_IP=$(grep 'Public IP address' /tmp/natpmp_output | awk '{print $NF}' | head -1)

    mkdir -p /shared/
    echo "$PORT" > /shared/port.dat
    
    iptables -t nat -A PREROUTING -i wg0 -p tcp --dport "$PORT" -j DNAT --to-destination "$PF_DEST_IP":"$PF_PORT"
    iptables -A FORWARD -p tcp -d "$PF_DEST_IP" --dport "$PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -A POSTROUTING -d "$PF_DEST_IP" -p tcp --dport "$PF_PORT" -j MASQUERADE
  
    iptables -t nat -A PREROUTING -i wg0 -p udp --dport "$PORT" -j DNAT --to-destination "$PF_DEST_IP":"$PF_PORT"
    iptables -A FORWARD -p udp -d "$PF_DEST_IP" --dport "$PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -A POSTROUTING -d "$PF_DEST_IP" -p udp --dport "$PF_PORT" -j MASQUERADE
    
    echo "Forwarding incoming VPN traffic from $PUBLIC_IP:$PORT to $PF_DEST_IP:$PF_PORT"
  else
    iptables -t nat -A PREROUTING -i wg0 -p tcp --dport "$PF_PORT" -j DNAT --to-destination "$PF_DEST_IP":"$PF_PORT"
    iptables -A FORWARD -p tcp -d "$PF_DEST_IP" --dport "$PF_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -A POSTROUTING -d "$PF_DEST_IP" -p tcp --dport "$PF_PORT" -j MASQUERADE
  
    iptables -t nat -A PREROUTING -i wg0 -p udp --dport "$PF_PORT" -j DNAT --to-destination "$PF_DEST_IP":"$PF_PORT"
    iptables -A FORWARD -p udp -d "$PF_DEST_IP" --dport "$PF_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    iptables -t nat -A POSTROUTING -d "$PF_DEST_IP" -p udp --dport "$PF_PORT" -j MASQUERADE
    
    WG_IP=$(wg show wg0 endpoints | awk '{print $2}' | cut -d: -f1)
    echo "Forwarding incoming VPN traffic from $WG_IP:$PF_PORT to $PF_DEST_IP:$PF_PORT"
  fi
fi

shutdown () {
	wg-quick down $interface
	exit 0
}

trap shutdown SIGTERM SIGINT SIGQUIT

sleep infinity &
wait $!
