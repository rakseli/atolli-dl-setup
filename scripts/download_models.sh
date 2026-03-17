#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./hf_download_models.sh models.txt [DEST_DIR]
#
# models.txt: one Hugging Face repo id per line, e.g.
#   meta-llama/Llama-2-7b-hf
#   google/flan-t5-base
#
# Notes:
# - Requires: huggingface_hub CLI (`pip install -U huggingface_hub`)
# - If a model is gated/private, run: `huggingface-cli login` first.

MODELS_FILE="${1:-}"
DEST_DIR="${2:-./hf_models}"

if [[ -z "${MODELS_FILE}" || ! -f "${MODELS_FILE}" ]]; then
  echo "Error: Provide a models file (one model repo per line)."
  echo "Usage: $0 models.txt [DEST_DIR]"
  exit 1
fi

mkdir -p "${DEST_DIR}"

# Optional: tune parallel transfer behavior for HF Hub
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-1}"

echo "Downloading models listed in: ${MODELS_FILE}"
echo "Destination directory: ${DEST_DIR}"
echo

# Read file line-by-line, skipping blanks and comments (# ...)
while IFS= read -r raw || [[ -n "${raw}" ]]; do
  model="$(echo "${raw}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  # Skip empty lines / comments
  [[ -z "${model}" ]] && continue
  [[ "${model}" =~ ^# ]] && continue

  echo "==> Downloading: ${model}"
  # --local-dir-use-symlinks False makes a real copy (more portable); change if you prefer symlinks.
    hf download "${model}" \
    --repo-type model \
    --local-dir "${DEST_DIR}/${model}" \
    --max-workers 4

  echo "✓ Done: ${model}"
  echo
done < "${MODELS_FILE}"

echo "All downloads completed."