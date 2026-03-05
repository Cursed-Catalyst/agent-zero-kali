#!/bin/bash
# ============================================================
#  Agent Zero - Kali Linux Installer (No Docker Required)
#  Default model: Claude claude-sonnet-4-5
#  Auto-starts on http://localhost:5000
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="$HOME/agent-zero"
PORT=5000

banner() {
  echo -e "${CYAN}"
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║        Agent Zero  ×  Kali Linux Setup       ║"
  echo "  ║        Default Model: Claude claude-sonnet-4-5      ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

log()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
err()    { echo -e "${RED}[✗]${NC} $1"; exit 1; }
prompt() { echo -e "${BOLD}${CYAN}[?]${NC} $1"; }

banner

# ── 1. Check for Python 3.11+ ─────────────────────────────
log "Checking Python version..."
PYTHON=$(command -v python3 || true)
[ -z "$PYTHON" ] && err "python3 not found. Run: sudo apt install python3"

PY_VER=$($PYTHON -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$(echo $PY_VER | cut -d. -f1)
PY_MINOR=$(echo $PY_VER | cut -d. -f2)
if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 11 ]); then
  warn "Python $PY_VER found. Agent Zero works best with 3.11+."
  warn "Installing python3.12 via apt..."
  sudo apt-get update -qq && sudo apt-get install -y python3.12 python3.12-venv python3.12-dev
  PYTHON=$(command -v python3.12)
fi
log "Using Python: $($PYTHON --version)"

# ── 2. System dependencies ─────────────────────────────────
log "Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
  git curl wget build-essential \
  python3-pip python3-venv \
  libssl-dev libffi-dev \
  chromium chromium-driver \
  --no-install-recommends -qq

# ── 3. Clone Agent Zero ────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
  warn "Found existing install at $INSTALL_DIR"
  prompt "Update it? [y/N]"
  read -r UPDATE
  if [[ "$UPDATE" =~ ^[Yy]$ ]]; then
    cd "$INSTALL_DIR" && git pull && log "Updated."
  fi
else
  log "Cloning Agent Zero into $INSTALL_DIR..."
  git clone https://github.com/agent0ai/agent-zero.git "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ── 4. Virtual environment ─────────────────────────────────
log "Creating Python virtual environment..."
$PYTHON -m venv .venv
source .venv/bin/activate

log "Installing Python requirements (this may take a few minutes)..."
pip install --upgrade pip -q
pip install -r requirements.txt -q
playwright install chromium --with-deps 2>/dev/null || warn "Playwright chromium install had issues (non-fatal)"

# ── 5. Collect Anthropic API key ──────────────────────────
echo ""
prompt "Enter your Anthropic API key (starts with sk-ant-...):"
read -r -s ANTHROPIC_KEY
echo ""

if [[ ! "$ANTHROPIC_KEY" == sk-ant-* ]]; then
  warn "Key doesn't look like an Anthropic key (expected sk-ant-...). Continuing anyway."
fi

# ── 6. Write .env ─────────────────────────────────────────
log "Writing .env configuration..."
cat > "$INSTALL_DIR/.env" << EOF
# ── Anthropic / Claude ──────────────────────────────────
API_KEY_ANTHROPIC=${ANTHROPIC_KEY}

# ── Web UI ───────────────────────────────────────────────
WEB_UI_PORT=${PORT}
WEB_UI_HOST=127.0.0.1

# ── Default model override (applied by patched initialize.py)
A0_DEFAULT_MODEL=claude-sonnet-4-5
A0_DEFAULT_PROVIDER=anthropic

# ── Disable Docker code executor (use local shell instead)
# CODE_EXEC_DOCKER_ENABLED=false
EOF
log ".env written."

# ── 7. Patch initialize.py to default to Claude ───────────
log "Patching initialize.py to default to Claude claude-sonnet-4-5..."

INIT_FILE="$INSTALL_DIR/initialize.py"
PATCH_FILE="$INSTALL_DIR/initialize_claude_patch.py"

# Write the patch as a separate helper that wraps initialize.py
cat > "$PATCH_FILE" << 'PYEOF'
"""
Monkey-patch applied before initialize.py runs.
Forces Claude claude-sonnet-4-5 as the default chat + utility model.
"""
import os, sys

def apply_claude_defaults():
    """
    Set environment variables that initialize.py and Agent Zero read
    to configure default models. These are respected by AgentConfig.
    """
    defaults = {
        # Primary chat model
        "A0_CHAT_MODEL_PROVIDER":   "anthropic",
        "A0_CHAT_MODEL_NAME":       "claude-sonnet-4-5",
        # Utility / summarization model
        "A0_UTILITY_MODEL_PROVIDER": "anthropic",
        "A0_UTILITY_MODEL_NAME":     "claude-sonnet-4-5",
        # Embedding model (free, local)
        "A0_EMBED_MODEL_PROVIDER":  "huggingface",
        "A0_EMBED_MODEL_NAME":      "sentence-transformers/all-MiniLM-L6-v2",
    }
    for k, v in defaults.items():
        os.environ.setdefault(k, v)

apply_claude_defaults()
PYEOF

# Inject the patch import at the top of initialize.py if not already there
if ! grep -q "initialize_claude_patch" "$INIT_FILE"; then
  # Prepend import to initialize.py
  TMP=$(mktemp)
  echo "import initialize_claude_patch  # Auto-added by install_kali.sh" > "$TMP"
  cat "$INIT_FILE" >> "$TMP"
  mv "$TMP" "$INIT_FILE"
  log "initialize.py patched successfully."
else
  log "initialize.py already patched."
fi

# ── 8. Write the launcher script ─────────────────────────
log "Writing launcher script..."
cat > "$INSTALL_DIR/start.sh" << LAUNCHER
#!/bin/bash
# ── Agent Zero Launcher ───────────────────────────────────
cd "\$(dirname "\$0")"
source .venv/bin/activate
export \$(grep -v '^#' .env | xargs)
echo ""
echo -e "\033[0;36m  Agent Zero is starting..."
echo -e "  Open your browser at: http://localhost:${PORT}\033[0m"
echo ""
python run_ui.py --port ${PORT} --host 127.0.0.1
LAUNCHER

chmod +x "$INSTALL_DIR/start.sh"
log "Launcher written at $INSTALL_DIR/start.sh"

# ── 9. Optional: systemd user service ────────────────────
prompt "Install as a systemd user service (auto-start on login)? [y/N]"
read -r SYSTEMD
if [[ "$SYSTEMD" =~ ^[Yy]$ ]]; then
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/agent-zero.service" << SERVICE
[Unit]
Description=Agent Zero AI Framework
After=network.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/.venv/bin/python run_ui.py --port ${PORT} --host 127.0.0.1
EnvironmentFile=${INSTALL_DIR}/.env
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICE

  systemctl --user daemon-reload
  systemctl --user enable agent-zero.service
  log "Systemd service installed. It will start automatically on login."
  log "Manual control: systemctl --user start|stop|status agent-zero"
fi

# ── 10. Done ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║   ✅  Installation Complete!              ║"
echo -e "╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e " ${CYAN}To start Agent Zero:${NC}"
echo -e "   cd ~/agent-zero && ./start.sh"
echo ""
echo -e " ${CYAN}Then open in browser:${NC}"
echo -e "   http://localhost:${PORT}"
echo ""
echo -e " ${YELLOW}Default model: Claude claude-sonnet-4-5 (Anthropic)${NC}"
echo ""
