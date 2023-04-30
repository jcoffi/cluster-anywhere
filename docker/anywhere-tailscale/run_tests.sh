#test for tailscale up
tailscale status -json | jq -r .BackendState | grep -q "Running" || exit 1

#test for crate connectivity
crash -U crate -c "SELECT * FROM sys.nodes" || exit 1


#ray status || exit 1
if [ ! "$NODETYPE" = "head" ]; then
        ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q ALIVE || ray start --head --num-cpus=0 --num-gpus=0 --disable-usage-stats --include-dashboard=True --dashboard-host 0.0.0.0 --node-ip-address nexus.chimp-beta.ts.net
else
        ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q ALIVE || ray start --address='nexus.chimp-beta.ts.net:6379' --disable-usage-stats --dashboard-host 0.0.0.0 --node-ip-address $HOSTNAME.chimp-beta.ts.net
fi
