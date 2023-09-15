if [ "$LOCATION" = "AWS" ]; then
        metadata_url="http://169.254.169.254/latest/meta-data/spot/termination-time"
        if curl $metadata_url; then
                /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';" &
                ray stop -f
                sudo tailscale logout

        fi
fi

FAIL=0


tailscale status -json | jq -r .BackendState | grep -q "Running" || FAIL=1


ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q "ALIVE" || FAIL=1


curl -s -X POST "http://localhost:4200/_sql?pretty" -H 'Content-Type: application/json' -d'
{
    "stmt": "select * from sys.nodes where name = '"'$HOSTNAME'"'"
}
' | jq -e '.rows | length > 0' || FAIL=1



#i'm in a hurry. but these if statements could use the lines above as boolen responses like crate_pid

if [ "$FAIL" = "1" ] && [ ! "$NODETYPE" = "user" ]; then
    echo "Failed and restarting"
    crate_pid=$(pgrep -f crate)
    if [ $crate_pid ]; then
        sudo kill -TERM $crate_pid
    fi
    sudo kill -TERM 1

fi
