#test for tailscale up
tailscale status -json | jq -r .BackendState | grep -q "Running" || exit 1

#test for crate connectivity
crash -U crate -c "SELECT * FROM sys.nodes" || exit 1


#ray status || exit 1
ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q ALIVE || exit 1


exit 0