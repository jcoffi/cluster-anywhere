#!/bin/bash
export HOME=/home/ray

if [ -z "$TSAPIKEY" ]; then
  echo "Environmental variable for TSAPIKEY not set"
  exit 1
fi

#echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
#echo "net.ipv6.conf.default.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
#echo "net.ipv6.conf.lo.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf
#echo "vm.max_map_count = 262144" | sudo tee -a /etc/sysctl.conf
#echo "vm.swappiness = 1" | sudo tee -a /etc/sysctl.conf



# Pull external IP
IPADDRESS=$(curl -s http://ifconfig.me/ip)
export IPADDRESS=$IPADDRESS


echo "export NUMEXPR_MAX_THREADS='$(nproc)'" | sudo tee -a ~/.bashrc
echo "export MAKEFLAGS='-j$(nproc)'" | sudo tee -a ~/.bashrc
echo "export CPU_COUNT='$(nproc)'" | sudo tee -a ~/.bashrc

memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Convert kB to GB
gb_memory=$(echo "scale=2; $memory / 1048576" | bc)
shm_memory=$(echo "scale=0; $gb_memory / 1" | bc)

#settings number of cpus for optimial (local) speed
export NUMEXPR_MAX_THREADS='$(nproc)'
#used by conda to specify cpus for building packages
export MAKEFLAGS='-j$(nproc)'
#used by conda
export CPU_COUNT='$(nproc)'

#CRATE_HEAP_SIZE=$(echo $shm_memory | awk '{print int($0+0.5)}')
export CRATE_HEAP_SIZE="${shm_memory}G"
export shm_memory="${shm_memory}G"

check_cloud_provider() {
  # Check AWS EC2
  if curl -s -m 5 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
    if [ $(curl -s -o /dev/null -w "%{http_code}" -m 5 http://169.254.169.254/latest/meta-data/) != "404" ]; then
      echo "Cloud Provider: Amazon Web Services (AWS)"
      location="AWS"
      export LOCATION=$location
      return
    fi
  fi

  # Check Google Cloud Platform (GCP)
  if curl -s -m 5 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/ >/dev/null 2>&1; then
    if [ $(curl -s -o /dev/null -w "%{http_code}" -m 5 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/) != "404" ]; then
      echo "Cloud Provider: Google Cloud Platform (GCP)"
      location="GCP"
      export LOCATION=$location
      return
    fi
  fi

  # Check Microsoft Azure
  if curl -s -m 5 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2021-02-01 >/dev/null 2>&1; then
    if [ $(curl -s -o /dev/null -w "%{http_code}" -m 5 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2021-02-01) != "404" ]; then
      echo "Cloud Provider: Microsoft Azure"
      location="Azure"
      export LOCATION=$location
      return
    fi
  fi

  # Check Oracle Cloud Infrastructure (OCI)
  if curl -s -m 5 http://169.254.169.254/opc/v1/ >/dev/null 2>&1; then
    if [ $(curl -s -o /dev/null -w "%{http_code}" -m 5 http://169.254.169.254/opc/v1/) != "404" ]; then
      echo "Cloud Provider: Oracle Cloud Infrastructure (OCI)"
      location="OCI"
      export LOCATION=$location
      return
    fi
  fi

  # Check RunPod
  if [ $RUNPOD_API_KEY ]; then
    echo "Cloud Provider: RunPod"
    location="RunPod"
    export LOCATION=$location
    return
  fi

  # Default fallback
  echo "Unable to determine the Cloud Provider. Either it's a new CSP or it's OnPrem"
  location="OnPrem"
  export LOCATION=$location
}



# Invoke the function
check_cloud_provider

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

#set -ae

## add in code to search and remove the machine name from tailscale if it already exists
#deviceid=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq '.devices[] | select(.hostname=="'$HOSTNAME'")' | jq -r .id)
#export deviceid=$deviceid

#echo "Deleting the device from Tailscale"
#curl -s -X DELETE https://api.tailscale.com/api/v2/device/$deviceid -u $TSAPIKEY: || echo "Error deleting $deviceid"




### getting a list of remaining devices
# Make the GET request to the Tailscale API to retrieve the list of all devices
# This could be updated to grab the DNS domain too to be more flexable.
# This is used for the parameter discovery.seed.hosts in crate.yml
function get_cluster_hosts() {
  #TSAPIKEY=$1

  clusterhosts=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Error: failed to fetch list of devices from Tailscale API"
    return 1
  fi

  clusterhosts=$(echo $clusterhosts | jq -r '.devices[].name')
  if [ $? -ne 0 ]; then
    echo "Error: failed to parse list of devices from Tailscale API response"
    clusterhosts="nexus:4300"
  fi


  # making it a comma-separated list
  clusterhosts="$(echo $clusterhosts | tr ' ' ',')"
  # removing AWS instances
  clusterhosts="$(echo $clusterhosts | sed 's/i-[^,]*,//g')"
  # strip domain names
  #clusterhosts="$(echo $clusterhosts | sed 's/.chimp-beta.ts.net/:4300/g')"

  echo $clusterhosts
}

export CLUSTERHOSTS="$(get_cluster_hosts)"
#export CLUSTERNODES="$(echo $CLUSTERHOSTS | sed 's/.chimp-beta.ts.net/:4300/g')"

if [ ! -c $TS_STATEDIR ] && echo $CLUSTERHOSTS | grep -q $HOSTNAME ; then
  deviceid=$(curl -s -u "${TSAPIKEY}:" https://api.tailscale.com/api/v2/tailnet/jcoffi.github/devices | jq '.devices[] | select(.hostname=="'$HOSTNAME'")' | jq -r .id)
  export deviceid=$deviceid

  echo "Deleting the device from Tailscale"
  curl -s -X DELETE https://api.tailscale.com/api/v2/device/$deviceid -u $TSAPIKEY: || echo "Error deleting $deviceid"
fi

# Make sure directories exist as they are not automatically created
# This needs to happen at runtime, as the directory could be mounted.
sudo mkdir -pv $CRATE_GC_LOG_DIR $CRATE_HEAP_DUMP_PATH $TS_STATEDIR
sudo chmod -R 7777 /data

if [ -c /dev/net/tun ]; then
    sudo tailscaled -port 41641 -statedir $TS_STATEDIR & #2>/dev/null&
    sudo tailscale up --auth-key=$TS_AUTHKEY --accept-risk=all --accept-routes
else
    echo "tun doesn't exist"
    sudo tailscaled -port 41641 -statedir $TS_STATEDIR -tun userspace-networking -state mem: -socks5-server=localhost:1055 -outbound-http-proxy-listen=localhost:1055 &
    export socks_proxy=socks5h://localhost:1055/
    export SOCKS_proxy=socks5h://localhost:1055/
    export ALL_PROXY=socks5h://localhost:1055/
    export http_proxy=http://localhost:1055/
    export HTTP_PROXY=http://localhost:1055/
    sudo tailscale up --auth-key=$TS_AUTHKEY --accept-risk=all --accept-routes
fi



# lcase_hostname=${HOSTNAME,,}.chimp-beta.ts.net
# #create cert

# if [ ! -f /data/certs/$lcase_hostname.key ]; then
#    cd /data/certs
#    echo "Creating certs"
#    sudo tailscale cert ${lcase_hostname} &
#    cd $HOME
# fi

# export KEYSTOREPASSWORD=$RANDOM$RANDOM
# #create p12
# if [ ! -f /crate/config/ssl_enabled ] && [ -f /data/certs/$lcase_hostname.key ]; then
#     echo "Generating p12"
#     sudo rm -rf /data/certs/keystore.p12
#     cd /data/certs
#     sudo openssl pkcs12 -export -name "$lcase_hostname" -in "$lcase_hostname.crt" -inkey "$lcase_hostname.key" -out keystore.p12 -passout pass:"$KEYSTOREPASSWORD"
#     cd $HOME
# fi
# #create jks
# if [ ! -f /crate/config/ssl_enabled ] && [ -f /data/certs/keystore.p12 ]; then
#     echo "Generating jks"
#     sudo rm -rf /data/certs/keystore.jks
#     sudo rm -rf /data/certs/truststore.jks
#     cd /data/certs
#     sudo -E /crate/jdk/bin/keytool -importkeystore -destkeystore /data/certs/keystore.jks -srckeystore /data/certs/keystore.p12 -srcstoretype pkcs12 -alias $lcase_hostname -srcstorepass $KEYSTOREPASSWORD -deststorepass $KEYSTOREPASSWORD
#     wget -nc https://letsencrypt.org/certs/lets-encrypt-r3.pem
#     sudo -E /crate/jdk/bin/keytool -importcert -alias letsencryptint -keystore /data/certs/truststore.jks -file /data/certs/lets-encrypt-r3.pem -trustcacerts -storepass $KEYSTOREPASSWORD
#     cd $HOME
# fi

# if [ ! -f /crate/config/ssl_enabled ] && [ -f /data/certs/keystore.jks ]; then
#     echo "ssl.keystore_filepath: /data/certs/keystore.jks" | sudo tee -a /crate/config/crate.yml \
#     && echo "ssl.keystore_password: $KEYSTOREPASSWORD" | sudo tee -a /crate/config/crate.yml \
#     && echo "ssl.truststore_filepath: /data/certs/truststore.jks" | sudo tee -a /crate/config/crate.yml \
#     && echo "ssl.truststore_password: $KEYSTOREPASSWORD" | sudo tee -a /crate/config/crate.yml \
#     && echo "ssl.transport.mode: on" | sudo tee -a /crate/config/crate.yml \
#     && sudo touch /crate/config/ssl_enabled \
#     && echo $KEYSTOREPASSWORD | sudo tee -a /crate/config/ssl_enabled
# fi

# sudo chmod 777 -R /data/certs

while [ ! $tailscale_status = "Running" ]
    do
        echo "Waiting for tailscale to start..."
        tailscale_status="$(tailscale status -json | jq -r .BackendState)"
done

#current_node_master=$(crash --hosts ${CLUSTERHOSTS} -c "SELECT n.hostname FROM sys.cluster c JOIN sys.nodes n ON c.master_node = n.id;" --format raw | jq -r '.rows[] | .[0]')
#export CURRENTNODEMASTER="$(crash --hosts ${CLUSTERHOSTS} -c "SELECT n.hostname FROM sys.cluster c JOIN sys.nodes n ON c.master_node = n.id;" --format raw | jq -r '.rows[] | .[0]')"

# check if we already have state data
if [ -d "$CRATE_HEAP_DUMP_PATH" ]; then

	if [ -d "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/" ] && [ "$(ls -A $CRATE_HEAP_DUMP_PATH/nodes/0/_state/)" ]; then
        echo "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/ is not Empty"
        crate_state_data=$true
	else
        echo "$CRATE_HEAP_DUMP_PATH/nodes/0/_state/ is Empty"
        crate_state_data=$false
	fi
else
	echo "Directory $CRATE_HEAP_DUMP_PATH not found."
    exit 1
fi


if [ ! "$LOCATION" = "OnPrem" ] && [ ! "$NODETYPE" = "head" ]; then
  node_master='-Cnode.master=false \\'
  node_data='-Cnode.data=false \\'
  node_voting_only='-Cnode.voting_only=false \\'
  discovery_zen_minimum_master_nodes='-Cdiscovery.zen.minimum_master_nodes=3'

fi

if [ "$NODETYPE" = "head" ]; then
  node_name='-Cnode.name=nexus \\'
  node_master='-Cnode.master=true \\'
  node_data='-Cnode.data=false \\'

  ray start --head --num-cpus=0 --num-gpus=0 --disable-usage-stats --include-dashboard=True --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net --node-name $HOSTNAME.chimp-beta.ts.net

  sudo tailscale serve https / http://localhost:8265 \
  && sudo tailscale funnel 443 on

elif [ "$NODETYPE" = "user" ]; then
  node_master='-Cnode.master=false \\'
  node_data='-Cnode.data=false \\'
  node_voting_only='-Cnode.voting_only=false \\'
  discovery_zen_minimum_master_nodes='-Cdiscovery.zen.minimum_master_nodes=3'

  ray start --address='nexus.chimp-beta.ts.net:6379' --num-cpus=1 --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net --node-name $HOSTNAME.chimp-beta.ts.net

  sudo chmod -R 777 /files
  conda install -c conda-forge -y jupyterlab nano && jupyter-lab --allow-root --ServerApp.token='' --ServerApp.password='' --notebook-dir /files --ip 0.0.0.0 --no-browser --preferred-dir /files &
  #pip install jupyter_ai
  #conda install -c conda-forge -y jupyterlab nano && jupyter-lab --allow-root --ServerApp.token='' --ServerApp.password='' --notebook-dir /files --ip 0.0.0.0 --no-browser --certfile=/data/certs/$HOSTNAME.chimp-beta.ts.net.crt --keyfile=/data/certs/$HOSTNAME.chimp-beta.ts.net.key --preferred-dir /files &

  #look into using /lab or /admin or whatever so that they can live on the same port (on the head node perhaps)
  #but we can't move it to the head node right now because the only other port is 10001 and that conflicts with ray
  sudo tailscale serve https:8443 / http://localhost:8888 \
  && sudo tailscale funnel 8443 on
  sudo tailscale serve https:443 / http://localhost:4200 \
  && sudo tailscale funnel 443 on
else

  ray start --address='nexus.chimp-beta.ts.net:6379' --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net --node-name $HOSTNAME.chimp-beta.ts.net

fi


# SIGTERM-handler this funciton will be executed when the container receives the SIGTERM signal (when stopping)
function term_handler(){
    crate_pid=$(pgrep -f crate)

    if [ $(tailscale status -json | jq -r .BackendState | grep -q "Running") ] && [ $crate_pid ]; then
        echo "Running Cluster Decommission"
        /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';" &
    fi

    if [ $(ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q "ALIVE") ]; then
        echo "***Stopping Ray***"
        ray stop -g 5
    fi

    if [ $(tailscale status -json | jq -r .BackendState | grep -q "Running") ]; then
        echo "tailscale logout"
        sudo tailscale logout
        sudo tailscale down
    fi

    if [ $crate_pid ]; then
        sudo kill -TERM $crate_pid
    fi
    exit 0
}

function error_handler(){
    echo "***Error***"
    echo "***Stopping Ray***"
    ray stop -g 5
    #echo "Running Cluster Election"
    #/usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "SET GLOBAL TRANSIENT 'cluster.routing.allocation.enable' = 'new_primaries';" &
    echo "Running Decommission"
    /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';" &

    echo "tailscale logout"
    sudo tailscale logout
    crate_pid=$(pgrep -f crate)
    sudo kill -TERM 1
    if [ $crate_pid ]; then
        sudo kill -TERM $crate_pid
    fi
    exit 1
}

# Setup signal handlers
trap 'term_handler' SIGTERM
trap 'term_handler' SIGKILL
trap 'term_handler' EXIT
trap 'error_handler' ERR
trap 'error_handler' SIGSEGV

/crate/bin/crate \
            ${cluster_initial_master_nodes}
            ${discovery_zen_minimum_master_nodes}
            ${discovery_seed_hosts}
            ${node_name}
            ${node_master}
            ${node_data}
            ${node_voting_only}
            ${node_store_allow_mmap}

#/usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "SET GLOBAL TRANSIENT 'cluster.routing.allocation.enable' = 'all';" &
#CREATE REPOSITORY s3backup TYPE s3
#[ WITH (parameter_name [= value], [, ...]) ]
#[ WITH (access_key = ${AWS_ACCESS_KEY_ID}, secret_key = ${AWS_SECRET_ACCESS_KEY}), endpoint = s3.${AWS_DEFAULT_REGION}.amazonaws.com, bucket = ${AWS_S3_BUCKET}, base_path=crate/ ]
#



#while true
#do
#  tail -f /dev/null & wait ${!}
#done