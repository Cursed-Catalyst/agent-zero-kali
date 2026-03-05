#!/bin/bash
# ============================================================
#  Agent Zero - Kali Linux Installer (No Docker Required)
#  Compatible with Python 3.13 (Kali default)
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
  echo "  ║     Agent Zero × Kali Linux Setup            ║"
  echo "  ║     Default Model: Claude claude-sonnet-4-5  ║"
  echo "  ║     Python 3.13 Compatible                   ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo -e "${NC}"
}

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

banner

# ── 1. System dependencies ─────────────────────────────────
log "Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
  git curl wget build-essential \
  python3-pip python3-venv python3-dev \
  libssl-dev libffi-dev \
  chromium chromium-driver \
  --no-install-recommends -qq

PYTHON=$(command -v python3)
PY_VER=$($PYTHON --version)
log "Using $PY_VER"

# ── 2. Clone Agent Zero ────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
  warn "Found existing install at $INSTALL_DIR — skipping clone."
else
  log "Cloning Agent Zero..."
  git clone https://github.com/agent0ai/agent-zero.git "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ── 3. Virtual environment ─────────────────────────────────
log "Creating Python virtual environment..."
rm -rf .venv
$PYTHON -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel -q

# ── 4. Write Python 3.13 compatible requirements ──────────
log "Writing Python 3.13 compatible requirements..."
cat > requirements_py313.txt << 'REQS'
ansio==0.0.1
inputimeout==1.0.4
GitPython
flask
flask-basicauth
flask-socketio
anthropic
langchain
langchain-community
langchain-anthropic
langchain-openai
langchain-google-genai
langchain-groq
langchain-mistralai
langchain-chroma
langchain-ollama
langchain-huggingface
sentence-transformers
chromadb
python-dotenv
requests
beautifulsoup4
markdownify
html2text
faiss-cpu
numpy
pydantic
paramiko
pypdf
webcolors
tiktoken
openai
playwright
browseruse
duckduckgo-search
docker
mcp
Pillow
REQS

log "Installing packages (this will take a few minutes)..."
pip install -r requirements_py313.txt --ignore-requires-python -q 2>&1 | tail -5

# Install kokoro separately without conflicting deps
log "Installing kokoro (TTS)..."
pip install kokoro --no-deps -q 2>/dev/null || warn "kokoro skipped — voice features disabled (non-fatal)"

# Install playwright browsers
log "Installing Playwright browser..."
playwright install chromium 2>/dev/null || warn "Playwright chromium skipped (non-fatal)"

# ── 5. Claude defaults patch ──────────────────────────────
log "Installing Claude defaults patch..."
cat > "$INSTALL_DIR/initialize_claude_patch.py" << 'PYEOF'
"""
initialize_claude_patch.py
Forces Claude claude-sonnet-4-5 as the default model.
Auto-injected by install_kali.sh
"""
import os

def apply_claude_defaults():
    defaults = {
        "A0_CHAT_MODEL_PROVIDER":    "anthropic",
        "A0_CHAT_MODEL_NAME":        "claude-sonnet-4-5",
        "A0_UTILITY_MODEL_PROVIDER": "anthropic",
        "A0_UTILITY_MODEL_NAME":     "claude-sonnet-4-5",
        "A0_EMBED_MODEL_PROVIDER":   "huggingface",
        "A0_EMBED_MODEL_NAME":       "sentence-transformers/all-MiniLM-L6-v2",
    }
    for key, value in defaults.items():
        os.environ.setdefault(key, value)

apply_claude_defaults()
PYEOF

# Patch initialize.py
INIT_FILE="$INSTALL_DIR/initialize.py"
if ! grep -q "initialize_claude_patch" "$INIT_FILE" 2>/dev/null; then
  TMP=$(mktemp)
  echo "import initialize_claude_patch  # Auto-added by install_kali.sh" > "$TMP"
  cat "$INIT_FILE" >> "$TMP"
  mv "$TMP" "$INIT_FILE"
  log "initialize.py patched."
else
  log "initialize.py already patched."
fi

# ── 6. Anthropic API key ──────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}[?] Enter your Anthropic API key (starts with sk-ant-...):${NC}"
read -r -s ANTHROPIC_KEY
echo ""

# ── 7. Write .env ─────────────────────────────────────────
log "Writing .env configuration..."
cat > "$INSTALL_DIR/.env" << EOF
# Anthropic
API_KEY_ANTHROPIC=${ANTHROPIC_KEY}

# Other providers (optional)
API_KEY_OPENAI=
API_KEY_GROQ=
API_KEY_GOOGLE=

# Web UI
WEB_UI_PORT=${PORT}
WEB_UI_HOST=127.0.0.1

# Default model
A0_CHAT_MODEL_PROVIDER=anthropic
A0_CHAT_MODEL_NAME=claude-sonnet-4-5
A0_UTILITY_MODEL_PROVIDER=anthropic
A0_UTILITY_MODEL_NAME=claude-sonnet-4-5
A0_EMBED_MODEL_PROVIDER=huggingface
A0_EMBED_MODEL_NAME=sentence-transformers/all-MiniLM-L6-v2
EOF

# ── 8. Launcher ───────────────────────────────────────────
log "Writing launcher..."
cat > "$INSTALL_DIR/start.sh" << LAUNCHER
#!/bin/bash
cd "\$(dirname "\$0")"
source .venv/bin/activate
export \$(grep -v '^#' .env | xargs)
echo ""
echo -e "\033[0;36m  Agent Zero starting..."
echo -e "  Browser UI : http://localhost:${PORT}"
echo -e "  CLI mode   : python run_cli.py\033[0m"
echo ""
python run_ui.py --port ${PORT} --host 127.0.0.1
LAUNCHER
chmod +x "$INSTALL_DIR/start.sh"

# ── 9. Tailscale ──────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}[?] Install Tailscale for remote access from your other devices? [y/N]${NC}"
read -r TAILSCALE
if [[ "$TAILSCALE" =~ ^[Yy]$ ]]; then
  log "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  log "Authenticate Tailscale in your browser..."
  sudo tailscale up
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "run: tailscale ip")
  log "Tailscale IP: $TAILSCALE_IP"
  log "Access from other devices: http://${TAILSCALE_IP}:${PORT}"
fi

# ── 10. Done ──────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║   ✅  Installation Complete!              ║"
echo -e "╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e " ${CYAN}Start Agent Zero:${NC}"
echo -e "   cd ~/agent-zero && ./start.sh"
echo ""
echo -e " ${CYAN}Open in browser:${NC}"
echo -e "   http://localhost:${PORT}"
echo ""
echo -e " ${CYAN}CLI mode (no browser):${NC}"
echo -e "   cd ~/agent-zero && source .venv/bin/activate && python run_cli.py"
echo ""
echo -e " ${YELLOW}Default model: Claude claude-sonnet-4-5${NC}"
echo ""
