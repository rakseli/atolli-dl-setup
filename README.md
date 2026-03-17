# atolli-dl-setup
Scripts for VM installations when environment is open 
1. Install general software using `/scripts/install_basic.sh`
2. Install Python packages into venv `/scripts/install_python.sh`
3. Export actual requirements from the venv into `post_requirements.txt`
4. Create `wheelhouse` for future flexibility from `post_requirements.txt`
5. Download models
6. Download test data