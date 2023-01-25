#!/bin/bash

# Pull external IP
IPADDRESS=$(curl -s http://ifconfig.me/ip)
export IPADDRESS=$IPADDRESS

memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Convert kB to GB
gb_memory=$(echo "scale=2; $memory / 1048576" | bc)

shm_memory=$(echo "scale=2; $gb_memory / 3" | bc)

CRATE_HEAP_SIZE=$(echo $shm_memory | awk '{print int($0+0.5)}')
export CRATE_HEAP_SIZE=$CRATE_HEAP_SIZE"G"
export shm_memory=$shm_memory"G"

set -ae

## add in code to search and remove the machine name from tailscale if it already exists
deviceid=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq '.devices[] | select(.hostname=="'$HOSTNAME'")' | jq -r .id)
export deviceid=$deviceid

echo "Deleting the device from Tailscale"
curl -s -X DELETE https://api.tailscale.com/api/v2/device/$deviceid -u $TSAPIKEY: || echo "Error deleting $deviceid"

### getting a list of remaining devices
# Make the GET request to the Tailscale API to retrieve the list of all devices
# This could be updated to grab the DNS domain too to be more flexable.
response=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq -r '.devices[].hostname')
# Output the hostnames left as a comma-separated list. This will be used by the crate seed host parameter
hostnames=$(echo $response | tr ' ' '\n' | awk '{print $0".chimp-beta.ts.net:4300"}' | tr '\n' ',')
if [ -n hostnames ]; then
    hostnames=${hostnames%?}
else
    hostnames="nexus.chimp-beta.ts.net:4300"
fi



# Make sure directories exist as they are not automatically created
# This needs to happen at runtime, as the directory could be mounted.
sudo mkdir -pv $CRATE_GC_LOG_DIR $CRATE_HEAP_DUMP_PATH $TS_STATE
sudo chmod -R 777 /data

if [ -c /dev/net/tun ]; then
    sudo tailscaled &
    sudo tailscale up --authkey=${TSKEY} --accept-risk=all --accept-routes --accept-dns=true
else
    echo "tun doesn't exist"
    sudo tailscaled -tun userspace-networking -state mem: -socks5-server localhost:1080 -outbound-http-proxy-listen=localhost:3128
    export ALL_PROXY=socks5h://localhost:1080
    export http_proxy=socks5h://localhost:3128
    sudo tailscale up --authkey=${TSKEY} --accept-risk=all --accept-routes --accept-dns=true
fi

# TS_STATE environment variable would specify where the tailscaled.state file is stored, if that is being set.
# TS_STATEDIR environment variable would specify a directory path other than /var/lib/tailscale, if that is being set.


while [ not $status = "Running" ]
    do
        echo "Waiting for tailscale to start..."
        status="$(tailscale status -json | jq -r .BackendState)"
done



if [ -z "$TSAPIKEY" ]; then
  echo "Environmental variable for TSAPIKEY not set"
  exit 1
fi


echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" | sudo tee /etc/sysctl.conf
echo "net.ipv6.conf.lo.disable_ipv6=1" | sudo tee /etc/sysctl.conf
echo "vm.max_map_count = 262144" | sudo tee /etc/sysctl.conf

# If NODETYPE is "head", run the supernode command and append some text to .bashrc
if [ "$NODETYPE" = "head" ]; then

ray start --head --num-cpus=0 --num-gpus=0 --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address nexus.chimp-beta.ts.net

/crate/bin/crate -Cnetwork.host=_tailscale0_,_local_ \
            -Cnode.name=nexus \
            -Cnode.master=true \
            -Cnode.data=false \
            -Cnode.store.allow_mmap=false \
            -Chttp.cors.enabled=true \
            -Chttp.cors.allow-origin="/*" \
            -Cdiscovery.seed_hosts=$hostnames \
            -Ccluster.initial_master_nodes=nexus \
            -Ccluster.routing.allocation.enable=full \
            -Ccluster.graceful_stop.min_availability=primaries \
            -Cstats.enabled=false &


else

ray start --address='nexus.chimp-beta.ts.net:6379' --disable-usage-stats --node-ip-address ${HOSTNAME}.chimp-beta.ts.net

/crate/bin/crate -Cnetwork.host=_tailscale0_,local \
#            -Cnode.master=false \
            -Cnode.data=true \
            -Cnode.store.allow_mmap=false \
            -Chttp.cors.enabled=true \
            -Chttp.cors.allow-origin="/*" \
            -Cdiscovery.seed_hosts=$hostnames \
            -Ccluster.initial_master_nodes=nexus \
            -Ccluster.routing.allocation.enable=full \
            -Ccluster.graceful_stop.min_availability=primaries \
            -Cstats.enabled=false &

fi

#CREATE REPOSITORY s3backup TYPE s3
#[ WITH (parameter_name [= value], [, ...]) ]
#[ WITH (access_key = ${AWS_ACCESS_KEY_ID}, secret_key = ${AWS_SECRET_ACCESS_KEY}), endpoint = s3.${AWS_DEFAULT_REGION}.amazonaws.com, bucket = ${AWS_S3_BUCKET}, base_path=crate/ ]
#


# SIGTERM-handler this funciton will be executed when the container receives the SIGTERM signal (when stopping)
term_handler(){
    echo "***Stopping"
    echo "Running Cluster Election"
    /usr/local/bin/crash -c "SET GLOBAL TRANSIENT 'cluster.routing.allocation.enable' = 'new_primaries';" \
    && echo "Running Decomission" \
    && $dbserver=$(tailscale ip --1) \
    && /usr/local/bin/crash --hosts $dbserver -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';"

    deviceid=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq '.devices[] | select(.hostname=="'$HOSTNAME'")' | jq -r .id)
    export deviceid=$deviceid
    echo "Deleting the device from Tailscale"
    curl -s -X DELETE https://api.tailscale.com/api/v2/device/$deviceid -u $TSAPIKEY: || echo "Error deleting $deviceid"
    echo "Shutting Tailscale Down"
    sudo tailscale down
    exit 0
}

# Setup signal handlers
trap 'term_handler' SIGTERM

#echo "***Starting"
#/bin/tcsh ./my-command

# Running something in foreground, otherwise the container will stop
while true
do
   #sleep 1000 - Doesn't work with sleep. Not sure why.
   tail -f /dev/null & wait ${!}
done
