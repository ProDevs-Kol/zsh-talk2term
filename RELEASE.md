# Release checklist

Ship a tagged plugin release that matches the GitHub **Releases** page. A tag alone is not enough — create the GitHub Release in the same pass (PRO-8571: tags v1.2.16–v1.2.18 existed while Latest stayed on v1.2.15).

## Before you tag

1. Bump `.version` and pin `PLUGIN_REF` / docs to the new tag (`install.sh`, `INSTALL.md`, `README.md`, plugin version string).
2. Refresh the pinned `install.sh` sha256 in `INSTALL.md` and `README.md`.
3. Merge the release pin PR to `main`.

## Tag

```sh
git fetch origin
git checkout main && git pull --ff-only
git tag -a "vX.Y.Z" -m "vX.Y.Z: <one-line user-visible summary>"
git push origin "vX.Y.Z"
```

Do not move or retag an existing tag.

## Create the GitHub Release (required)

Tags and Releases must stay in sync. After the tag is on GitHub:

```sh
gh release create "vX.Y.Z" -R ProDevs-Kol/zsh-talk2term \
  --verify-tag \
  --title "vX.Y.Z" \
  --latest \
  --notes "$(cat <<'EOF'
Fix from #<pr> (PRO-xxxx):
- <one line per user-visible fix; honest, no marketing>

Installer pinned to vX.Y.Z. install.sh sha256: <sha256>

Review https://github.com/ProDevs-Kol/zsh-talk2term/blob/vX.Y.Z/install.sh before running it.
This tag does not pull unpinned main.
EOF
)"
```

Proof:

```sh
gh release list -R ProDevs-Kol/zsh-talk2term -L 4
```

Confirm the new tag shows as **Latest**.
