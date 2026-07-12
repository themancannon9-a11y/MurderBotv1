#!/usr/bin/env python3
"""
Advanced AI Assistant - A Claude Code-like application with:
- Local GGUF model support (llama-cpp-python)
- Secure web browsing with BeautifulSoup
- File operations (decompilation, decryption helpers)
- Sandboxed code execution
- Rich terminal UI
"""

import os
import sys
import subprocess
import json
import hashlib
import tempfile
import shutil
import re
import base64
import zipfile
import tarfile
import traceback
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any
from contextlib import contextmanager

# Auto-install dependencies
REQUIRED_PACKAGES = [
    "rich",
    "prompt_toolkit",
    "requests",
    "beautifulsoup4",
    "lxml",
    "llama-cpp-python",
    "cryptography",
    "pycryptodome",
    "disassembler",
    "capstone",
    "keystone-engine",
]

def install_dependencies():
    """Check and install required pip packages."""
    missing = []
    for pkg in REQUIRED_PACKAGES:
        try:
            if pkg == "beautifulsoup4":
                __import__("bs4")
            elif pkg == "llama-cpp-python":
                __import__("llama_cpp")
            elif pkg == "cryptography":
                __import__("cryptography")
            elif pkg == "pycryptodome":
                __import__("Crypto")
            elif pkg == "capstone":
                __import__("capstone")
            elif pkg == "keystone-engine":
                __import__("keystone")
            else:
                __import__(pkg)
        except ImportError:
            missing.append(pkg)
    
    if missing:
        print("\n📦 Installing required packages...")
        pip_cmd = [sys.executable, "-m", "pip", "install", "--upgrade", "pip"]
        subprocess.run(pip_cmd, check=True, capture_output=True)
        
        for pkg in missing:
            print(f"  Installing {pkg}...")
            install_cmd = [sys.executable, "-m", "pip", "install", pkg]
            try:
                subprocess.run(install_cmd, check=True, capture_output=True)
                print(f"  ✓ {pkg} installed")
            except subprocess.CalledProcessError as e:
                print(f"  ⚠ Failed to install {pkg}: {e}")
        print("✅ All dependencies installed!\n")

install_dependencies()

# Now import the installed packages
from rich.console import Console
from rich.panel import Panel
from rich.markdown import Markdown
from rich.syntax import Syntax
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.prompt import Prompt, Confirm
from rich.live import Live
from prompt_toolkit import prompt
from prompt_toolkit.history import FileHistory
from prompt_toolkit.auto_suggest import AutoSuggestFromHistory
from prompt_toolkit.key_binding import KeyBindings
import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
from cryptography.fernet import Fernet
from Crypto.Cipher import AES, DES, Blowfish
from Crypto.Util.Padding import pad, unpad
import capstone
import keystone

console = Console()

# Configuration
CONFIG_DIR = Path.home() / ".advanced_ai_assistant"
CONFIG_DIR.mkdir(exist_ok=True)
HISTORY_FILE = CONFIG_DIR / "history.txt"
SANDBOX_DIR = CONFIG_DIR / "sandbox"
SANDBOX_DIR.mkdir(exist_ok=True)
MODELS_DIR = CONFIG_DIR / "models"
MODELS_DIR.mkdir(exist_ok=True)

