#!/bin/bash
#
# Deployment Automation Script
# Created by: @KADIRI PROSPER
#

# Safety Flags
set -e
set -o pipefail
set -u


LOG_DIR="$(pwd)/logs"
mkdir -p "$LOG_DIR"
sleep 1

LOG_FILE="$LOG_DIR/deploy_$(date +'%Y%m%d_%H%M%S').log"

exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "Error occured at line $LINENO. Check $LOG_FILE for details." >&2' ERR

log() {
	local LEVEL="$1"; shift
	local MESSAGE="$@"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [$LEVEL] $MESSAGE" | tee -a "$LOG_FILE"
}


# Data Collection Segment
echo "Details Collection Segment "
echo

read -rp "Enter your Git Repository URL: " GIT_URL

# Validate Git URL input before going to the next place

if [[ ! $GIT_URL =~ ^https:// ]]; then
	echo "Invalid Git URL format. Must start with https://"
	log ERROR "Invalid Git URL format"
	exit 1
fi

read -rsp "Enter your Personal Access Token (PAT): " PAT
echo
read -rp "Enter branch name (press Enter for 'main'): " BRANCH
BRANCH=${BRANCH:-main}

# SSH Cred Segment
read -rp "SSH Username for remote server: " SSH_USER

read -rp "Remote Server IP address: " SERVER_IP
if [[ ! $SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Invalid IP address format"
	log ERROR "Invalid IP address format"
	exit 2
fi

read -rp "SSH Private Key Path: " SSH_KEY
if [[ ! -f "$SSH_KEY" ]]; then
	echo "SSH key not found at $SSH_KEY"
	log ERROR "SSH Key not found at $SSH_KEY"
	exit 3
fi

read -rp "Application Internal port (e.g., 5000): " APP_PORT
if [[ ! $APP_PORT =~ ^[0-9]+$ ]]; then
	echo "Application port must be numeric"
	log ERROR "PORT MUST BE NUMERIC"
	exit 4
fi

log INFO "Data collected and validated successfully"

# REPOSITORY CLONING ZONE

log INFO "Beginning Repo Cloning process"

REPO_DIR=$(basename "$GIT_URL" .git)

if [[ -d "$REPO_DIR" ]]; then
	# PULL THE CHANGES
	cd "$REPO_DIR"
	git pull origin "$BRANCH"
	git checkout "$BRANCH"
else
	# CLONE REPO
	git clone "https://${PAT}@${GIT_URL#https://}" --branch "$BRANCH"
	cd "$REPO_DIR"
fi

# echo "Repo ready at $(pwd)"


log INFO "Repo Clone Successful"

# SSH CONNECTION ZONE
#
#
# Verify Reachability of Server

log INFO "Verifying reachability of the Remote server"

if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$SERVER_IP" "echo connected"; then
	echo "SSH Connection established"
	log INFO "Connection Established"
else
	echo "Unable to establish connection. Verify credentials"
	log ERROR "Error connecting to Remote Server"
	exit 10
fi


# Prep server
log INFO "Setting up server"
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << 'EOF'
set -e

# Update the system
sudo apt update -y

# Install needed components
sudo apt install -y docker.io docker-compose nginx

sudo usermod -aG docker $USER

# Enable and start services
sudo systemctl enable docker nginx
sudo systemctl start docker nginx	

EOF

# Verify the installations made

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << 'EOF'
docker --version
docker-compose --version
nginx -v
EOF

log INFO "Uploading file to remote host"
# Upload file to remote host
rsync -avz -e "ssh -i $SSH_KEY" ./ "$SSH_USER@$SERVER_IP:/home/$SSH_USER/app"

rollback() {
	log WARN "Deployment Failed. Rolling back to previous version"
	ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" << 'EOF'
	if docker images | grep previous_app_image; then
		docker stop test_app || true
		docker rm test_app || true
		docker run -d -p ${APP_PORT}:${APP_PORT} --name test_app previous_app_image
	else
		echo "No previous version found"
	fi
EOF
} 
trap rollback ERR

# Containerize app on server

log INFO "Containerizing application on server"
ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<'EOF'
cd ~/app

if [[ -f docker-compose.yml ]]; then
# Using docker-compose
docker-compose down
docker-compose up -d --build
else
# using vanilla docker
docker stop test_app || true
docker rm test_app || true
docker build -t app_image .
docker run -d -p ${APP_PORT}:${APP_PORT} --name test_app app_image
fi

docker ps
EOF

# Reverse Proxying

log INFO "Reverse prox NGINX setup"

PROXY_CONF="/etc/nginx/sites-available/app.conf"

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP"  bash -s <<EOF
set -e

sudo tee "$PROXY_CONF" > /dev/null <<'NGINX'
server {
	listen 80;
	server_name _;

	location / {
		proxy_pass http://127.0.0.1:$APP_PORT;
		proxy_set_header Host \$host;
		proxy_set_header X-Real-IP \$remote_addr;
	}
}
NGINX

sudo ln -sf $PROXY_CONF /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
EOF

# Log Validation

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<'EOF'
docker ps --format "table {{.Names}\t{{.Status}}\t{{.Ports}}"
sudo systemctl status nginx --no-pager

curl -I http://localhost
EOF


log INFO "Cheers -- Deployment Successful"

if [[ "$1" == "--cleanup" ]]; then
	log INFO "Performing full cleanup..."
	ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" <<'EOF'
	docker system prune -a -f
	sudo rm -rf ~/app /etc/nginx/sites-available/app.conf /etc/nginx/sites-enabled/app.conf
	sudo systemctl reload nginx
EOF
log INFO "Cleanup Complete."
exit 0
fi
