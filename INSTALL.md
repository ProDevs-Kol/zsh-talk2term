# Installation

## Prerequisites

- **zsh** 5.8 or later
- **curl**
- **jq**
- **git**
- Oh My Zsh is optional. Without it, the installer uses `~/.zsh/talk2term`.

The installer does not log you in and does not write your API key. It only prints where to put the key.

---

## Pinned install

Review the script, check the checksum, then run it. Tag: `v1.2.0`.

- Script: [install.sh at v1.2.0](https://github.com/ProDevs-Kol/zsh-talk2term/blob/v1.2.0/install.sh)
- sha256: `13d0869d13d58671b5fe4c8e14f7e07e1e65df7fd21dac7764f1759a8fed4c80`

```sh
curl -fsSL -o /tmp/talk2term-install.sh https://raw.githubusercontent.com/prodevs-kol/zsh-talk2term/v1.2.0/install.sh
echo "13d0869d13d58671b5fe4c8e14f7e07e1e65df7fd21dac7764f1759a8fed4c80  /tmp/talk2term-install.sh" | shasum -a 256 -c -   # macOS
# Linux: echo "13d0869d13d58671b5fe4c8e14f7e07e1e65df7fd21dac7764f1759a8fed4c80  /tmp/talk2term-install.sh" | sha256sum -c -
sh /tmp/talk2term-install.sh
source ~/.zshrc
```

The installer finishes in a few seconds.

### Manual git clone

No Oh My Zsh:

```sh
git clone --depth 1 --branch v1.2.0 https://github.com/prodevs-kol/zsh-talk2term.git ~/.zsh/talk2term
printf '\n# Talk2Term ZSH Plugin\nsource "%s/talk2term.plugin.zsh"\n' "$HOME/.zsh/talk2term" >> ~/.zshrc
source ~/.zshrc
```

---

## After install

1. Log in at [https://talk2term.prodevs.in/](https://talk2term.prodevs.in/) with the magic-link email.
2. Open [https://talk2term.prodevs.in/profile](https://talk2term.prodevs.in/profile). Copy an API key. Use **Generate New API Key** if the list is empty.
3. Save the key and run a command:

```sh
echo 'YOUR_API_KEY' > ~/.talk2term && chmod 600 ~/.talk2term
t2t list files
```

The first `t2t` command often takes 2–4 minutes. That wait is the API. Success looks like this. The translated command can differ. `ls` is typical for `list files`:

```text
$ t2t list files

Translated Command:
  ls
Execute? (y/n):
```

Answer `n` to cancel. The command does not run until you answer `y`.

If `~/.talk2term` is missing, `t2t` prints an error and exits non-zero:

```text
[talk2term] API key file not found: /Users/you/.talk2term
  Create it with: echo 'YOUR_KEY' > /Users/you/.talk2term && chmod 600 /Users/you/.talk2term
```

---

## Oh My Zsh

```sh
git clone --depth 1 --branch v1.2.0 https://github.com/prodevs-kol/zsh-talk2term.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/talk2term
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
git clone --depth 1 --branch v1.2.0 https://github.com/prodevs-kol/zsh-talk2term.git ~/.zsh/talk2term
```

Add to `~/.zshrc`:
```sh
source ~/.zsh/talk2term/talk2term.plugin.zsh
```

Restart: `source ~/.zshrc`

---

## Windows (WSL)

1. Install WSL: `wsl --install` (PowerShell as Admin)
2. Inside WSL, install ZSH: `sudo apt install zsh curl jq git`
3. Set ZSH as default: `chsh -s $(which zsh)`
4. Follow the **Oh My Zsh** or **Manual** instructions above

---

## Updating

Re-run the pinned installer for the tag you want. `t2t-update` checks out the tag baked into that plugin (`v1.2.0` in this release). It does not pull unpinned `main`.

---

## Uninstall

1. Remove the plugin directory.
   - Oh My Zsh: `rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/talk2term"`
   - No Oh My Zsh: `rm -rf "$HOME/.zsh/talk2term"`
2. Remove the Talk2Term line from `~/.zshrc`. That is the `talk2term` entry inside `plugins=(...)`, or the `source .../talk2term.plugin.zsh` line.
3. Or restore the pre-install backup instead of editing the line by hand: `mv ~/.zshrc.bak.t2t ~/.zshrc`
4. Remove the API key file: `rm -f ~/.talk2term`
