#! /bin/sh -x
curl https://get.docker.com | sudo sh
sleep 10
sudo touch ~/.sudo_as_admin_successful
sudo usermod -aG docker ubuntu || true
sudo docker pull jcoffi/cluster-anywhere:cpu
sudo docker pull containrrr/watchtower:latest
sudo docker run --name=watchtower --env=WATCHTOWER_CLEANUP=true --env=WATCHTOWER_INCLUDE_STOPPED=true --env=WATCHTOWER_REVIVE_STOPPED=true --env=WATCHTOWER_INCLUDE_RESTARTING=true --env=WATCHTOWER_POLL_INTERVAL=900 --env=WATCHTOWER_TIMEOUT=300 --env=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin --volume=/var/run/docker.sock:/var/run/docker.sock --workdir=/ --restart=unless-stopped --runtime=runc -d containrrr/watchtower:latest
sudo docker run -d --shm-size='6G' --ulimit memlock=-1 --name=$(hostname -s) -h $(hostname -s) -e TSKEY=tskey-auth-kTSQbo3CNTRL-bWzNQtfVbgfmqTbd9zc5mffSAWJoMLLTB -e TSAPIKEY=tskey-api-k3bg4C7CNTRL-2m9fj3TiCyXzMpubSfax5YVi8PZhyzsoa -e AWS_ACCESS_KEY_ID=AKIAWBFHWTXYZVSR4LXM -e AWS_SECRET_ACCESS_KEY=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 -p 41641:41641/udp --restart unless-stopped --cap-add=NET_ADMIN --cap-add=SYS_PTRACE --cap-add=SYS_ADMIN --device=/dev/net/tun jcoffi/cluster-anywhere:cpu