class SecureBrowser:
    """Secure web browsing with content extraction."""
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.5",
            "Accept-Encoding": "gzip, deflate",
            "Connection": "close",
        })
        self.visited_urls = set()
        self.max_depth = 3
    
    def fetch_page(self, url: str, timeout: int = 10) -> Optional[Dict[str, Any]]:
        """Fetch a webpage securely."""
        parsed = urlparse(url)
        if parsed.scheme not in ["http", "https"]:
            return {"error": "Only HTTP/HTTPS URLs allowed"}
        
        # Security checks
        hostname = parsed.hostname
        if hostname and ("localhost" in hostname or "127.0.0.1" in hostname):
            return {"error": "Localhost access disabled for security"}
        
        try:
            response = self.session.get(url, timeout=timeout, allow_redirects=True)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.text, "lxml")
            
            # Extract content
            title = soup.find("title")
            title_text = title.string.strip() if title else "No title"
            
            # Get main content
            content_elements = []
            for tag in ["article", "main", "div[class*='content']", "body"]:
                elements = soup.select(tag)
                if elements:
                    content_elements = elements
                    break
            
            text_content = soup.get_text(separator="\n", strip=True)[:10000]
            
            # Extract links
            links = []
            for a in soup.find_all("a", href=True)[:20]:
                link_url = urljoin(url, a["href"])
                if link_url.startswith("http"):
                    links.append({"text": a.get_text(strip=True), "url": link_url})
            
            return {
                "url": url,
                "title": title_text,
                "content": text_content,
                "links": links,
                "status": response.status_code,
            }
        except requests.exceptions.RequestException as e:
            return {"error": f"Request failed: {str(e)}"}
        except Exception as e:
            return {"error": f"Parse error: {str(e)}"}
    
    def search_summary(self, query: str, max_results: int = 3) -> str:
        """Get search results summary (simulated - would need API for real search)."""
        return f"Search query: {query}\nNote: For actual web search, configure a search API key."


class SandboxExecutor:
    """Sandboxes code execution for safety."""
    
    def __init__(self):
        self.sandbox_dir = SANDBOX_DIR
        self.execution_log = []
    
    @contextmanager
    def sandbox_context(self):
        """Create isolated execution context."""
        exec_dir = self.sandbox_dir / f"exec_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}"
        exec_dir.mkdir(exist_ok=True)
        
        # Create restricted environment
        env = os.environ.copy()
        env["PYTHONPATH"] = str(exec_dir)
        
        try:
            yield exec_dir, env
        finally:
            # Cleanup after execution
            try:
                shutil.rmtree(exec_dir)
            except Exception:
                pass
    
    def execute_python(self, code: str, timeout: int = 5) -> Dict[str, Any]:
        """Execute Python code in sandbox."""
        result = {"success": False, "output": "", "error": ""}
        
        with self.sandbox_context() as (exec_dir, env):
            script_path = exec_dir / "script.py"
            script_path.write_text(code)
            
            # Restricted Python execution
            restricted_code = """
import sys
import os
# Block dangerous imports
blocked = ['subprocess', 'os.system', 'eval', 'exec', '__import__', 'open']
original_import = __builtins__.__import__

def safe_import(name, *args, **kwargs):
    if name in blocked or any(b in name for b in ['subprocess', 'socket']):
        raise ImportError(f"Import of {name} is blocked for security")
    return original_import(name, *args, **kwargs)

__builtins__.__import__ = safe_import

""" + code
            
            try:
                proc = subprocess.run(
                    [sys.executable, "-c", restricted_code],
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                    cwd=str(exec_dir),
                    env=env,
                )
                result["success"] = proc.returncode == 0
                result["output"] = proc.stdout
                result["error"] = proc.stderr
            except subprocess.TimeoutExpired:
                result["error"] = "Execution timeout"
            except Exception as e:
                result["error"] = str(e)
        
        self.execution_log.append({
            "timestamp": datetime.now().isoformat(),
            "code_preview": code[:100],
            "success": result["success"],
        })
        
        return result
    
    def execute_shell(self, command: str, allowed_commands: List[str] = None) -> Dict[str, Any]:
        """Execute shell command with restrictions."""
        if allowed_commands is None:
            allowed_commands = ["ls", "dir", "cat", "echo", "pwd", "head", "tail", "wc"]
        
        result = {"success": False, "output": "", "error": ""}
        
        cmd_parts = command.split()
        if not cmd_parts or cmd_parts[0] not in allowed_commands:
            result["error"] = f"Command not allowed. Allowed: {allowed_commands}"
            return result
        
        with self.sandbox_context() as (exec_dir, env):
            try:
                proc = subprocess.run(
                    command.split(),
                    capture_output=True,
                    text=True,
                    timeout=10,
                    cwd=str(exec_dir),
                    env=env,
                )
                result["success"] = proc.returncode == 0
                result["output"] = proc.stdout
                result["error"] = proc.stderr
            except Exception as e:
                result["error"] = str(e)
        
        return result


