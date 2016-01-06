#!/bin/bash -x

#[ -z "$ID" ] && export ID=001

[ -z "$HOSTS" ] && HOSTS='2 3 4 5'
[ -z "$IP_PREFIX" ] && IP_PREFIX='10.0.0.'
[ -z "$SUBNET" ] && export SUBNET='10.10.0.0/29'

IPS=''
for h in $HOSTS; do IPS="$IPS $IP_PREFIX$h"; done

docker-machine create --driver vmwarefusion \
	--vmwarefusion-no-share --vmwarefusion-disk-size 5000 --vmwarefusion-memory-size 1024 \
	'zookeeper'
	
docker $(docker-machine config zookeeper) run -d -p 8181:8181 -p 2181:2181 -p 2888:2888 -p 3888:3888 \
        -h zookeeper.local --name zookeeper.local -e HOSTNAME=zookeeper.local mbabineau/zookeeper-exhibitor:latest
        

for h in $HOSTS; do
	docker-machine create --driver vmwarefusion \
		--vmwarefusion-no-share --vmwarefusion-disk-size 2000 --vmwarefusion-memory-size 512 \
		--engine-opt="cluster-advertise=eth0:2376" --engine-opt="$cluster_store" \
		"alpine$h"
done

any_host_=$(echo "$HOSTS" | awk '{print $1}')
eval $(docker-machine env "alpine$any_host_")
docker network create --driver overlay --subnet="$SUBNET" 'multihost'

for h in $HOSTS; do
	cmd_='for h in '"$IPS"'; do ping -q -c 1 $h >/dev/null; [ $? -eq 0 ] && echo $(hostname)": can ping $h";done'
	eval $(docker-machine env "alpine$h")
	docker run --rm --net='multihost' gliderlabs/alpine sh -c "$cmd_"
done

docker-machine stop $(docker-machine ls | grep zookeeper|awk '{print $1}')
docker-machine rm -f $(docker-machine ls | grep zookeeper|awk '{print $1}')
docker-machine stop $(docker-machine ls | grep alpine|awk '{print $1}')
docker-machine rm -f $(docker-machine ls | grep alpine|awk '{print $1}')
