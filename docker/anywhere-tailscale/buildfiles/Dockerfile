ARG IMAGETYPE=cpu
FROM rayproject/ray:2.2.0-py39-$IMAGETYPE
ENV __MODIN_AUTOIMPORT_PANDAS__=1 \
        MODIN_ENGINE=ray \
        MODIN_RAY_CLUSTER=True \
        RAY_IGNORE_UNHANDLED_ERRORS=1 \
        RAY_ADDRESS="nexus.chimp-beta.ts.net:6379" \
        RAY_CLIENT_RECONNECT_GRACE_PERIOD=60 \
        RAY_memory_monitor_refresh_ms=0 \
        RAY_record_ref_creation_sites=1 \
        TZ=America/Los_Angeles \
        NODETYPE=edge \
        AWS_DEFAULT_REGION="us-west-2" \
        AWS_S3_BUCKET="cluster-anywhere" \
        CRATE_GC_LOG_DIR="/data/crate/log" \
        CRATE_HEAP_DUMP_PATH="/data/crate/data" \
        CRATE_JAVA_OPTS="-XX:+IgnoreUnrecognizedVMOptions -XX:+UseContainerSupport -XX:+IdleTuningCompactOnIdle -XX:+IdleTuningGcOnIdle -Des.cgroups.hierarchy.override=/ $CRATE_JAVA_OPTS" \
        PATH=/crate/bin/:$PATH \
        CRATE_HEAP_SIZE="5G" \
        CRATE_HOME=/crate/bin/ \
        CRATE_USE_IPV4=true \
        SQLALCHEMY_SILENCE_UBER_WARNING=1 \
        HOME=/home/ray \
        TS_STATEDIR="/data/tailscale" \
        TS_STATE="$TS_STATEDIR/tailscale.state"
ARG TSKEY
ARG TSAPIKEY
ARG OPENAPI_KEY
#        TSAPIKEY="" \
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
#        IPv6=false \
#        DISABLE_IPV6=true \

#SHELL ["/bin/bash", "-o", "pipefail", "-c"]
#RUN sudo ulimit -n 65535


#we'll make the cluster name the github commit id, this way every new image is a new cluster but we keep state

RUN sudo apt update \
&& sudo apt install -y --no-install-recommends ca-certificates curl bc jq lsb-release \
&& curl -fsSLZ https://pkgs.tailscale.com/stable/ubuntu/focal.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
&& curl -fsSLZ https://pkgs.tailscale.com/stable/ubuntu/focal.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list \
&& sudo apt update \
&& sudo apt install -y --no-install-recommends iptables nftables tailscale iproute2 procps inotify-tools \
&& sudo mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale \
&& sudo apt clean \
&& sudo rm -rf /var/lib/apt/lists/* \
&& sudo groupadd crate \
        && export PLATFORM="$( case $(uname --m) in x86_64) echo x64_linux ;; aarch64) echo aarch64_linux ;; esac)" \
        && CRATE_LATEST_TAG=$(curl -s https://api.github.com/repos/crate/crate/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v') \
        && CRASH_LATEST_TAG=$(curl -s https://api.github.com/repos/crate/crash/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v') \
        && sudo mkdir -p /crate \
        && sudo adduser ray crate \
        && sudo chown -R ray /crate \
        && sudo chgrp -R crate /crate \
        && export CRATE_URL=https://cdn.crate.io/downloads/releases/cratedb/${PLATFORM}/crate-${CRATE_LATEST_TAG}.tar.gz \
        && curl -fsSLZ -O ${CRATE_URL} \
        && curl -fsSLZ -O "https://raw.githubusercontent.com/jcoffi/docker-crate/master/config/crate.yml" \
        && curl -fsSLZ -O "https://raw.githubusercontent.com/jcoffi/docker-crate/master/config/log4j2.properties" \
        && sudo tar -xf crate-${CRATE_LATEST_TAG}.tar.gz -C /crate --strip-components=1 \
        && sudo chown 1000 crate.yml \
        && sudo mv crate.yml /crate/config/crate.yml \
        && sudo chown 1000 log4j2.properties \
        && sudo mv log4j2.properties /crate/config/log4j2.properties \
        && rm crate-${CRATE_LATEST_TAG}.tar.gz \
        && curl -fsSLZ -O https://cdn.crate.io/downloads/releases/crash_standalone_${CRASH_LATEST_TAG} \
        && sudo mv crash_standalone_${CRASH_LATEST_TAG} /usr/local/bin/crash \
        && sudo chmod +x /usr/local/bin/crash \
&& curl -fsSLZ -O "https://raw.githubusercontent.com/jcoffi/ray/cluster-anywhere/docker/anywhere-tailscale/startup.sh" \
&& sudo chmod +x /home/ray/startup.sh \
&& curl -fsSLZ -O "https://raw.githubusercontent.com/jcoffi/ray/cluster-anywhere/docker/anywhere-tailscale/run_tests.sh" \
&& sudo chmod +x /home/ray/run_tests.sh \
&& $HOME/anaconda3/bin/pip install -q --no-cache-dir -U pip \
    pandas \
    pandas_market_calendars \
    modin[ray] \
    'sqlalchemy<2.0' \
    crate[sqlalchemy] \
    'distributed==2022.2.0' \
    'ray==2.2' \
    scikit-learn-intelex \
    torch \
    fredapi \
    sympy \
    numba \
    numpy \
    datetime \
    icecream \
    geojson \
    tsfresh \
    alpaca_py \
    tiingo \
    yfinance \
    openai

##building juicefs
#RUN JFS_LATEST_TAG=$(curl -s https://api.github.com/repos/juicedata/juicefs/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | tr -d 'v') && \
#  wget "https://github.com/juicedata/juicefs/releases/download/v${JFS_LATEST_TAG}/juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz" && \
#  tar -zxf "juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz" && \
#  sudo install juicefs /usr/bin && \
#  rm juicefs "juicefs-${JFS_LATEST_TAG}-linux-amd64.tar.gz"

#for direct connections from tailscale
EXPOSE 41641/udp
EXPOSE 41641/tcp

VOLUME /data
RUN sudo mkdir -p $CRATE_HEAP_DUMP_PATH $CRATE_GC_LOG_DIR $TS_STATEDIR

ENTRYPOINT ["/bin/bash", "/home/ray/startup.sh"]
## Either the interval or the retries needs to be longer so that crate has time to find the cluster
#HEALTHCHECK --interval=300s --timeout=30s --start-period=300s --retries=3 \
HEALTHCHECK --interval=60s --timeout=30s --start-period=300s --retries=1 \
CMD sh /home/ray/run_tests.sh