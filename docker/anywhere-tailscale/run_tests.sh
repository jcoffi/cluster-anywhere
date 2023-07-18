if [ "$LOCATION" = "AWS" ]; then
        metadata_url="http://169.254.169.254/latest/meta-data/spot/termination-time"
        if curl -sf $metadata_url; then
                /usr/local/bin/crash --hosts ${CLUSTERHOSTS} -c "ALTER CLUSTER DECOMMISSION '"$HOSTNAME"';" &
                ray stop -f
                sudo tailscale logout

        fi
fi

tailscale status -json | jq -r .BackendState | grep -q "Running" || exit 1
ray list nodes -f NODE_NAME="${HOSTNAME}.chimp-beta.ts.net" -f STATE=ALIVE | grep -q "ALIVE" || exit 1
curl -s -X POST "http://localhost:4200/_sql?pretty" -H 'Content-Type: application/json' -d'
{
    "stmt": "select * from sys.nodes where name = '"'$HOSTNAME'"'"
}
' | jq -e '.rows | length > 0' || exit 1


exit 0
