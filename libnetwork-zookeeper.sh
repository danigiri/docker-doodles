#!/bin/bash

#[ -z "$ID" ] && export ID=001

#DRIVER_OPTS=${DRIVER_OPTS:-'--driver vmwarefusion --vmwarefusion-no-share --vmwarefusion-disk-size 2000 --vmwarefusion-memory-size 512'}
DRIVER_OPTS=${DRIVER_OPTS:-'--driver virtualbox --virtualbox-no-share --virtualbox-disk-size 2000 --virtualbox-memory 512'}
[ -z "$HOSTS" ] && HOSTS='a b c'
[ -z "$CONTAINERS" ] && CONTAINERS='2 3 4'
[ -z "$IP_PREFIX" ] && IP_PREFIX='10.10.0.'
[ -z "$SUBNET" ] && SUBNET='10.10.0.0/24'
[ -z "$NETWORK" ] && NETWORK='multihost'
[ -z "$SAME_HOST" ] && SAME_HOST=


IPS=''
for c in $CONTAINERS; do IPS="$IPS $IP_PREFIX$c"; done

ZK_='zookeeper'
HOST_='host'

echo '**** Creating zookeeper host ****'

docker-machine ls | grep "$ZK_"
if [ $? -ne 0 ] ; then
docker-machine create $DRIVER_OPTS "$ZK_"
else
	echo "Host $ZK_ exists"
fi

echo '**** Running zookeeper container (takes a while) ****'
#docker $(docker-machine config "$ZK_") run -d -p 8181:8181 -p 2181:2181 -p 2888:2888 -p 3888:3888 \
#        -h zookeeper.local --name zookeeper.local -e HOSTNAME=zookeeper.local mbabineau/zookeeper-exhibitor:latest
docker $(docker-machine config "$ZK_") run -d -p 8181:8181 -p 2181:2181 -p 2888:2888 -p 3888:3888 \
        -h zookeeper.local --name zookeeper.local -e HOSTNAME=zookeeper.local jplock/zookeeper:latest
        
printf %s '**** Creating host machines '
cluster_store="cluster-store=zk://$(docker-machine ip $ZK_):2181"
for h in $HOSTS; do
	echo "Creating $HOST_$h"
	docker-machine create $DRIVER_OPTS --engine-opt="cluster-advertise=eth0:2376" --engine-opt="$cluster_store" \
		"$HOST_$h"
done
echo

echo '**** Creating network ****'
first_host_=$(echo "$HOSTS" | awk '{print $1}')
eval $(docker-machine env "$HOST_$first_host_")
docker network create --driver overlay --subnet="$SUBNET" "$NETWORK"
docker network inspect "$NETWORK" | head -7

printf %s '**** Running idle docker containers on hosts '
cmd_='sleep 1000'
if [ -z "$SAME_HOST" ]; then
	eval $(docker-machine env "$HOST_$first_host_")
	for c in $CONTAINERS; do
		echo "$HOST_$first_host_[$c]: ($cmd_)"
		docker run -d --name "sleep$c" --net="$NETWORK" gliderlabs/alpine sh -c "$cmd_"
	done
else
	c=1
	for h in $HOSTS; do
		container_=$(echo "$CONTAINERS" | awk '{print $'$c'}')
		echo "$HOST_$h[$container_]: ($cmd_)"
		eval $(docker-machine env "$HOST_$h")
		docker run -d --name "sleep$h" --net="$NETWORK" gliderlabs/alpine sh -c "$cmd_"
		let "c++"
	done
fi

cmd_='for h in '"$IPS"'; do ping -q -c 1 $h >/dev/null;if [ $? -eq 0 ]; then echo $(hostname)": ping $h OK" else echo $(hostname)": ping $h KO($?)";fi;done'
if [ -z "$SAME_HOST" ]; then
	for c in $CONTAINERS; do
		echo "$HOST_$first_host_[$c]: ($cmd_)"
		docker exec "$HOST_$first_host_" sh -c "$cmd_"
	done
else
	c=1
	for h in $HOSTS; do
		container_=$(echo "$CONTAINERS" | awk '{print $'$c'}')
		echo "$HOST_$h[$container_]: ($cmd_)"
		eval $(docker-machine env "$HOST_$first_host_")
		docker exec "$HOST_$h" sh -c "$cmd_"
	done
fi

exit 0

# bash -c 'for h in '"$HOSTS"'; do eval $(docker-machine env "alpine$h") && docker stop $(docker ps -q); done'
# bash -c 'for h in '"$HOSTS"'; do eval $(docker-machine env "alpine$h") && docker rm "alpine$h"; done'
# bash -c 'for h in '"$HOSTS"'; do docker-machine rm -f "alpine$h"; done; docker-machine rm -f zookeeper'



