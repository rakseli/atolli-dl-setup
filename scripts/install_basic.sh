#!/bin/bash
set -euo pipefail

#make apt to don't ask questions
export DEBIAN_FRONTEND=noninteractive
USER_HOME="$(eval echo "~$SUDO_USER")"
export HOME=$USER_HOME
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

VLLM_VERSION="0.17.1"

#For A100
export TORCH_CUDA_ARCH_LIST="8.0"

export CMAKE_CUDA_ARCHITECTURES="70;80"
export MAKEFLAGS="-j$(nproc)"
export MAX_JOBS="$(nproc)"

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
# uv
#############################################################################
curl -LsSf https://astral.sh/uv/install.sh | sh
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
install_cuda_stack() {
  local distro="ubuntu2404"
  local keypkg="cuda-keyring_1.1-1_all.deb"

  wget -q "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/${CPU_ARCH}/${keypkg}" -O "/tmp/${keypkg}"
  dpkg -i "/tmp/${keypkg}"
  rm -f "/tmp/${keypkg}"  local distro="ubuntu2404"
  local keypkg="cuda-keyring_1.1-1_all.deb"

  wget -q "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/${CPU_ARCH}/${keypkg}" -O "/tmp/${keypkg}"
  dpkg -i "/tmp/${keypkg}"
  rm -f "/tmp/${keypkg}"

  apt update

  # Toolkit
  apt install -y --no-install-recommends "cuda-toolkit-${CUDA_VERSION_DASH}"

  # cuDNN (repo naming on Ubuntu typically: libcudnn9-cuda-13 / libcudnn9-dev-cuda-13)
  apt install -y --no-install-recommends \
    "libcudnn${CUDNN_MAJOR}-cuda-13" "libcudnn${CUDNN_MAJOR}-dev-cuda-13"

  # NCCL
  apt install -y --no-install-recommends libnccl2 libnccl-dev

  # CUDA env
  cat >/etc/profile.d/cuda.sh <<'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
EOF
}

install_cuda_stack

exit 0
