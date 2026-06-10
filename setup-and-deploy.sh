#!/bin/bash
set -e

# ============================================================
# OCR App - Enterprise Deploy Script
# Usage: bash setup-and-deploy.sh
# ============================================================

DATABRICKS_HOST="https://adb-7970838286274484.4.azuredatabricks.net"
YOUR_EMAIL="yukta.khatri@honeywell.com"
APP_NAME="ai-parse-demo"

# Token is asked at runtime (GitHub blocks hardcoded secrets)
read -sp "Paste your Databricks Token: " DATABRICKS_TOKEN; echo

APP_WORKSPACE_PATH="/Workspace/Users/${YOUR_EMAIL}/apps/${APP_NAME}"

echo ""
echo "======================================"
echo " Host  : $DATABRICKS_HOST"
echo " Email : $YOUR_EMAIL"
echo " App   : $APP_NAME"
echo "======================================"

# ---------- 1. Install CLI ----------
echo ""
echo "[1/7] Checking Databricks CLI..."
CLI=$(command -v databricks 2>/dev/null || echo "")
if [ -z "$CLI" ]; then
  arch=$(uname -m); os=$(uname -s | tr '[:upper:]' '[:lower:]')
  [ "$arch" = "arm64" ] && ARCH="arm64" || ARCH="amd64"
  curl -fsSL -o /tmp/db_cli.zip \
    "https://github.com/databricks/cli/releases/download/v0.240.0/databricks_cli_0.240.0_${os}_${ARCH}.zip"
  mkdir -p ~/bin
  unzip -o /tmp/db_cli.zip databricks -d ~/bin/
  chmod +x ~/bin/databricks
  export PATH="$HOME/bin:$PATH"
  CLI="$HOME/bin/databricks"
fi
echo "✅ CLI: $($CLI --version)"

# ---------- 2. Configure CLI ----------
echo ""
echo "[2/7] Configuring CLI..."
cat > ~/.databrickscfg << CFGEOF
[DEFAULT]
host = ${DATABRICKS_HOST}
token = ${DATABRICKS_TOKEN}
CFGEOF
$CLI auth describe 2>&1 | grep -E "User:|Authenticated|error" || true
echo "✅ CLI configured"

# ---------- 3. Clone repo ----------
echo ""
echo "[3/7] Cloning repo..."
REPO_DIR="$HOME/ocr-databricks"
if [ -d "$REPO_DIR/.git" ]; then
  echo "Repo exists, pulling latest..."
  cd "$REPO_DIR" && git pull
else
  git clone https://github.com/rinitlulla18-wq/ocr-databricks.git "$REPO_DIR"
fi
cd "$REPO_DIR"
echo "✅ Repo ready"

# ---------- 4. Install Node deps ----------
echo ""
echo "[4/7] Installing frontend dependencies..."
if ! command -v node &>/dev/null; then
  echo "Installing Node.js..."
  curl -fsSL https://nodejs.org/dist/v20.11.0/node-v20.11.0-linux-x64.tar.gz | tar -xz -C /tmp/
  export PATH="/tmp/node-v20.11.0-linux-x64/bin:$PATH"
fi
echo "Node: $(node --version)"
cd "$REPO_DIR/frontend" && npm install --silent
cd "$REPO_DIR"
echo "✅ Dependencies ready"

# ---------- 5. Write app.yaml ----------
echo ""
echo "[5/7] Writing app.yaml..."
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
  value: "$APP_WORKSPACE_PATH/static"
YAMLEOF
echo "✅ app.yaml ready"

# ---------- 6. Create App ----------
echo ""
echo "[6/7] Creating Databricks App..."
$CLI apps create "$APP_NAME" 2>/dev/null && echo "✅ App created" || echo "ℹ️  App already exists, continuing..."

# ---------- 7. Deploy ----------
echo ""
echo "[7/7] Deploying..."
# Fix CLI path in deploy.sh
sed -i "s| databricks | $CLI |g" "$REPO_DIR/deploy.sh" 2>/dev/null || \
sed -i '' "s| databricks | $CLI |g" "$REPO_DIR/deploy.sh" 2>/dev/null || true
chmod +x "$REPO_DIR/deploy.sh"
cd "$REPO_DIR"
./deploy.sh "$APP_WORKSPACE_PATH" "$APP_NAME" "DEFAULT"

echo ""
echo "======================================"
echo "✅ DEPLOYMENT COMPLETE!"
APP_URL=$($CLI apps get "$APP_NAME" 2>/dev/null | grep '"url"' | sed 's/.*"url": *"\([^"]*\)".*/\1/' || echo "Check Databricks Apps UI")
echo "🌐 App URL: $APP_URL"
echo "======================================"
