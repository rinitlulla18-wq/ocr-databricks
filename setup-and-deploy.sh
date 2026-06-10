#!/bin/bash
set -e

# ============================================================
# OCR App - Enterprise Deploy Script
# Usage: bash setup-and-deploy.sh
# ============================================================

# ---------- CONFIG - FILL THESE ----------
DATABRICKS_HOST=""        # e.g. https://adb-xxxx.azuredatabricks.net
DATABRICKS_TOKEN=""       # your PAT token
APP_NAME="ai-parse-demo"
YOUR_EMAIL=""             # your Databricks workspace email
# -----------------------------------------

# Prompt if not set
if [ -z "$DATABRICKS_HOST" ]; then
  read -p "Databricks Host URL: " DATABRICKS_HOST
fi
if [ -z "$DATABRICKS_TOKEN" ]; then
  read -sp "Databricks Token: " DATABRICKS_TOKEN; echo
fi
if [ -z "$YOUR_EMAIL" ]; then
  read -p "Your workspace email: " YOUR_EMAIL
fi

APP_WORKSPACE_PATH="/Workspace/Users/${YOUR_EMAIL}/apps/${APP_NAME}"

echo ""
echo "======================================"
echo " Host  : $DATABRICKS_HOST"
echo " App   : $APP_NAME"
echo " Path  : $APP_WORKSPACE_PATH"
echo "======================================"

# ---------- 1. Install CLI ----------
echo ""
echo "[1/6] Installing Databricks CLI..."
if ! command -v databricks &>/dev/null; then
  arch=$(uname -m)
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  [ "$arch" = "arm64" ] && arch="arm64" || arch="amd64"
  [ "$os" = "darwin" ] && os="darwin" || os="linux"
  curl -fsSL -o /tmp/db_cli.zip \
    "https://github.com/databricks/cli/releases/download/v0.240.0/databricks_cli_0.240.0_${os}_${arch}.zip"
  unzip -o /tmp/db_cli.zip databricks -d /usr/local/bin/ 2>/dev/null || \
    { mkdir -p ~/bin && unzip -o /tmp/db_cli.zip databricks -d ~/bin/; export PATH="$HOME/bin:$PATH"; }
  echo "✅ CLI installed"
else
  echo "✅ CLI already installed: $(databricks --version)"
fi

CLI=$(command -v databricks || echo "$HOME/bin/databricks")

# ---------- 2. Configure CLI ----------
echo ""
echo "[2/6] Configuring CLI..."
mkdir -p ~/.databricks
cat > ~/.databrickscfg << CFGEOF
[DEFAULT]
host = ${DATABRICKS_HOST}
token = ${DATABRICKS_TOKEN}
CFGEOF
$CLI auth describe 2>&1 | grep -E "User:|Authenticated|error" || true
echo "✅ CLI configured"

# ---------- 3. Clone repo ----------
echo ""
echo "[3/6] Cloning repo..."
REPO_DIR="$HOME/ocr-databricks"
if [ -d "$REPO_DIR" ]; then
  cd "$REPO_DIR" && git pull
else
  git clone https://github.com/rinitlulla18-wq/ocr-databricks.git "$REPO_DIR"
  cd "$REPO_DIR"
fi
echo "✅ Repo ready at $REPO_DIR"

# ---------- 4. Install Node & deps ----------
echo ""
echo "[4/6] Setting up frontend..."
if ! command -v node &>/dev/null; then
  curl -fsSL https://nodejs.org/dist/v20.11.0/node-v20.11.0-linux-x64.tar.gz | tar -xz -C /tmp/
  export PATH="/tmp/node-v20.11.0-linux-x64/bin:$PATH"
fi
cd "$REPO_DIR/frontend"
npm install --silent
echo "✅ Node deps installed"

# ---------- 5. Update app.yaml ----------
echo ""
echo "[5/6] Updating app.yaml..."
cat > "$REPO_DIR/backend/app.yaml" << YAMLEOF
command: ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
runtime: python_3.10
env:
- name: "DATABRICKS_WAREHOUSE_ID"
  value: "02804c29f542248b"
- name: "DATABRICKS_VOLUME_PATH"
  value: "/Volumes/corp_enit_sandbox_catalog/data_classification_poc/data/"
- name: "DATABRICKS_DELTA_TABLE_PATH"
  value: "corp_enit_sandbox_catalog.data_classification_poc.doc_results"
- name: "BATCH_INPUT_VOLUME_PATH"
  value: "/Volumes/corp_enit_sandbox_catalog/data_classification_poc/data/"
- name: "STATIC_FILES_PATH"
  value: "${APP_WORKSPACE_PATH}/static"
YAMLEOF
echo "✅ app.yaml updated"

# ---------- 6. Create app & deploy ----------
echo ""
echo "[6/6] Creating app and deploying..."
cd "$REPO_DIR"

# Create app (ignore if already exists)
$CLI apps create "$APP_NAME" 2>/dev/null || echo "App may already exist, continuing..."

# Make deploy.sh use our CLI
sed -i "s|databricks |$CLI |g" deploy.sh 2>/dev/null || true

chmod +x deploy.sh
./deploy.sh "$APP_WORKSPACE_PATH" "$APP_NAME" "DEFAULT"

echo ""
echo "======================================"
echo "✅ DEPLOYMENT COMPLETE!"
echo ""
$CLI apps get "$APP_NAME" 2>/dev/null | grep -E '"url"|"state"' || true
echo "======================================"