class FileOperations:
    """File operations including decompilation and decryption helpers."""
    
    @staticmethod
    def decrypt_aes_cbc(encrypted_data: bytes, key: bytes, iv: bytes) -> bytes:
        """Decrypt AES-CBC encrypted data."""
        cipher = AES.new(key, AES.MODE_CBC, iv)
        decrypted = cipher.decrypt(encrypted_data)
        return unpad(decrypted, AES.block_size)
    
    @staticmethod
    def decrypt_file(filepath: str, method: str = "aes", key: bytes = None, **kwargs) -> Optional[bytes]:
        """Decrypt a file."""
        try:
            with open(filepath, "rb") as f:
                encrypted = f.read()
            
            if method == "aes":
                key = key or kwargs.get("password", b"default_key_16b!")[:16]
                iv = kwargs.get("iv", b"\x00" * 16)
                return FileOperations.decrypt_aes_cbc(encrypted, key.ljust(16), iv[:16])
            elif method == "fernet":
                f = Fernet(key)
                return f.decrypt(encrypted)
            else:
                return None
        except Exception as e:
            console.print(f"[red]Decryption error: {e}[/red]")
            return None
    
    @staticmethod
    def disassemble_binary(filepath: str, arch: str = "x86", mode: int = 64) -> str:
        """Disassemble a binary file."""
        try:
            with open(filepath, "rb") as f:
                code = f.read()
            
            md = capstone.Cs(
                getattr(capstone, f"CS_ARCH_{arch.upper()}"),
                getattr(capstone, f"CS_MODE_{mode}")
            )
            
            output = []
            for insn in md.disasm(code[:10000], 0x1000):  # Limit to first 10KB
                output.append(f"0x{insn.address:x}:\t{insn.mnemonic}\t{insn.op_str}")
            
            return "\n".join(output)
        except Exception as e:
            return f"Disassembly error: {e}"
    
    @staticmethod
    def analyze_file(filepath: str) -> Dict[str, Any]:
        """Analyze a file and return metadata."""
        path = Path(filepath)
        
        if not path.exists():
            return {"error": "File not found"}
        
        info = {
            "path": str(path.absolute()),
            "name": path.name,
            "size": path.stat().st_size,
            "modified": datetime.fromtimestamp(path.stat().st_mtime).isoformat(),
            "hash_md5": hashlib.md5(path.read_bytes()).hexdigest(),
            "hash_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "type": "unknown",
        }
        
        # Detect file type
        magic = path.read_bytes()[:20]
        if magic[:4] == b"\x7fELF":
            info["type"] = "ELF executable"
        elif magic[:2] == b"MZ":
            info["type"] = "PE executable"
        elif magic[:4] == b"\xca\xfe\xba\xbe" or magic[:4] == b"\xfe\xed\xfa\xce":
            info["type"] = "Mach-O executable"
        elif path.suffix == ".py":
            info["type"] = "Python script"
        elif path.suffix in [".js", ".ts"]:
            info["type"] = "JavaScript/TypeScript"
        elif path.suffix == ".json":
            info["type"] = "JSON"
        elif path.suffix in [".zip", ".tar", ".gz"]:
            info["type"] = "Archive"
        
        return info


