# 🧠 zsh-talk2term

> Use plain English in your terminal — and let AI convert it to safe, executable shell commands.

`zsh-talk2term` is a ZSH plugin for [Talk2Term](https://talk2term.prodevs.in), allowing you to type natural language prompts like:

```bash
t2t: find all png files with "logo" in the current directory
```

Or unlock deeper capabilities using:

```bash
t2t-p: deploy a Flask app to Heroku
```

It instantly returns the equivalent shell command and asks for your confirmation before executing.

---

## 🚀 Installation

> **Full installation guide:** See [INSTALL.md](INSTALL.md) for all methods (Oh My Zsh, Antigen, Zinit, zplug, Sheldon, Homebrew, Manual, WSL).

### 🟢 Easy One-Liner (Recommended)

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/prodevs-kol/zsh-talk2term/main/install.sh)"
```

Paste this in your terminal to install the plugin instantly!

---

## 🔑 API Key Setup

To use this plugin, you need an API key from [Talk2Term](https://talk2term.prodevs.in/):

1. Sign up or log in at [https://talk2term.prodevs.in/](https://talk2term.prodevs.in/)
2. Go to your account or API section and generate/copy your API key.
3. Create a file at `~/.talk2term` in your home directory and paste your API key inside it:

   ```sh
   echo "YOUR_API_KEY_HERE" > ~/.talk2term
   ```

4. The plugin will automatically read your API key from this file.

> **Note:** Keep your API key secure. Do not share it publicly.

---

### ⚙️ Manual Installation

1. **Clone the plugin**

```bash
git clone https://github.com/prodevs-kol/zsh-talk2term.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/talk2term
```

2. **Add to your `.zshrc`**

```bash
plugins=(... talk2term)
```

3. **Reload your shell**

```bash
source ~/.zshrc
```

---

## ⚙️ Usage

| Prefix   | Plan | Cost               | Use Case                             |
| -------- | ---- | ------------------ | ------------------------------------ |
| `t2t:`   | Lite | Free daily credits | Simple, everyday shell tasks         |
| `t2t-p:` | Pro  | Paid credits       | Advanced, complex, or risky commands |

### Example:

```bash
t2t: show running docker containers
```

Response:

```bash
Translated Command:
docker ps
Execute? (y/n)
```

---

## 💳 Credits & Pricing

* **Lite credits** reset daily — use them freely for general queries.
* **Pro credits** are required for more advanced or critical tasks.
* You can **purchase additional credits** at:
  👉 [https://talk2term.prodevs.in](https://talk2term.prodevs.in)

---

## 🛡️ Safety & Confirmation

* You always see the final command before execution.
* You must confirm (`y`) before anything runs.
* No command will run without your explicit approval.

---

## ❗Requirements

* ZSH 5.8+ (works great with Oh My Zsh)
* `curl` and `jq` installed (the plugin checks at load time)
* Internet connection

### Platform Support

| Platform | Status |
|----------|--------|
| macOS | Fully supported |
| Linux (X11) | Fully supported |
| Linux (Wayland) | Fully supported (`wl-copy` for clipboard) |
| Windows (WSL2) | Fully supported |
| Windows (WSL1) | Supported |
| Windows (MSYS2) | Basic support |

---

## 💡 Why Use This?

* Stop Googling terminal commands — just describe what you want
* Smart fallback: confirm before execution
* Great for learners and pros alike
* Extendable and self-hosted — privacy-first

---

## 📄 License

MIT © [ProDevs](https://prodevs.in)

