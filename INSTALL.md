# Installation

## Prerequisites

- **ZSH** (5.8 or later)
- **curl** and **jq** (the plugin checks at load time and tells you how to install them)
- An API key from [talk2term.prodevs.in/profile](https://talk2term.prodevs.in/profile)

After installing, create your API key file:
```sh
echo "YOUR_API_KEY" > ~/.talk2term
```

---

## One-Liner (Recommended for Oh My Zsh users)

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/prodevs-kol/zsh-talk2term/main/install.sh)"
```

Then restart your shell: `source ~/.zshrc`

---

## Oh My Zsh

```sh
git clone --depth=1 https://github.com/prodevs-kol/zsh-talk2term ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/talk2term
```

Add to `~/.zshrc`:
```sh
plugins=(... talk2term)
```

Restart: `source ~/.zshrc`

---

## Antigen

Add to `~/.zshrc`:
```sh
antigen bundle prodevs-kol/zsh-talk2term
```

Restart: `source ~/.zshrc`

---

## Zinit

Add to `~/.zshrc`:
```sh
zinit light prodevs-kol/zsh-talk2term
```

For turbo mode (faster shell startup):
```sh
zinit ice wait lucid
zinit light prodevs-kol/zsh-talk2term
```

---

## zplug

Add to `~/.zshrc`:
```sh
zplug "prodevs-kol/zsh-talk2term"
```

Then run: `zplug install`

---

## Sheldon

Add to `~/.config/sheldon/plugins.toml`:
```toml
[plugins.talk2term]
github = "prodevs-kol/zsh-talk2term"
```

Then run: `sheldon lock --update`

---

## Manual (git clone)

```sh
git clone --depth=1 https://github.com/prodevs-kol/zsh-talk2term ~/.zsh/zsh-talk2term
```

Add to `~/.zshrc`:
```sh
source ~/.zsh/zsh-talk2term/talk2term.plugin.zsh
```

Restart: `source ~/.zshrc`

---

## Windows (WSL)

1. Install WSL: `wsl --install` (PowerShell as Admin)
2. Inside WSL, install ZSH: `sudo apt install zsh curl jq`
3. Set ZSH as default: `chsh -s $(which zsh)`
4. Follow the **Oh My Zsh** or **Manual** instructions above

---

## Updating

```sh
cd ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/talk2term && git pull
```

Or re-run the one-liner installer — it detects existing installations and updates them.
