#!/usr/bin/env python3
"""
Claude Code-like Terminal Assistant

A terminal-based AI coding assistant similar to Claude Code.
This script will automatically install required dependencies on first run.
"""

import subprocess
import sys
import os

# Required packages
REQUIRED_PACKAGES = [
    "rich",
    "prompt_toolkit",
    "requests",
]

def check_and_install_packages():
    """Check for required packages and install them if missing."""
    print("🔍 Checking dependencies...")
    
    missing_packages = []
    for package in REQUIRED_PACKAGES:
        try:
            __import__(package)
        except ImportError:
            missing_packages.append(package)
    
    if missing_packages:
        print(f"📦 Installing missing packages: {', '.join(missing_packages)}")
        python_executable = sys.executable
        subprocess.check_call([
            python_executable, "-m", "pip", "install", 
            "--quiet", *missing_packages
        ])
        print("✅ All dependencies installed!")
    else:
        print("✅ All dependencies are up to date!")
    
    print()

# Install dependencies before importing other modules
check_and_install_packages()

# Now import the rest of the modules
from rich.console import Console
from rich.panel import Panel
from rich.markdown import Markdown
from rich.syntax import Syntax
from rich.live import Live
from rich.text import Text
from rich.spinner import Spinner
from prompt_toolkit import prompt
from prompt_toolkit.history import FileHistory
from prompt_toolkit.auto_suggest import AutoSuggestFromHistory
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.formatted_text import HTML
import requests
import json
import re

console = Console()

# Configuration
HISTORY_FILE = os.path.expanduser("~/.claude_code_like_history")
API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

bindings = KeyBindings()

@bindings.add('c-m')
def _(event):
    event.current_buffer.validate_and_handle()

@bindings.add('escape', 'enter')
def _(event):
    event.current_buffer.insert_text('\n')

