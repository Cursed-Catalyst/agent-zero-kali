#!/bin/bash
# ============================================================
#  Agent Zero - Kali Linux Installer (No Docker Required)
#  Compatible with Python 3.13 (Kali default)
#  Default model: Claude claude-sonnet-4-5
#  Auto-starts on http://localhost:5000
#  All dependencies pre-installed — no manual pip installs!
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
  libssl-dev libffi-dev libsodium-dev \
  chromium chromium-driver \
  --no-install-recommends -qq

PYTHON=$(command -v python3)
log "Using $($PYTHON --version)"

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

# ── 4. Install ALL required packages ──────────────────────
log "Installing all required packages (this will take a few minutes)..."
pip install --ignore-requires-python -q \
  # Web framework
  flask \
  flask-basicauth \
  flask-socketio \
  uvicorn \
  aiohttp \
  websockets \
  python-socketio \
  eventlet \
  nest-asyncio \
  # Anthropic / LLM
  anthropic \
  openai \
  litellm \
  # LangChain
  langchain \
  langchain-community \
  langchain-anthropic \
  langchain-openai \
  langchain-google-genai \
  langchain-groq \
  langchain-mistralai \
  langchain-chroma \
  langchain-ollama \
  langchain-huggingface \
  # Embeddings & Vector DB
  sentence-transformers \
  chromadb \
  faiss-cpu \
  # Utilities
  python-dotenv \
  requests \
  aiofiles \
  asyncio \
  # Text processing
  beautifulsoup4 \
  markdownify \
  html2text \
  dirty-json \
  simpleeval \
  # Security / crypto
  cryptography \
  paramiko \
  # Data
  numpy \
  pydantic \
  # PDF & docs
  pypdf \
  Pillow \
  # Git
  GitPython \
  # Search
  duckduckgo-search \
  # Agent Zero specific
  ansio \
  inputimeout \
  mcp \
  tiktoken \
  tokenizers \
  webcolors \
  rfc3986 \
  annotated-doc \
  browser-use \
  # Misc
  schedule \
  rich \
  typer \
  pyyaml \
  toml \
  regex \
  tqdm \
  packaging

log "Core packages installed!"

# ── 5. Install kokoro without heavy deps ──────────────────
log "Installing kokoro (TTS — voice features)..."
pip install kokoro --no-deps -q 2>/dev/null || warn "kokoro skipped — voice features disabled (non-fatal)"

# ── 6. Playwright ─────────────────────────────────────────
log "Installing Playwright..."
pip install playwright -q
playwright install chromium 2>/dev/null || warn "Playwright chromium skipped (non-fatal)"

# ── 7. Claude defaults patch ──────────────────────────────
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

# ── 8. Anthropic API key ──────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}[?] Enter your Anthropic API key (starts with sk-ant-...):${NC}"
read -r -s ANTHROPIC_KEY
echo ""

# ── 9. Write .env ─────────────────────────────────────────
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

# ── 10. Launcher ──────────────────────────────────────────
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

# ── 11. Tailscale ─────────────────────────────────────────
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

# ── 12. Done ──────────────────────────────────────────────
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
