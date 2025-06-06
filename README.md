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

### 🟢 Easy One-Liner (Recommended)

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/prodevs-kol/zsh-talk2term/main/install.sh)"
```

Paste this in your terminal to install the plugin instantly!

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

* ZSH (works great with Oh My Zsh)
* `curl` and `jq` installed
* Internet connection

---

## 💡 Why Use This?

* Stop Googling terminal commands — just describe what you want
* Smart fallback: confirm before execution
* Great for learners and pros alike
* Extendable and self-hosted — privacy-first

---

## 📄 License

MIT © [ProDevs](https://prodevs.in)
