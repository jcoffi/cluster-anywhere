#!/bin/bash

# Check if the DOCKER_PASSWORD environment variable is set
if [ -z "$DOCKER_PASSWORD" ]; then
  echo "Environment variable for DOCKER_PASSWORD not set"
  exit 1
fi

# Variables
builddir="/home/tripps/build"
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
distro=${distribution//\./}

# Functions
disable_nouveau() {
  # Create a new configuration file for the kernel modules
  echo "Creating configuration file to disable Nouveau drivers..."
  echo "blacklist nouveau" | sudo tee /etc/modprobe.d/disable-nouveau.conf > /dev/null
  echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/disable-nouveau.conf > /dev/null

  # Regenerate the initial RAM disk (initramfs) to apply the changes
  echo "Regenerating initramfs..."
  sudo update-initramfs -u

  # Prompt user to reboot
  echo "Please reboot your system to apply the changes:"
  echo "sudo reboot"
}

prepare_build_directory() {
  if [ -d "$builddir/" ]; then
    cd "$builddir/"
    sudo rm -rf *
  else
    sudo mkdir -p "$builddir" /home/$USER/data && cd "$builddir"
  fi
}

setup_docker_or_podman() {
  if [ -x /usr/bin/podman ]; then
    DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
    export DOCKER_HOST
    exec=/usr/bin/podman
    sudo podman registry remove quay.io
    podman login --username jcoffi --password "$DOCKER_PASSWORD"
    alias docker=podman
  elif [ -x /usr/bin/docker ]; then
    exec=/usr/bin/docker
    docker login --username jcoffi --password "$DOCKER_PASSWORD"
  fi
}

configure_sysctl() {
  sudo sysctl -w vm.max_map_count=262144
  #sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
  #sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
  #sudo sysctl -w net.ipv6.conf.lo.disable_ipv6=1
  sudo sysctl -p

  echo -e "vm.max_map_count = 262144\n" | sudo tee /etc/sysctl.conf
  #echo -e "net.ipv6.conf.all.disable_ipv6=1\n" | sudo tee /etc/sysctl.conf
  #echo -e "net.ipv6.conf.default.disable_ipv6=1\n" | sudo tee /etc/sysctl.conf
  #echo -e "net.ipv6.conf.lo.disable_ipv6=1\n" | sudo tee /etc/sysctl.conf
}

disable_sleep_for_laptops() {
  if [ -d /sys/class/power_supply/BAT0 ]; then
    echo "Script is running on a laptop"
    #disable sleep on laptops
    sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  fi
}

install_docker_on_wsl() {
  if ! [ -x "$(command -v docker)" ] && ! [ -z "$WSL_DISTRO_NAME" ] && ! [ -x /usr/bin/podman ]; then
    sudo curl https://get.docker.com | sh
    sudo adduser ubuntu docker
  fi
}

remove_registry_and_install_dependencies() {
  if [ -x /usr/bin/podman ]; then

    sudo podman registry remove quay.io
  fi

  sudo apt install --no-install-recommends -y jq wget && sudo apt -y autoremove
}

handle_nvidia_gpu() {
  # Check if the GPU is NVIDIA
  sudo apt install jq -y
  if [ -n "$(lspci | grep -i nvidia)" ] || [ -n "$(nvidia-smi -L)" ]; then
    if [ -x "$(command -v nvidia-smi)" ] && [ -d /usr/local/cuda ]; then
      CUDA="Already done"
      # Get the driver version
      nvidia_driver_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)
    elif [ -n "$WSL_DISTRO_NAME" ]; then
      install_nvidia_cuda "wsl-ubuntu"
      CUDA="WSL"
    elif [ -n "$(lspci | grep -i nvidia)" ]; then
      install_nvidia_cuda "$distro"
      CUDA="lspci"
    fi

    if [[ -n $CUDA ]] && [ -f /usr/local/cuda/version.json ]; then
      # Get the CUDA version
      cuda_version=$(cat /usr/local/cuda/version.json | jq -r '.cuda.version')

      # Strip out the decimal point
      cuda_version=${cuda_version//\./}
      #i dont have time to figure this out right now
      echo $cuda_version
      if [ $cuda_version == "1200" ]; then
        cuda_version="116"
      fi
    elif [[ -n $CUDA ]] && ! [ -f /usr/local/cuda/version.json ]; then
      #we will default to 11.8
      cuda_version="gpu"
    fi
  fi
}

install_nvidia_cuda() {
  local repo="$1"
  if ! [ -x "$(command -v gcc)" ]; then
    sudo apt -y install gcc make
  fi
  #curl -O https://developer.download.nvidia.com/compute/cuda/11.2.2/local_installers/cuda_11.2.2_460.32.03_linux.run | sudo sh &1 --silent --driver --toolkit --no-drm --no-man-page
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A4B469963BF863CC
  wget https://developer.download.nvidia.com/compute/cuda/repos/$repo/$(uname --m)/cuda-keyring_1.0-1_all.deb -O cuda-keyring_1.0-1_all.deb && sudo chmod +x cuda-keyring_1.0-1_all.deb
  sudo dpkg -i cuda-keyring_1.0-1_all.deb
  sudo apt-get update
  sudo apt-get -y install cuda
}

download_docker_files() {
  wget https://raw.githubusercontent.com/jcoffi/cluster-anywhere/master/docker/anywhere-tailscale/Dockerfile -O Dockerfile
  wget https://raw.githubusercontent.com/jcoffi/cluster-anywhere/master/docker/anywhere-tailscale/startup.sh -O "$builddir/startup.sh"
  sudo chmod 777 Dockerfile
  sudo chmod 777 "$builddir/startup.sh"
}

build_and_push_docker_image() {
  if [[ -n $cuda_version ]] && [ $cuda_version != "gpu" ]; then
    sudo $exec build --cache-from=index.docker.io/rayproject/ray-ml:2.2.0-py38-cu$cuda_version $builddir -t docker.io/jcoffi/cluster-anywhere:cu$cuda_version --build-arg IMAGETYPE=cu$cuda_version
    sudo $exec push  docker.io/jcoffi/cluster-anywhere:cu$cuda_version
  elif [[ -n $cuda_version ]] && [ $cuda_version == "gpu" ]; then
    sudo $exec build --cache-from=index.docker.io/rayproject/ray-ml:2.2.0
    sudo $exec build --cache-from=index.docker.io/rayproject/ray-ml:2.2.0-py38-gpu $builddir -t docker.io/jcoffi/cluster-anywhere:gpu -t docker.io/jcoffi/cluster-anywhere:gpu-latest --build-arg IMAGETYPE=gpu
    sudo $exec push docker.io/jcoffi/cluster-anywhere:gpu
  else
    sudo $exec build --cache-from=index.docker.io/rayproject/ray:2.2.0-py38-cpu $builddir -t docker.io/jcoffi/cluster-anywhere:cpu -t docker.io/jcoffi/cluster-anywhere:latest -t docker.io/jcoffi/cluster-anywhere:cpu-latest --build-arg IMAGETYPE=cpu
    sudo $exec push docker.io/jcoffi/cluster-anywhere:$cuda_version
  fi

  if [ -f /root/.docker/config.json ]; then
    sudo rm /root/.docker/config.json
  fi
}

check_environment_variable
prepare_builddir
check_installed_executables
configure_system_settings
install_dependencies
handle_nvidia_gpu
#download_docker_files
#build_and_push_docker_image
