FROM alpine:3

# Add community repo
RUN sh -c 'echo "https://dl-cdn.alpinelinux.org/alpine/v$(cut -d. -f1,2 /etc/alpine-release)/main/" > /etc/apk/repositories && \
           echo "https://dl-cdn.alpinelinux.org/alpine/v$(cut -d. -f1,2 /etc/alpine-release)/community/" >> /etc/apk/repositories && \
           echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories' 

RUN apk update && apk add --no-cache findutils openresolv iptables ip6tables iproute2 wireguard-tools libnatpmp

COPY entrypoint.sh /entrypoint.sh
COPY natpmp.sh /natpmp.sh

ENTRYPOINT ["/entrypoint.sh"]
