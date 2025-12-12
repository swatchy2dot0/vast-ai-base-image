#!/bin/bash

set -euo pipefail

. /venv/main/bin/activate

apt-get install -y \
    libasound2-dev \
    pulseaudio-utils \
    wget \
    --no-install-recommends

cd "$WORKSPACE"
[[ -d "${WORKSPACE}/Wan2GP" ]] || git clone https://github.com/deepbeepmeep/Wan2GP
cd Wan2GP
[[ -n "{WAN2GP_VERSION:-}" ]] && git checkout "$WAN2GP_VERSION"

uv pip install torch==${TORCH_VERSION:-2.8.0} torchvision torchaudio --torch-backend=auto
uv pip install -r requirements.txt

echo current directory is
pwd

wget -P ./loras https://huggingface.co/Kijai/WanVideo_comfy/blob/main/Wan21_CausVid_14B_T2V_lora_rank32.safetensors

wget -P ./loras https://huggingface.co/DeepBeepMeep/Wan2.2/resolve/main/wan2.2_animate_relighting_lora.safetensors

wget -P ./ckpts https://huggingface.co/DeepBeepMeep/Wan2.2/resolve/main/wan2.2_animate_14B_quanto_bf16_int8.safetensors

echo download done

ls ./loras -rtl
ls ./ckpts -rtl

echo Create Wan2GP startup scripts
cat > /opt/supervisor-scripts/wan2gp.sh << 'EOL'
#!/bin/bash

utils=/opt/supervisor-scripts/utils
. "${utils}/logging.sh"
. "${utils}/cleanup_generic.sh"
. "${utils}/environment.sh"
. "${utils}/exit_serverless.sh"
. "${utils}/exit_portal.sh" "Wan2GP"

echo "Starting Wan2GP"

. /etc/environment
. /venv/main/bin/activate

cd "${WORKSPACE}/Wan2GP"
export XDG_RUNTIME_DIR=/tmp
export SDL_AUDIODRIVER=dummy
python wgp.py --profile 3 2>&1

EOL

chmod +x /opt/supervisor-scripts/wan2gp.sh

echo Generate the supervisor config files
cat > /etc/supervisor/conf.d/wan2gp.conf << 'EOL'
[program:wan2gp]
environment=PROC_NAME="%(program_name)s"
command=/opt/supervisor-scripts/wan2gp.sh
autostart=true
autorestart=true
exitcodes=0
startsecs=0
stopasgroup=true
killasgroup=true
stopsignal=TERM
stopwaitsecs=10
# This is necessary for Vast logging to work alongside the Portal logs (Must output to /dev/stdout)
stdout_logfile=/dev/stdout
redirect_stderr=true
stdout_events_enabled=true
stdout_logfile_maxbytes=0
stdout_logfile_backups=0
EOL

# Update supervisor to start the new service
supervisorctl reread
supervisorctl update

echo provisioning done
