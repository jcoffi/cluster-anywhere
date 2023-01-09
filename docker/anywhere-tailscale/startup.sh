#!/bin/bash

# Generate a random string
RANDOMSTRING=$(openssl rand -hex 16)

# Pull external IP
IPADDRESS=$(curl -s http://ifconfig.me/ip)
export IPADDRESS=$IPADDRESS

# Export the random string as an environment variable
export RANDOMSTRING=$RANDOMSTRING


# Create named pipes
edgepipe=/tmp/f$RANDOMSTRING
dhcppipe=/tmp/d$RANDOMSTRING
mkfifo $edgepipe
mkfifo $dhcppipe

set -ae

# GC logging set to default value of path.logs
CRATE_GC_LOG_DIR="/data/log"
CRATE_HEAP_DUMP_PATH="/data/data"
# Make sure directories exist as they are not automatically created
# This needs to happen at runtime, as the directory could be mounted.
mkdir -pv $CRATE_GC_LOG_DIR $CRATE_HEAP_DUMP_PATH

# Special VM options for Java in Docker
CRATE_JAVA_OPTS="-Des.cgroups.hierarchy.override=/ $CRATE_JAVA_OPTS"

sudo tailscaled &


# If NODETYPE is "head", run the supernode command and append some text to .bashrc
if [ "$NODETYPE" = "head" ]; then

sudo tailscale up --authkey=tskey-auth-kTSQbo3CNTRL-bWzNQtfVbgfmqTbd9zc5mffSAWJoMLLTB --accept-risk=all --hostname=nexus --accept-dns
nexus=$(tailscale ip nexus)
sudo echo -e "#/bin/sh\nsudo tailscale down\n" >> /etc/rc0.d/tailscaledown.sh
sudo chmod +x /etc/rc0.d/tailscaledown.sh
/crate/bin/crate -Cnetwork.host=_${N2N_INTERFACE}_ \
            -Cnode.name=nexus.chimp-beta.ts.net \
            -Cdiscovery.type=zen \
            -Ccluster.initial_master_nodes=nexus.chimp-beta.ts.net,$nexus \
            &

else

sudo tailscale up --authkey=tskey-auth-kTSQbo3CNTRL-bWzNQtfVbgfmqTbd9zc5mffSAWJoMLLTB --accept-risk=all --accept-routes --accept-dns
nexus=$(tailscale ip nexus)
sudo echo -e "#/bin/sh\nsudo tailscale down\n" >>  /etc/rc0.d/tailscaledown.sh
sudo chmod +x /etc/rc0.d/tailscaledown.sh
/crate/bin/crate -Cnetwork.host=_${N2N_INTERFACE}_ \
            #-Cnode.name=${DDNS_HOST} \
            -Cdiscovery.type=zen \
            -Cdiscovery.seed_hosts=nexus.chimp-beta.ts.net,$nexus \
            -Ccluster.initial_master_nodes=nexus.chimp-beta.ts.net,$nexus \
            &
fi