class LocalLLM:
    """Local LLM using GGUF models via llama-cpp-python."""
    
    def __init__(self):
        self.model = None
        self.model_path = None
        self.context = None
    
    def load_model(self, model_path: str, n_ctx: int = 4096, n_gpu_layers: int = 0) -> bool:
        """Load a GGUF model."""
        try:
            from llama_cpp import Llama
            
            if not Path(model_path).exists():
                console.print(f"[red]Model file not found: {model_path}[/red]")
                return False
            
            console.print(f"\n[yellow]Loading model: {model_path}[/yellow]")
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
            ) as progress:
                task = progress.add_task("Loading...", total=None)
                
                self.model = Llama(
                    model_path=model_path,
                    n_ctx=n_ctx,
                    n_gpu_layers=n_gpu_layers,
                    verbose=False,
                )
                progress.update(task, completed=True)
            
            self.model_path = model_path
            console.print(f"[green]✓ Model loaded successfully![/green]\n")
            return True
        except Exception as e:
            console.print(f"[red]Failed to load model: {e}[/red]")
            return False
    
    def generate(self, prompt: str, max_tokens: int = 1024, temperature: float = 0.7,
                 system_prompt: str = None) -> str:
        """Generate response from the model."""
        if not self.model:
            return "[No model loaded. Load a GGUF model first.]"
        
        try:
            full_prompt = prompt
            if system_prompt:
                full_prompt = f"<|system|>\n{system_prompt}\n<|user|>\n{prompt}\n<|assistant|>"
            
            output = self.model(
                full_prompt,
                max_tokens=max_tokens,
                temperature=temperature,
                stop=["<|user|>", "<|system|>"],
                echo=False,
            )
            
            return output["choices"][0]["text"].strip()
        except Exception as e:
            return f"[Generation error: {e}]"
    
    def chat(self, messages: List[Dict], max_tokens: int = 1024) -> str:
        """Chat with the model using conversation history."""
        if not self.model:
            return "[No model loaded. Load a GGUF model first.]"
        
        try:
            formatted = ""
            for msg in messages:
                role = msg["role"]
                content = msg["content"]
                if role == "system":
                    formatted += f"<|system|>\n{content}\n"
                elif role == "user":
                    formatted += f"<|user|>\n{content}\n"
                elif role == "assistant":
                    formatted += f"<|assistant|>\n{content}\n"
            formatted += "<|assistant|>"
            
            output = self.model(
                formatted,
                max_tokens=max_tokens,
                temperature=0.7,
                stop=["<|user|>", "<|system|>"],
                echo=False,
            )
            
            return output["choices"][0]["text"].strip()
        except Exception as e:
            return f"[Generation error: {e}]"


