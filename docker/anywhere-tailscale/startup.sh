#!/bin/bash


echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.lo.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
echo "vm.max_map_count = 262144" | sudo tee -a /etc/sysctl.conf
echo "vm.swappiness = 1" | sudo tee -a /etc/sysctl.conf



# Pull external IP
IPADDRESS=$(curl -s http://ifconfig.me/ip)
export IPADDRESS=$IPADDRESS

memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Convert kB to GB
gb_memory=$(echo "scale=2; $memory / 1048576" | bc)
shm_memory=$(echo "scale=2; $gb_memory / 3" | bc)
num_cpus=$(nproc)

if [ -z "$TSAPIKEY" ]; then
  echo "Environmental variable for TSAPIKEY not set"
  exit 1
fi

#settings number of cpus for optimial (local) speed
export NUMEXPR_MAX_THREADS=$num_cpus
#used by conda to specify cpus for building packages
export MAKEFLAGS="-j$num_cpus"
#used by conda
export CPU_COUNT=$num_cpus

CRATE_HEAP_SIZE=$(echo $shm_memory | awk '{print int($0+0.5)}')
export CRATE_HEAP_SIZE=$CRATE_HEAP_SIZE"G"
export shm_memory=$shm_memory"G"



functiontodetermine_cloud_provider() {
  if [ -f "/sys/hypervisor/uuid" ]; then
    # Check if the instance is running on GCP (not tested and probably wrong)
    UUID=$(cat /sys/hypervisor/uuid)
    if [[ $UUID =~ "gce" ]]; then
      location="GCP"
      export LOCATION=$location
      return
    fi
  elif [ -f "/sys/devices/virtual/dmi/id/product_uuid" ]; then
    # Check if the instance is running on AWS
    UUID=$(cat /sys/devices/virtual/dmi/id/sys_vendor)
    if [[ $UUID =~ "EC2" ]]; then
      location="AWS"
      export LOCATION=$location
      return
    fi
  elif [ -f "/proc/version" ]; then
    # Check if the instance is running on Azure (not tested and probably wrong)
    VERSION=$(cat /proc/version)
    if [[ $VERSION =~ "Microsoft" ]]; then
      location="Azure"
      export LOCATION=$location
      return
    fi
  fi
  location="OnPrem"
  export LOCATION=$location
  return
}

functiontodetermine_cloud_provider

functiontodetermine_cpu() {
  # Check if lscpu command exists
  if command -v lscpu >/dev/null 2>&1 ; then
      # Get vendor information from lscpu output
      vendor=$(lscpu | grep 'Vendor ID' | awk '{print $3}')

      # Check if vendor is AMD or Intel
      if [ "$vendor" == "AuthenticAMD" ]; then
        export CPU_VENDOR=$vendor
      elif [ "$vendor" == "GenuineIntel" ]; then
        export CPU_VENDOR=$vendor
      else
          echo "CPU vendor could not be determined."
      fi
  else
      echo "lscpu command not found. Unable to determine CPU vendor."
  fi
}

functiontodetermine_cpu

set -ae

## add in code to search and remove the machine name from tailscale if it already exists
deviceid=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq '.devices[] | select(.hostname=="'$HOSTNAME'")' | jq -r .id)
export deviceid=$deviceid

echo "Deleting the device from Tailscale"
curl -s -X DELETE https://api.tailscale.com/api/v2/device/$deviceid -u $TSAPIKEY: || echo "Error deleting $deviceid"



get_clusterhosts() {
  ### getting a list of remaining devices
  # Make the GET request to the Tailscale API to retrieve the list of all devices
  # This could be updated to grab the DNS domain too to be more flexable.
  # This is used for the parameter discovery.seed.hosts in crate.yml
  clusterhosts=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Error: failed to fetch list of devices from Tailscale API"
  fi
  clusterhosts=$(echo $clusterhosts | jq -r '.devices[].name')
  if [ $? -ne 0 ]; then
    echo "Error: failed to parse list of devices from Tailscale API response"
    clusterhosts="nexus.chimp-beta.ts.net:4300"
  fi

  clusterhosts="$(echo $clusterhosts | tr ' ' ',')"
}


