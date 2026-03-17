#!/bin/bash

set -euo pipefail

#make apt to don't ask questions
export DEBIAN_FRONTEND=noninteractive

#############################################################################
# Versions
#############################################################################
PYVER="3.12"

NVIDIA_DRIVER="590"
CUDNN_MAJOR="9"
CPU_ARCH=$(uname -m)
VLLM_VERSION=$(curl -s https://api.github.com/repos/vllm-project/vllm/releases/latest | jq -r .tag_name | sed 's/^v//')
CUDA_VERSION=130 # or other
#For A100
export TORCH_CUDA_ARCH_LIST="8.0"
export CMAKE_CUDA_ARCHITECTURES="70;80"
export MAKEFLAGS="-j2"
export MAX_JOBS=2 

VENV_PATH="$HOME/venvs"
echo "venv path:$VENV_PATH"
mkdir -p $VENV_PATH

#############################################################################
# PyTorch + requirements
#############################################################################
if [[ ! -f ../data/requirements.txt ]]; then
  echo "ERROR: ../data/requirements.txt missing. Copy your requirements.txt to ../data/requirements.txt"
  exit 1
fi
#python3 -m venv "$VENV_PATH/pytorch"
uv venv --python 3.12 "$VENV_PATH/pytorch"
echo "venv created to $VENV_PATH/pytorch"    
source "$VENV_PATH/pytorch/bin/activate"
uv pip install https://github.com/vllm-project/vllm/releases/download/v${VLLM_VERSION}/vllm-${VLLM_VERSION}+cu${CUDA_VERSION}-cp38-abi3-manylinux_2_35_${CPU_ARCH}.whl \
 --extra-index-url https://download.pytorch.org/whl/cu${CUDA_VERSION} \
 --index-strategy unsafe-best-match 
uv pip install -r ../data/requirements.txt
#############################################################################
#GPTmodel
##############################################################################
uv pip install gptqmodel --no-build-isolation
#############################################################################
# Jupyter
#############################################################################
uv pip install notebook
#############################################################################
# Flash attention
#############################################################################
uv pip install flash-attn --no-build-isolation -v --no-cache-dir