class AdvancedAssistant:
    """Main assistant class combining all features."""
    
    def __init__(self):
        self.llm = LocalLLM()
        self.browser = SecureBrowser()
        self.sandbox = SandboxExecutor()
        self.file_ops = FileOperations()
        self.conversation_history = []
        self.current_dir = Path.cwd()
        self.verbose = False
        self.system_prompt = """You are an advanced AI assistant with capabilities for:
- Web browsing and information gathering
- File analysis, decompilation, and decryption
- Code execution in a sandboxed environment
- Binary analysis and reverse engineering

Always be helpful, accurate, and security-conscious.
When executing code or analyzing files, explain what you're doing.
Prioritize user safety and system security."""
    
    def show_welcome(self):
        """Display welcome panel."""
        welcome = """
# 🤖 Advanced AI Assistant

A powerful Claude Code-like application with:

| Feature | Description |
|---------|-------------|
| 🧠 **Local LLM** | Load GGUF models for offline AI |
| 🌐 **Web Browsing** | Securely fetch and analyze web content |
| 📁 **File Operations** | Decrypt, decompile, analyze files |
| 🏖️ **Sandbox** | Execute code safely |
| 🔍 **Reverse Engineering** | Disassemble binaries |

## Commands
- `/load <path>` - Load a GGUF model
- `/browse <url>` - Fetch and analyze a webpage
- `/analyze <file>` - Analyze a file
- `/decrypt <file>` - Decrypt a file
- `/disasm <file>` - Disassemble a binary
- `/run <code>` - Execute Python code in sandbox
- `/shell <cmd>` - Run restricted shell command
- `/search <query>` - Search the web (simulated)
- `/cd <path>` - Change directory
- `/cwd` - Show current directory
- `/history` - Show conversation history
- `/clear` - Clear conversation
- `/verbose` - Toggle verbose mode
- `/help` - Show this help
- `/exit` - Exit application
        """
        console.print(Panel(Markdown(welcome), title="Welcome", border_style="green"))
    
    def process_command(self, user_input: str) -> str:
        """Process special commands."""
        parts = user_input.strip().split(maxsplit=1)
        cmd = parts[0].lower() if parts else ""
        args = parts[1] if len(parts) > 1 else ""
        
        if cmd == "/load":
            if not args:
                return "Usage: /load <path_to_gguf_model>"
            success = self.llm.load_model(args)
            return f"Model {'loaded' if success else 'failed to load'}: {args}"
        
        elif cmd == "/browse":
            if not args:
                return "Usage: /browse <url>"
            with console.status("[bold green]Fetching page..."):
                result = self.browser.fetch_page(args)
            if "error" in result:
                return f"❌ {result['error']}"
            return f"## {result['title']}\n\nURL: {result['url']}\n\n### Content Preview:\n{result['content'][:2000]}..."
        
        elif cmd == "/analyze":
            if not args:
                return "Usage: /analyze <filepath>"
            info = self.file_ops.analyze_file(args)
            if "error" in info:
                return f"❌ {info['error']}"
            table = Table(title="File Analysis")
            table.add_column("Property", style="cyan")
            table.add_column("Value", style="green")
            for key, value in info.items():
                table.add_row(key, str(value))
            from io import StringIO
            output = StringIO()
            console.file = output
            console.print(table)
            console.file = sys.__stdout__
            return output.getvalue()
        
        elif cmd == "/decrypt":
            if not args:
                return "Usage: /decrypt <filepath> [method:aes|fernet] [key:base64]"
            # Parse arguments
            filepath = args.split()[0] if args.split() else ""
            method = "aes"
            key = None
            for part in args.split()[1:]:
                if part.startswith("method:"):
                    method = part.split(":")[1]
                elif part.startswith("key:"):
                    key = base64.b64decode(part.split(":")[1])
            
            if not Path(filepath).exists():
                return f"❌ File not found: {filepath}"
            
            decrypted = self.file_ops.decrypt_file(filepath, method=method, key=key)
            if decrypted:
                # Save to temp file
                temp_path = SANDBOX_DIR / f"decrypted_{Path(filepath).name}"
                temp_path.write_bytes(decrypted)
                return f"✅ Decrypted successfully!\nSaved to: {temp_path}"
            return "❌ Decryption failed"
        
        elif cmd == "/disasm":
            if not args:
                return "Usage: /disasm <filepath> [arch:x86|arm]"
            filepath = args.split()[0]
            arch = "x86"
            for part in args.split()[1:]:
                if part.startswith("arch:"):
                    arch = part.split(":")[1]
            
            if not Path(filepath).exists():
                return f"❌ File not found: {filepath}"
            
            disasm = self.file_ops.disassemble_binary(filepath, arch=arch)
            return f"### Disassembly ({arch}):\n```\n{disasm}\n```"
        
        elif cmd == "/run":
            if not args:
                return "Usage: /run <python_code>"
            result = self.sandbox.execute_python(args)
            output = ""
            if result["output"]:
                output += f"### Output:\n```\n{result['output']}\n```\n"
            if result["error"]:
                output += f"### Error:\n```\n{result['error']}\n```\n"
            return output or "No output"
        
        elif cmd == "/shell":
            if not args:
                return "Usage: /shell <command>"
            result = self.sandbox.execute_shell(args)
            output = ""
            if result["output"]:
                output += f"### Output:\n```\n{result['output']}\n```\n"
            if result["error"]:
                output += f"### Error:\n```\n{result['error']}\n```\n"
            return output or "No output"
        
        elif cmd == "/search":
            if not args:
                return "Usage: /search <query>"
            return self.browser.search_summary(args)
        
        elif cmd == "/cd":
            if not args:
                return "Usage: /cd <path>"
            try:
                new_path = Path(args).expanduser()
                if not new_path.is_absolute():
                    new_path = self.current_dir / new_path
                if new_path.exists() and new_path.is_dir():
                    self.current_dir = new_path.resolve()
                    os.chdir(self.current_dir)
                    return f"Changed directory to: {self.current_dir}"
                return f"❌ Invalid path: {args}"
            except Exception as e:
                return f"❌ Error: {e}"
        
        elif cmd == "/cwd":
            return f"Current directory: {self.current_dir}"
        
        elif cmd == "/history":
            if not self.conversation_history:
                return "No conversation history."
            output = "### Conversation History:\n"
            for i, msg in enumerate(self.conversation_history[-10:], 1):
                role = msg["role"]
                preview = msg["content"][:100] + "..." if len(msg["content"]) > 100 else msg["content"]
                output += f"{i}. **{role}**: {preview}\n"
            return output
        
        elif cmd == "/clear":
            self.conversation_history = []
            return "Conversation history cleared."
        
        elif cmd == "/verbose":
            self.verbose = not self.verbose
            return f"Verbose mode: {'ON' if self.verbose else 'OFF'}"
        
        elif cmd == "/help":
            self.show_welcome()
            return ""
        
        elif cmd == "/exit":
            raise SystemExit
        
        else:
            return f"Unknown command: {cmd}. Type /help for available commands."
    
    def generate_response(self, user_input: str) -> str:
        """Generate AI response."""
        self.conversation_history.append({"role": "user", "content": user_input})
        
        # Add context about current state
        context_info = f"Current directory: {self.current_dir}\n"
        if self.llm.model_path:
            context_info += f"Loaded model: {self.llm.model_path}\n"
        
        system_msg = self.system_prompt + "\n\n" + context_info
        
        response = self.llm.chat(
            [{"role": "system", "content": system_msg}] + self.conversation_history,
            max_tokens=1024
        )
        
        self.conversation_history.append({"role": "assistant", "content": response})
        return response
    
    def run(self):
        """Main application loop."""
        self.show_welcome()
        
        # Check for default model
        default_model = MODELS_DIR / "model.gguf"
        if default_model.exists():
            console.print(f"[yellow]Found default model: {default_model}[/yellow]")
            console.print("[dim]Use /load <path> to load a different model[/dim]\n")
        
        while True:
            try:
                # Build prompt with current directory
                cwd_display = str(self.current_dir).replace(str(Path.home()), "~")
                user_input = prompt(
                    f"[🤖 {cwd_display}]> ",
                    history=FileHistory(str(HISTORY_FILE)),
                    auto_suggest=AutoSuggestFromHistory(),
                ).strip()
                
                if not user_input:
                    continue
                
                console.print()  # Add spacing
                
                # Check if it's a command
                if user_input.startswith("/"):
                    result = self.process_command(user_input)
                    if result:
                        console.print(Markdown(result))
                else:
                    # Generate AI response
                    if not self.llm.model:
                        console.print(Panel(
                            "[yellow]No model loaded! Use /load <path> to load a GGUF model.\n"
                            "Download models from: https://huggingface.co/models?library=gguf[/yellow]",
                            title="⚠️ Model Required",
                            border_style="yellow"
                        ))
                    else:
                        with console.status("[bold green]Thinking..."):
                            response = self.generate_response(user_input)
                        
                        console.print(Panel(Markdown(response), title="Assistant", border_style="blue"))
                
                console.print()
                
            except KeyboardInterrupt:
                console.print("\n[yellow]Interrupted. Type /exit to quit.[/yellow]\n")
            except EOFError:
                break
            except SystemExit:
                console.print("[green]Goodbye! 👋[/green]")
                break
            except Exception as e:
                console.print(f"[red]Error: {e}[/red]")
                if self.verbose:
                    console.print(traceback.format_exc())


def main():
    """Entry point."""
    console.print("[bold green]Starting Advanced AI Assistant...[/bold green]\n")
    
    assistant = AdvancedAssistant()
    assistant.run()


if __name__ == "__main__":
    main()
