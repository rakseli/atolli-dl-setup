#!/bin/bash

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

#############################################################################
# Versions (from your recipe)
#############################################################################
PYVER="3.12"

NVIDIA_DRIVER="575"
CUDA_VERSION_DOT="12.9"
CUDA_VERSION_DASH="12-9"
CUDNN_MAJOR="9"

PYTORCH_VERSION="2.9.1"
PYTORCH_CUDA_VERSION="${CUDA_VERSION_DOT/./}"   # 129
TORCHVISION_VERSION="0.24.1"
TORCHAUDIO_VERSION="2.9.1"

VIMVER="v9.1.1997"
OPENCV_VER="4.12.0"
VLLM_VERSION="0.13.0"
FAISS_VERSION="1.13.1"

export TORCH_CUDA_ARCH_LIST="7.0;8.0"
export CMAKE_CUDA_ARCHITECTURES="70;80"
export MAKEFLAGS="-j$(nproc)"
export MAX_JOBS="$(nproc)"

#############################################################################
# Base packages
#############################################################################
apt-get update
apt-get -y upgrade

apt-get install -y --no-install-recommends \
  ca-certificates curl wget git unzip zip \
  build-essential pkg-config ninja-build cmake \
  gnupg lsb-release \
  ffmpeg \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncurses-dev libffi-dev libxml2-dev libxslt1-dev \
  libsndfile1 \
  libnuma-dev numactl \
  graphviz \
  swig \
  libgflags-dev \
  libaio-dev

#############################################################################
# Python 3.12 (native on Ubuntu 24.04) + pip
#############################################################################
apt-get install -y --no-install-recommends \
  "python${PYVER}" "python${PYVER}-dev" "python${PYVER}-venv"

# Make python/pip default-ish (similar intent as alternatives in Rocky)
apt-get install -y --no-install-recommends python3-pip
update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYVER} 2
update-alternatives --install /usr/bin/python  python  /usr/bin/python${PYVER} 2

python -m pip install --upgrade pip wheel setuptools

# Ensure /usr/local paths are visible even in constrained envs
PY_SITE="/usr/lib/python${PYVER}/site-packages"
mkdir -p "$PY_SITE"
cat > "${PY_SITE}/usr-local.pth" <<EOF
/usr/local/lib/python${PYVER}/dist-packages
/usr/local/lib/python${PYVER}/site-packages
/usr/local/lib64/python${PYVER}/site-packages
EOF

#############################################################################
# Node.js 24
#############################################################################
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y --no-install-recommends nodejs

#############################################################################
# OpenMPI + UCX (sufficient)
#############################################################################
apt-get install -y --no-install-recommends \
  openmpi-bin libopenmpi-dev \
  ucx-utils libucx-dev

#############################################################################
# CUDA + driver + cuDNN + NCCL (Ubuntu/NVIDIA repo)
# NOTE: If this VM has no GPU, you should skip this entire section.
#############################################################################
install_cuda_stack() {
  local distro="ubuntu2404"
  local keypkg="cuda-keyring_1.1-1_all.deb"

  wget -q "https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/${keypkg}" -O "/tmp/${keypkg}"
  dpkg -i "/tmp/${keypkg}"
  rm -f "/tmp/${keypkg}"

  apt-get update

  # Driver
  apt-get install -y --no-install-recommends "nvidia-driver-${NVIDIA_DRIVER}" || true

  # Toolkit
  apt-get install -y --no-install-recommends "cuda-toolkit-${CUDA_VERSION_DASH}"

  # cuDNN (repo naming on Ubuntu typically: libcudnn9-cuda-12 / libcudnn9-dev-cuda-12)
  apt-get install -y --no-install-recommends \
    "libcudnn${CUDNN_MAJOR}-cuda-12" "libcudnn${CUDNN_MAJOR}-dev-cuda-12"

  # NCCL
  apt-get install -y --no-install-recommends libnccl2 libnccl-dev

  # CUDA env
  cat >/etc/profile.d/cuda.sh <<'EOF'
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}
EOF
}
install_cuda_stack

#############################################################################
# PyTorch + requirements
#############################################################################
if [[ ! -f /opt/requirements.txt ]]; then
  echo "ERROR: /opt/requirements.txt missing. Copy your requirements_pytorch_2.9.txt to /opt/requirements.txt"
  exit 1
fi

