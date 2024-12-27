#!/bin/bash

FAIL=0
#This needs to stay if we're to actually have a location to use since environmental variables are only passed from parent to child and this file isn't run from the startup shell
export $(grep "LOCATION=" /etc/environment)

# Check for AWS Spot Instance Termination
if [ "$LOCATION" = "AWS" ]; then
    metadata_url="http://169.254.169.254/latest/meta-data/spot/termination-time"
    if curl -s $metadata_url; then
        /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '$HOSTNAME';" &
        ray stop -g 30
        sudo tailscale logout
        sudo tailscale down
        sudo tailscaled -cleanup
    fi
fi

# Check for GCP Spot Instance Termination
if [ "$LOCATION" = "GCP" ]; then
   result=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/maintenance-event -H "Metadata-Flavor: Google")
   if [ "$result" != "NONE" ]; then
       /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '$HOSTNAME';" &
       ray stop -g 30
       sudo tailscale logout
       sudo tailscale down
       sudo tailscaled -cleanup
   fi
fi




# Check Tailscale
tailscale_status=$(tailscale status -json | jq -r .BackendState)
if [ "$tailscale_status" != "Running" ]; then FAIL=1; fi

# Check Ray status if not OnPrem node. Want to confine all non gpu processing to the cloud
if [ "$LOCATION" != "OnPrem" ]; then
    ray_status=$(ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep "ALIVE")
    if [ -z "$ray_status" ]; then FAIL=1; fi
fi

# Check Crate.io status
# if [ "$LOCATION" != "Vast" ]; then
#     crate_status=$(curl -s -I http://localhost:4200/ | grep HTTP/1.1)
#     if echo "$crate_status" | grep -qv "200 OK"; then FAIL=1; fi
# fi

# Write status to a file
# also write a bit of additional information for diagnostic purposes.
if [ $FAIL -eq 1 ]; then
    echo "unhealthy" | sudo tee /tmp/health_status.html
    echo "Location: $LOCATION" | sudo tee -a /tmp/health_status.html

    if [ $tailscale_status ]; then
        echo "Tailscale: $tailscale_status" | sudo tee -a /tmp/health_status.html
    fi

    if [ $ray_status ]; then
        echo "Ray: $ray_status" | sudo tee -a /tmp/health_status.html
    fi

    if [ $crate_status ]; then
        echo "Crate: $crate_status" | sudo tee -a /tmp/health_status.html
    fi
    #so we can see what happened if the problem resolved itself
    sudo cp /tmp/health_status.html /tmp/health_status_last_unhealthy.html

    exit 1
else
    exit 0
fi