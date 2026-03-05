# Agent Zero — Kali Linux Setup (No Docker)
### Default model: Claude claude-sonnet-4-5

---

## Quick Start

```bash
# 1. Download the installer
chmod +x install_kali.sh

# 2. Run it (one command, sets everything up)
./install_kali.sh

# 3. Start Agent Zero
cd ~/agent-zero && ./start.sh

# 4. Open browser
# http://localhost:5000
```

That's it. Nothing else to configure.

---

## What the installer does

| Step | Action |
|------|--------|
| 1 | Checks Python 3.11+, installs 3.12 if needed |
| 2 | Installs system deps (`git`, `chromium`, `build-essential`, etc.) |
| 3 | Clones Agent Zero from GitHub |
| 4 | Creates a Python virtual environment |
| 5 | Installs all Python requirements |
| 6 | Prompts for your Anthropic API key (stored in `.env`) |
| 7 | Writes pre-configured `.env` with Claude claude-sonnet-4-5 as default |
| 8 | Patches `initialize.py` to load Claude defaults |
| 9 | Creates `start.sh` launcher |
| 10 | (Optional) Installs systemd user service for auto-start |

---

## Files included

| File | Purpose |
|------|---------|
| `install_kali.sh` | Main installer — run this |
| `example.env` | Pre-filled `.env` template (installer auto-generates the real one) |
| `initialize_claude_patch.py` | Drop into `~/agent-zero/` — sets Claude as default model |

---

## Manual setup (if you prefer not to run the installer)

```bash
# Clone
git clone https://github.com/agent0ai/agent-zero.git ~/agent-zero
cd ~/agent-zero

# Virtual env
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Copy files
cp /path/to/example.env .env
# Edit .env and add your API key:
nano .env   # replace sk-ant-YOUR_KEY_HERE

cp /path/to/initialize_claude_patch.py .
# Add this line to the TOP of initialize.py:
# import initialize_claude_patch

# Run
python run_ui.py --port 5000 --host 127.0.0.1
```

---

## Changing the model

Edit `~/agent-zero/.env`:

```bash
# To use Claude Opus instead:
A0_CHAT_MODEL_NAME=claude-opus-4-5

# To use a local Ollama model instead:
A0_CHAT_MODEL_PROVIDER=ollama
A0_CHAT_MODEL_NAME=llama3
```

Or change it live in the Agent Zero web UI under **Settings → Model**.

---

## Notes for ethical hacking use

- Agent Zero runs with **your user's full permissions** — no Docker sandbox
- It can execute terminal commands, run scripts, access the filesystem
- Great for automating recon, running tools (nmap, gobuster, etc.), CTF work
- **Only use in controlled environments / your own lab**
- Consider creating a dedicated Kali user with limited permissions for Agent Zero

---

## Troubleshooting

**Port already in use:**
```bash
# Change port in .env
WEB_UI_PORT=8080
# Then restart
```

**API key errors:**
```bash
cat ~/agent-zero/.env  # verify key is set correctly
```

**Requirements install fails:**
```bash
source ~/agent-zero/.venv/bin/activate
pip install -r requirements.txt --break-system-packages
```