class ClaudeCodeLike:
    """A Claude Code-like terminal assistant."""
    
    def __init__(self):
        self.conversation_history = []
        self.current_directory = os.getcwd()
        self.verbose = False
        
    def get_system_prompt(self):
        """Return the system prompt for the assistant."""
        return """You are an expert coding assistant running in a terminal environment. 
You help users with:
- Writing, reviewing, and debugging code
- Explaining programming concepts
- Suggesting best practices
- Answering technical questions
- Helping with shell commands and file operations

Always provide clear, concise, and accurate responses.
When showing code, use proper markdown formatting.
When suggesting commands, explain what they do."""

    def display_welcome(self):
        """Display welcome message."""
        welcome_text = """
╔═══════════════════════════════════════════════════════════╗
║           🤖 Claude Code-like Terminal Assistant          ║
╠═══════════════════════════════════════════════════════════╣
║  Type your questions or coding tasks                      ║
║  Use /help for available commands                         ║
║  Press Ctrl+C twice to exit                               ║
╚═══════════════════════════════════════════════════════════╝
"""
        console.print(Panel(welcome_text, style="bold blue"))
        console.print()

    def display_help(self):
        """Display help information."""
        help_text = """
**Available Commands:**

| Command | Description |
|---------|-------------|
| `/help` | Show this help message |
| `/clear` | Clear conversation history |
| `/cwd` | Show current working directory |
| `/cd <path>` | Change directory |
| `/verbose` | Toggle verbose mode |
| `/exit` | Exit the application |

**Tips:**
- Ask coding questions naturally
- Request code examples by saying "show me code for..."
- Ask for explanations of concepts
- Get help with debugging errors
"""
        console.print(Markdown(help_text))

    def handle_command(self, user_input):
        """Handle special commands."""
        cmd = user_input.strip().lower()
        
        if cmd == "/help":
            self.display_help()
            return True
            
        elif cmd == "/clear":
            self.conversation_history = []
            console.print("[green]Conversation history cleared.[/green]")
            return True
            
        elif cmd == "/cwd":
            console.print(f"[cyan]Current directory:[/cyan] {self.current_directory}")
            return True
            
        elif cmd.startswith("/cd "):
            path = user_input[4:].strip()
            try:
                os.chdir(path)
                self.current_directory = os.getcwd()
                console.print(f"[green]Changed directory to:[/green] {self.current_directory}")
            except Exception as e:
                console.print(f"[red]Error:[/red] {e}")
            return True
            
        elif cmd == "/verbose":
            self.verbose = not self.verbose
            status = "enabled" if self.verbose else "disabled"
            console.print(f"[cyan]Verbose mode {status}[/cyan]")
            return True
            
        elif cmd == "/exit":
            console.print("[yellow]Goodbye! 👋[/yellow]")
            return False
            
        return None  # Not a command

    def call_api(self, user_message):
        """Call the Anthropic API (placeholder - requires API key)."""
        if not API_KEY:
            return self.get_local_response(user_message)
        
        headers = {
            "Content-Type": "application/json",
            "x-api-key": API_KEY,
            "anthropic-version": "2023-06-01"
        }
        
        messages = self.conversation_history + [{"role": "user", "content": user_message}]
        
        payload = {
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "system": self.get_system_prompt(),
            "messages": messages
        }
        
        try:
            response = requests.post(
                "https://api.anthropic.com/v1/messages",
                headers=headers,
                json=payload,
                timeout=60
            )
            response.raise_for_status()
            data = response.json()
            assistant_message = data["content"][0]["text"]
            
            # Update conversation history
            self.conversation_history.append({"role": "user", "content": user_message})
            self.conversation_history.append({"role": "assistant", "content": assistant_message})
            
            return assistant_message
            
        except requests.exceptions.RequestException as e:
            return f"Error calling API: {e}"

    def get_local_response(self, user_message):
        """Provide local responses when no API key is set."""
        responses = {
            "hello": "Hello! I'm your Claude Code-like assistant. How can I help you with coding today?",
            "hi": "Hi there! Ready to help with any coding questions or tasks.",
            "help": "I can help you with coding questions, debugging, explaining concepts, and more. Just ask!",
        }
        
        lower_msg = user_message.lower()
        for key, response in responses.items():
            if key in lower_msg:
                return response
        
        return """I notice you haven't set an ANTHROPIC_API_KEY environment variable.

To get full AI responses:
1. Get an API key from https://console.anthropic.com
2. Set it: export ANTHROPIC_API_KEY=your_key_here
3. Restart this application

In the meantime, here are some things I can help with once configured:
- **Code generation**: Write code in any language
- **Debugging**: Help fix errors in your code
- **Explanations**: Explain programming concepts
- **Best practices**: Suggest improvements
- **Shell commands**: Help with terminal operations

Type /help for available commands."""

    def format_response(self, response):
        """Format the response for display."""
        # Extract code blocks
        code_pattern = r'```(\w+)?\n(.*?)```'
        matches = re.findall(code_pattern, response, re.DOTALL)
        
        if matches:
            parts = re.split(code_pattern, response, flags=re.DOTALL)
            for i, part in enumerate(parts):
                if i % 4 == 1:  # Language
                    continue
                elif i % 4 == 2:  # Code content
                    lang = parts[i-1] if i > 0 else "python"
                    if part.strip():
                        syntax = Syntax(part.strip(), lang or "python", theme="monokai", line_numbers=True)
                        console.print(Panel(syntax, title=f"📝 Code ({lang or 'python'})", style="green"))
                elif i % 4 == 0 and part.strip():  # Regular text
                    console.print(Markdown(part.strip()))
        else:
            console.print(Markdown(response))

    def run(self):
        """Main application loop."""
        self.display_welcome()
        
        while True:
            try:
                # Create prompt with directory indicator
                prompt_text = f"[bold green]{os.path.basename(self.current_directory)}[/bold green] [dim]›[/dim] "
                
                user_input = prompt(
                    HTML(prompt_text),
                    history=FileHistory(HISTORY_FILE),
                    auto_suggest=AutoSuggestFromHistory(),
                    key_bindings=bindings,
                    multiline=False,
                ).strip()
                
                if not user_input:
                    continue
                
                # Handle commands
                if user_input.startswith("/"):
                    result = self.handle_command(user_input)
                    if result is False:
                        break
                    continue
                
                # Show thinking indicator
                with console.status("[bold blue]Thinking...", spinner="dots"):
                    response = self.call_api(user_input)
                
                console.print()
                self.format_response(response)
                console.print()
                
            except KeyboardInterrupt:
                console.print("\n[yellow]Press Ctrl+C again to exit, or continue typing.[/yellow]")
                try:
                    # Wait for second Ctrl+C
                    prompt("", default="", read_only=True)
                except KeyboardInterrupt:
                    console.print("\n[yellow]Goodbye! 👋[/yellow]")
                    break
            except EOFError:
                break
            except Exception as e:
                console.print(f"[red]Error:[/red] {e}")


def main():
    """Entry point."""
    app = ClaudeCodeLike()
    app.run()


if __name__ == "__main__":
    main()
