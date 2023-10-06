#!/bin/bash

FAIL=0

# Check for AWS Spot Instance Termination
if [ "$LOCATION" = "AWS" ]; then
    metadata_url="http://169.254.169.254/latest/meta-data/spot/termination-time"
    if curl -s $metadata_url; then
        /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '$HOSTNAME';" &
        ray stop -g 30
        sudo tailscale logout
        sudo tailscale down
        sudo tailscaled -cleanup
        exit 0
    fi
fi

# Check for GCP Spot Instance Termination
#if [ "$LOCATION" = "GCP" ]; then
#    result=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/maintenance-event -H "Metadata-Flavor: Google")
#    if [ "$result" != "NONE" ]; then
#        /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '$HOSTNAME';" &
#        ray stop -g 30
#        sudo tailscale logout
#        sudo tailscale down
#        sudo tailscaled -cleanup
#        exit 0
#    fi
#fi




# Check Tailscale
tailscale_status=$(tailscale status -json | jq -r .BackendState)
if [ "$tailscale_status" != "Running" ]; then FAIL=1; fi


# Check Ray status if not user node. Want to confine all non gpu processing to the cloud
if [ "$LOCATION" != "OnPrem" ]; then
    ray_status=$(ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q "ALIVE")
    if [ -z "$ray_status" ]; then FAIL=1; fi
fi


# Check Crate.io status (Added this part)
crate_status=$(curl -s http://localhost:4200/ | grep -q "CrateDB Admin UI")
if [ -z "$crate_status" ]; then FAIL=1; fi

# Other test commands here

if [ $FAIL -eq 1 ]; then
    echo "Tests failed."
    exit 1
fi
