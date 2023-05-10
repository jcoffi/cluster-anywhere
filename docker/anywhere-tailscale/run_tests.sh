#test for tailscale up
tailscale status -json | jq -r .BackendState | grep -q "Running" || exit 1

#test for crate connectivity
crash -U crate -c "SELECT count(*) FROM sys.nodes" || exit 1


#ray status || exit 1
if [ "$NODETYPE" = "head" ]; then
        ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q ALIVE || ray start --head --num-cpus=0 --num-gpus=0 --disable-usage-stats --include-dashboard=True --dashboard-host 0.0.0.0 --node-ip-address nexus.chimp-beta.ts.net || exit 1
else
        ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q ALIVE || exit 1
fi


if [ "$LOCATION" = "AWS" ]; then
        metadata_url="http://169.254.169.254/latest/meta-data/spot/termination-time"
        if curl -sf $metadata_url; then
                /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';" &
                ray stop -g 60
                sudo tailscale logout
        fi
fi



exit 0