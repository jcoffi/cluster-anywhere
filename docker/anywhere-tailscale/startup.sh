#!/bin/bash

# Generate a random string
RANDOMSTRING=$(openssl rand -hex 16)

# Pull external IP
IPADDRESS=$(curl -s http://ifconfig.me/ip)
export IPADDRESS=$IPADDRESS

# Export the random string as an environment variable
export RANDOMSTRING=$RANDOMSTRING

set -ae

# GC logging set to default value of path.logs
CRATE_GC_LOG_DIR="/data/log"
CRATE_HEAP_DUMP_PATH="/data/data"
# Make sure directories exist as they are not automatically created
# This needs to happen at runtime, as the directory could be mounted.
mkdir -pv $CRATE_GC_LOG_DIR $CRATE_HEAP_DUMP_PATH

# Special VM options for Java in Docker
CRATE_JAVA_OPTS="-Des.cgroups.hierarchy.override=/ $CRATE_JAVA_OPTS"


sudo tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &


# If NODETYPE is "head", run the supernode command and append some text to .bashrc
if [ "$NODETYPE" = "head" ]; then

    sudo tailscale up --authkey=${TSKEY} --accept-risk=all --accept-routes --hostname=nexus --accept-dns

    while [ not $status = "Running" ]
    do 
        status="$(tailscale status -json | jq -r .BackendState)"
    done


/crate/bin/crate -Cnetwork.host=_${N2N_INTERFACE}_ \
            -Cnode.name=nexus \
            -Cnode.master=true \
            -Cnode.data=true \
            -Cnode.store.allow_mmap=false \
            -Cdiscovery.seed_hosts=nexus:4300 \
            -Ccluster.initial_master_nodes=nexus \
            -Ccluster.graceful_stop.min_availability=primaries \
            -Cstats.enabled=false
            

else

    sudo tailscale up --authkey=${TSKEY} --accept-risk=all --accept-routes --accept-dns

    while [ not $status = "Running" ]
    do 
        status="$(tailscale status -json | jq -r .BackendState)"
    done

/crate/bin/crate -Cnetwork.host=_${N2N_INTERFACE}_ \
            -Cnode.data=true \
            -Cnode.store.allow_mmap=false \
            -Cdiscovery.seed_hosts=nexus:4300 \
            -Ccluster.initial_master_nodes=nexus \
            -Ccluster.graceful_stop.min_availability=primaries \
            -Cstats.enabled=false
            
fi


#CREATE REPOSITORY s3backup TYPE s3
#[ WITH (parameter_name [= value], [, ...]) ]
#[ WITH (access_key = ${AWS_ACCESS_KEY_ID}, secret_key = ${AWS_SECRET_ACCESS_KEY}), endpoint = s3.${AWS_DEFAULT_REGION}.amazonaws.com, bucket = ${AWS_S3_BUCKET}, base_path=crate/ ]
#

# If NODETYPE is "head", used to free up the nexus name
if [ "$NODETYPE" = "head" ]; then

sudo tailscale --authkey=${TSKEY} set --hostname=nexus-old


fi

sudo tailscale down