$clusterhosts=get_clusterhosts

export CLUSTERHOSTS=$clusterhosts

# Make sure directories exist as they are not automatically created
# This needs to happen at runtime, as the directory could be mounted.
sudo mkdir -pv $CRATE_GC_LOG_DIR $CRATE_HEAP_DUMP_PATH $TS_STATE
sudo chmod -R 7777 /data

if [ -c /dev/net/tun ]; then
    sudo tailscaled &
    sudo tailscale up --authkey=${TSKEY} --accept-risk=all --accept-routes --accept-dns=true
else
    echo "tun doesn't exist"
    sudo tailscaled -tun userspace-networking -state mem: -socks5-server localhost:1080 -outbound-http-proxy-listen=localhost:3128 &
    export socks_proxy=socks5h://localhost:1080
    export ALL_PROXY=socks5h://localhost:1080
    export http_proxy=http://localhost:3128
    sudo tailscale up --authkey=${TSKEY} --accept-risk=all --accept-routes --accept-dns=true
fi

# TS_STATE environment variable would specify where the tailscaled.state file is stored, if that is being set.
# TS_STATEDIR environment variable would specify a directory path other than /var/lib/tailscale, if that is being set.




while [ ! $tailscale_status = "Running" ]
    do
        echo "Waiting for tailscale to start..."
        tailscale_status="$(tailscale status -json | jq -r .BackendState)"
done


# check if we already have state data
if [ -d "$CRATE_HEAP_DUMP_PATH" ]; then

	if [ -d "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/" ] && [ "$(ls -A $CRATE_HEAP_DUMP_PATH/nodes/0/_state/)" ]; then
        echo "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/ is not Empty"
        statedata=$true
	else
        echo "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/ is Empty"
        statedata=$false
	fi
else
	echo "Directory $CRATE_HEAP_DUMP_PATH not found."
    exit 1
fi


#if [ $location = "onPrem" ]; then
    #node_store_allow_mmap="-Cnode.store.allow_mmap=false \\"
#fi


if [ "$NODETYPE" = "head" ]; then
    node_name='-Cnode.name=nexus \\'
    node_master='-Cnode.master=true \\'
    node_data='-Cnode.data=false \\'

    ray start --head --num-cpus=0 --num-gpus=0 --disable-usage-stats --include-dashboard=True --dashboard-host 0.0.0.0 --node-ip-address nexus.chimp-beta.ts.net


else

    if [ ! $statedata ]; then
        cluster_initial_master_nodes='-Ccluster.initial_master_nodes=nexus \\'
    fi

    ray start --address='nexus.chimp-beta.ts.net:6379' --disable-usage-stats --node-ip-address $HOSTNAME.chimp-beta.ts.net

fi

/crate/bin/crate \
            ${cluster_initial_master_nodes}
            ${node_name}
            ${node_master}
            ${node_data}
            ${node_store_allow_mmap}
            &

/usr/local/bin/crash --hosts ${clusterhosts} -c "SET GLOBAL TRANSIENT 'cluster.routing.allocation.enable' = 'all';" &
#CREATE REPOSITORY s3backup TYPE s3
#[ WITH (parameter_name [= value], [, ...]) ]
#[ WITH (access_key = ${AWS_ACCESS_KEY_ID}, secret_key = ${AWS_SECRET_ACCESS_KEY}), endpoint = s3.${AWS_DEFAULT_REGION}.amazonaws.com, bucket = ${AWS_S3_BUCKET}, base_path=crate/ ]
#


# SIGTERM-handler this funciton will be executed when the container receives the SIGTERM signal (when stopping)
term_handler(){
    echo "***Stopping"
    ray stop -g 60 -v
    echo "Running Cluster Election"
    /usr/local/bin/crash -c "SET GLOBAL TRANSIENT 'cluster.routing.allocation.enable' = 'new_primaries';"
    echo "Running Decommission"
    $clusterhosts=get_clusterhosts
    /usr/local/bin/crash --hosts ${clusterhosts} -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';"


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

# Running something in foreground, otherwise the container will stop
while true
do
   #sleep 1000 - Doesn't work with sleep. Not sure why.
   tail -f /dev/null & wait ${!}
done