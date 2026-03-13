#!/bin/bash

set -euo pipefail

#make apt to don't ask questions
export DEBIAN_FRONTEND=noninteractive

#############################################################################
# Versions
#############################################################################
PYVER="3.12"

NVIDIA_DRIVER="590"
CUDA_VERSION="13"
CUDA_VERSION_DOT="13.0"
CUDA_VERSION_DASH="13-0"
CUDNN_MAJOR="9"
CPU_ARCH=$(uname -m)

PYTORCH_VERSION="2.10.0"
PYTORCH_CUDA_VERSION="${CUDA_VERSION_DOT/./}"   # 129
TORCHVISION_VERSION="0.25.0"
TORCHAUDIO_VERSION="2.10.0"

VIMVER="v9.1.1997"
VLLM_VERSION="0.17.1"

#For A100
export TORCH_CUDA_ARCH_LIST="8.0"

export CMAKE_CUDA_ARCHITECTURES="70;80"
export MAKEFLAGS="-j$(nproc)"
export MAX_JOBS="$(nproc)"

USER_HOME="$(eval echo "~$SUDO_USER")"

VENV_PATH="$USER_HOME/venvs"
echo "venv path:$VENV_PATH"
mkdir -p $VENV_PATH

#############################################################################
# Base packages
#############################################################################
apt update

apt install -y --no-install-recommends \
  jq \
  ninja-build \
  ffmpeg \
  graphviz \
  vim pandoc 

#############################################################################
# Python 3.12 
#############################################################################
apt install python3.12-venv
#############################################################################
# OpenMPI
#############################################################################
apt install -y --no-install-recommends \
  openmpi-bin libopenmpi-dev \

#############################################################################
# CUDA + driver + cuDNN + NCCL (Ubuntu/NVIDIA repo)
# NOTE: If this VM has no GPU, you should skip this entire section.
#############################################################################
#install_cuda_stack() {
#  local distro="ubuntu2404"
#  local keypkg="cuda-keyring_1.1-1_all.deb"
#
#  wget -q "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/${CPU_ARCH}/${keypkg}" -O "/tmp/${keypkg}"
#  dpkg -i "/tmp/${keypkg}"
#  rm -f "/tmp/${keypkg}"  local distro="ubuntu2404"
#  local keypkg="cuda-keyring_1.1-1_all.deb"
#
#  wget -q "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/${keypkg}" -O "/tmp/${keypkg}"
#  dpkg -i "/tmp/${keypkg}"
#  rm -f "/tmp/${keypkg}"
#
#  apt-get update
#
#  # Driver
#  apt-get install -y --no-install-recommends "nvidia-driver-${NVIDIA_DRIVER}" || true
#
#  # Toolkit
#  apt-get install -y --no-install-recommends "cuda-toolkit-${CUDA_VERSION_DASH}"
#
#  # cuDNN (repo naming on Ubuntu typically: libcudnn9-cuda-13 / libcudnn9-dev-cuda-13)
#  apt-get install -y --no-install-recommends \
#    "libcudnn${CUDNN_MAJOR}-cuda-13" "libcudnn${CUDNN_MAJOR}-dev-cuda-13"
#
#  # NCCL
#  apt-get install -y --no-install-recommends libnccl2 libnccl-dev
#
#  # CUDA env
#  cat >/etc/profile.d/cuda.sh <<'EOF'
#export PATH=/usr/local/cuda/bin:$PATH
#export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
#EOF
#}
#install_cuda_stack
#exit(0)
#############################################################################
# PyTorch + requirements
#############################################################################
if [[ ! -f ../data/requirements.txt ]]; then
  echo "ERROR: ../data/requirements.txt missing. Copy your requirements.txt to ../data/requirements.txt"
  exit 1
fi
python3 -m venv "$VENV_PATH/pytorch"
echo "venv created to $VENV_PATH/pytorch"    
source "$VENV_PATH/pytorch/bin/activate"
echo "venv actived"    
python -m pip install --upgrade pip wheel setuptools
python -m pip install \
  "torch==${PYTORCH_VERSION}" \
  "torchvision==${TORCHVISION_VERSION}" \
  "torchaudio==${TORCHAUDIO_VERSION}" \
  --extra-index-url "https://download.pytorch.org/whl/cu${PYTORCH_CUDA_VERSION}" \
  -r ../data/requirements.txt
exit 0
#############################################################################
# Jupyter
#############################################################################
python -m pip install jupyterlab-dash
/usr/local/bin/jupyter lab build || true

#############################################################################
# Flash attention
#############################################################################
MAX_JOBS=4 python -m pip install flash-attn --no-build-isolation -v --no-cache-dir


#############################################################################
# Vim with python support
#############################################################################
apt-get install -y --no-install-recommends \
  autoconf automake libtool \
  libncurses5-dev libgtk-3-dev \
  libx11-dev libxpm-dev libxt-dev


#############################################################################
# vLLM
#############################################################################
cd /opt
git clone https://github.com/vllm-project/vllm.git -b "v${VLLM_VERSION}"
cd vllm
python use_existing_torch.py
python -m pip install -r requirements/build.txt
python -m pip install --no-build-isolation --verbose .
cd /opt
rm -rf vllm




#############################################################################
# Cleanup
#############################################################################
apt clean
