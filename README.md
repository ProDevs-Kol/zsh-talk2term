# 🧠 zsh-talk2term

> Use plain English in your terminal — and let AI convert it to safe, executable shell commands.

`zsh-talk2term` is a ZSH plugin for [Talk2Term](https://talk2term.prodevs.in), allowing you to type natural language prompts like:

```bash
t2t find all png files with "logo" in the current directory
```

Or unlock deeper capabilities using:

```bash
t2t-p deploy a Flask app to Heroku
```

It instantly returns the equivalent shell command and asks for your confirmation before executing.

---

## 🚀 Installation

> **Full installation guide:** See [INSTALL.md](INSTALL.md) for all methods (Oh My Zsh, Antigen, Zinit, zplug, Sheldon, Homebrew, Manual, WSL).

### Pinned installer (recommended)

Review the script, check the checksum, then run it. Tag: `v1.2.0`.

- Script: [install.sh at v1.2.0](https://github.com/ProDevs-Kol/zsh-talk2term/blob/v1.2.0/install.sh)
- sha256: `13d0869d13d58671b5fe4c8e14f7e07e1e65df7fd21dac7764f1759a8fed4c80`

```sh
curl -fsSL -o /tmp/talk2term-install.sh https://raw.githubusercontent.com/prodevs-kol/zsh-talk2term/v1.2.0/install.sh
echo "13d0869d13d58671b5fe4c8e14f7e07e1e65df7fd21dac7764f1759a8fed4c80  /tmp/talk2term-install.sh" | shasum -a 256 -c -   # macOS
# Linux: echo "13d0869d13d58671b5fe4c8e14f7e07e1e65df7fd21dac7764f1759a8fed4c80  /tmp/talk2term-install.sh" | sha256sum -c -
sh /tmp/talk2term-install.sh
```

Oh My Zsh is optional. Without it, the installer clones into `~/.zsh/talk2term`.

---

## 🔑 API Key Setup

To use this plugin, you need an API key from [Talk2Term](https://talk2term.prodevs.in/):

1. Log in at [https://talk2term.prodevs.in/](https://talk2term.prodevs.in/) with the magic-link email.
2. Open [https://talk2term.prodevs.in/profile](https://talk2term.prodevs.in/profile), generate a key if you do not have one, and copy it.
3. Save the key and run a command:

   ```sh
   echo "YOUR_API_KEY_HERE" > ~/.talk2term && chmod 600 ~/.talk2term
   source ~/.zshrc
   t2t list files
   ```

The installer finishes in a few seconds. The first `t2t` command waits on the API. Two to four minutes is typical. Success prints a translated command and `Execute? (y/n):`. The command text can differ. `ls` is typical for `t2t list files`. Answer `n` to cancel. Nothing runs until you answer `y`.

If `~/.talk2term` is missing, `t2t` prints an error and exits non-zero.

> **Note:** Keep your API key secure. Do not share it publicly.

---

### ⚙️ Manual Installation

1. **Clone the plugin**

```bash
git clone --depth 1 --branch v1.2.0 https://github.com/prodevs-kol/zsh-talk2term.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/talk2term
```

No Oh My Zsh:

```bash
git clone --depth 1 --branch v1.2.0 https://github.com/prodevs-kol/zsh-talk2term.git ~/.zsh/talk2term
printf '\n# Talk2Term ZSH Plugin\nsource "%s/talk2term.plugin.zsh"\n' "$HOME/.zsh/talk2term" >> ~/.zshrc
```

2. **Add to your `.zshrc`** (Oh My Zsh only; the no-Oh-My-Zsh clone above already appends a `source` line)

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
| `t2t <prompt>`   | Lite | Free daily credits | Simple, everyday shell tasks         |
| `t2t-p <prompt>` | Pro  | Paid credits       | Advanced, complex, or risky commands |

### Example:

```bash
t2t show running docker containers
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

* ZSH 5.8+
* `curl`, `jq`, and `git`
* Oh My Zsh is optional
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
* Prompts go to Talk2Term at talk2term.prodevs.in. You confirm every command before it runs.

---

## 📄 License

MIT © [ProDevs](https://prodevs.in)

