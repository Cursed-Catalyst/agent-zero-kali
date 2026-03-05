#!/bin/bash
# Agent Zero - Kali Linux Installer
# Compatible with Python 3.13
# Default model: Claude claude-sonnet-4-5

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="$HOME/agent-zero"
PORT=5000

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║     Agent Zero × Kali Linux Setup            ║"
echo "  ║     Default Model: Claude claude-sonnet-4-5  ║"
echo "  ║     Python 3.13 Compatible                   ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# 1. System dependencies
log "Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y git curl wget build-essential python3-pip python3-venv python3-dev libssl-dev libffi-dev libsodium-dev chromium chromium-driver --no-install-recommends -qq

PYTHON=$(command -v python3)
log "Using $($PYTHON --version)"

# 2. Clone Agent Zero
if [ -d "$INSTALL_DIR" ]; then
  warn "Found existing install — skipping clone."
else
  log "Cloning Agent Zero..."
  git clone https://github.com/agent0ai/agent-zero.git "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# 3. Virtual environment
log "Creating virtual environment..."
rm -rf .venv
$PYTHON -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel -q

# 4. Write requirements
log "Writing requirements..."
cat > /tmp/a0_requirements.txt << 'REQS'
flask
flask-basicauth
flask-socketio
uvicorn
aiohttp
websockets
python-socketio
eventlet
nest-asyncio
anthropic
openai
litellm
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
faiss-cpu
python-dotenv
requests
aiofiles
beautifulsoup4
markdownify
html2text
dirty-json
simpleeval
cryptography
paramiko
numpy
pydantic
pypdf
Pillow
GitPython
duckduckgo-search
ansio
inputimeout
mcp
tiktoken
tokenizers
webcolors
browser-use
schedule
rich
typer
pyyaml
toml
regex
tqdm
packaging
playwright
REQS

# 5. Install all packages
log "Installing all packages (this will take a few minutes)..."
pip install -r /tmp/a0_requirements.txt --ignore-requires-python -q
log "All packages installed!"

# 6. Kokoro TTS
log "Installing kokoro..."
pip install kokoro --no-deps -q 2>/dev/null || warn "kokoro skipped (non-fatal)"

# 7. Playwright
log "Setting up Playwright..."
playwright install chromium 2>/dev/null || warn "Playwright chromium skipped (non-fatal)"

# 8. Claude patch
log "Installing Claude defaults patch..."
cat > "$INSTALL_DIR/initialize_claude_patch.py" << 'PYEOF'
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

INIT_FILE="$INSTALL_DIR/initialize.py"
if ! grep -q "initialize_claude_patch" "$INIT_FILE" 2>/dev/null; then
  TMP=$(mktemp)
  echo "import initialize_claude_patch" > "$TMP"
  cat "$INIT_FILE" >> "$TMP"
  mv "$TMP" "$INIT_FILE"
  log "initialize.py patched."
fi

# 9. API key
echo ""
echo -e "${BOLD}${CYAN}[?] Enter your Anthropic API key (sk-ant-...):${NC}"
read -r -s ANTHROPIC_KEY
echo ""

# 10. .env
log "Writing .env..."
cat > "$INSTALL_DIR/.env" << EOF
API_KEY_ANTHROPIC=${ANTHROPIC_KEY}
API_KEY_OPENAI=
API_KEY_GROQ=
API_KEY_GOOGLE=
WEB_UI_PORT=${PORT}
WEB_UI_HOST=127.0.0.1
A0_CHAT_MODEL_PROVIDER=anthropic
A0_CHAT_MODEL_NAME=claude-sonnet-4-5
A0_UTILITY_MODEL_PROVIDER=anthropic
A0_UTILITY_MODEL_NAME=claude-sonnet-4-5
A0_EMBED_MODEL_PROVIDER=huggingface
A0_EMBED_MODEL_NAME=sentence-transformers/all-MiniLM-L6-v2
EOF

# 11. Launcher
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

# 12. Tailscale
echo ""
echo -e "${BOLD}${CYAN}[?] Install Tailscale for remote access? [y/N]${NC}"
read -r TAILSCALE
if [[ "$TAILSCALE" =~ ^[Yy]$ ]]; then
  log "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  sudo tailscale up
  TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "run: tailscale ip")
  log "Tailscale IP: $TAILSCALE_IP"
  log "Access from other devices: http://${TAILSCALE_IP}:${PORT}"
fi

# Done
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════╗"
echo -e "║   ✅  Installation Complete!          ║"
echo -e "╚══════════════════════════════════════╝${NC}"
echo ""
echo -e " ${CYAN}Start:${NC} cd ~/agent-zero && ./start.sh"
echo -e " ${CYAN}Browser:${NC} http://localhost:${PORT}"
echo -e " ${CYAN}CLI:${NC} cd ~/agent-zero && source .venv/bin/activate && python run_cli.py"
echo -e " ${YELLOW}Model: Claude claude-sonnet-4-5${NC}"
echo ""