python -m pip install \
  "torch==${PYTORCH_VERSION}" \
  "torchvision==${TORCHVISION_VERSION}" \
  "torchaudio==${TORCHAUDIO_VERSION}" \
  --extra-index-url "https://download.pytorch.org/whl/cu${PYTORCH_CUDA_VERSION}" \
  -r /opt/requirements.txt

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
# PyTorch Geometric and related
#############################################################################
PIP_COMPILE_FLAGS="--verbose --no-build-isolation --no-cache-dir"
python -m pip install "git+https://github.com/pyg-team/pyg-lib.git" $PIP_COMPILE_FLAGS
python -m pip install $PIP_COMPILE_FLAGS torch_scatter
python -m pip install $PIP_COMPILE_FLAGS torch_sparse
python -m pip install $PIP_COMPILE_FLAGS torch_cluster
python -m pip install $PIP_COMPILE_FLAGS torch_spline_conv

#############################################################################
# Vim with python support
#############################################################################
apt-get install -y --no-install-recommends \
  autoconf automake libtool \
  libncurses5-dev libgtk-3-dev \
  libx11-dev libxpm-dev libxt-dev

cd /opt
wget -q "https://github.com/vim/vim/archive/refs/tags/${VIMVER}.tar.gz"
tar xf "${VIMVER}.tar.gz"
cd "vim-${VIMVER/v/}"
./configure --enable-python3interp=yes --with-python3-command="python${PYVER}" \
  --prefix=/opt/vim --enable-fail-if-missing
make -j"$(nproc)"
make install
cd /
rm -rf "/opt/vim-${VIMVER/v/}" "/opt/${VIMVER}.tar.gz"

cat >/etc/profile.d/vim.sh <<'EOF'
export PATH=/opt/vim/bin:$PATH
EOF

#############################################################################
# OpenCV from source + ffcv
#############################################################################
apt-get install -y --no-install-recommends \
  libjpeg-dev libpng-dev libtiff-dev \
  libavcodec-dev libavformat-dev libswscale-dev \
  libgtk-3-dev

cd /opt
wget -q "https://github.com/opencv/opencv/archive/${OPENCV_VER}.zip"
unzip -q "${OPENCV_VER}.zip"
cd "opencv-${OPENCV_VER}"
mkdir -p build
cd build
cmake -DOPENCV_GENERATE_PKGCONFIG=ON ..
make -j6
make install
ldconfig
cd /
rm -rf "/opt/${OPENCV_VER}.zip" "/opt/opencv-${OPENCV_VER}"

cat >/etc/profile.d/opencv.sh <<'EOF'
export LD_LIBRARY_PATH=/usr/local/lib64:${LD_LIBRARY_PATH:-}
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:${PKG_CONFIG_PATH:-}
EOF

python -m pip install ffcv

#############################################################################
# DeepSpeed
#############################################################################
python -m pip install deepspeed-kernels
python -m pip install deepspeed

python - <<'PY'
import glob, pathlib
paths = glob.glob("/usr/local/lib*/python*/site-packages/deepspeed/comm/comm.py")
for p in paths:
    pp = pathlib.Path(p)
    txt = pp.read_text()
    new = txt.replace("hostname -I", "hostname -s")
    if new != txt:
        pp.write_text(new)
PY

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
# FAISS (GPU + Python)
#############################################################################
cd /opt
git clone --branch "v${FAISS_VERSION}" https://github.com/facebookresearch/faiss
cd faiss

cmake -B build . \
  -DFAISS_ENABLE_GPU=ON -DFAISS_ENABLE_PYTHON=ON \
  -DBUILD_TESTING=OFF -DFAISS_OPT_LEVEL=generic -DFAISS_ENABLE_C_API=ON \
  -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_CUDA_ARCHITECTURES="${CMAKE_CUDA_ARCHITECTURES}" \
  -DCMAKE_BUILD_TYPE=Release

make -C build faiss
make -C build swigfaiss
cd build/faiss/python
python -m pip install .
cd /opt/faiss
make -C build install
ldconfig
cd /opt
rm -rf faiss

cat >/etc/profile.d/faiss.sh <<EOF
export LD_LIBRARY_PATH=/usr/local/lib/python${PYVER}/site-packages/faiss/:\${LD_LIBRARY_PATH:-}
EOF

#############################################################################
# Custom env from your %environment
#############################################################################
cat >/etc/profile.d/custom_env.sh <<'EOF'
export LIBRARY_PATH=
export KERAS_BACKEND="torch"
EOF

#############################################################################
# Cleanup
#############################################################################
apt-get clean
rm -rf /var/lib/apt/lists/*
echo "Done."