"""
initialize_claude_patch.py
──────────────────────────
Auto-injected by install_kali.sh.
Forces Claude claude-sonnet-4-5 as the default model for Agent Zero
when no other model is explicitly configured in settings.
"""

import os


def apply_claude_defaults():
    """
    Set environment variables Agent Zero reads for model configuration.
    Uses os.environ.setdefault so user overrides in .env are respected.
    """
    defaults = {
        # Primary conversational model
        "A0_CHAT_MODEL_PROVIDER":    "anthropic",
        "A0_CHAT_MODEL_NAME":        "claude-sonnet-4-5",
        # Utility / summarization (same model for quality)
        "A0_UTILITY_MODEL_PROVIDER": "anthropic",
        "A0_UTILITY_MODEL_NAME":     "claude-sonnet-4-5",
        # Local embedding model — no API key required
        "A0_EMBED_MODEL_PROVIDER":   "huggingface",
        "A0_EMBED_MODEL_NAME":       "sentence-transformers/all-MiniLM-L6-v2",
    }
    for key, value in defaults.items():
        os.environ.setdefault(key, value)


apply_claude_defaults()
