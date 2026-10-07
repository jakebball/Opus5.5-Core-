# Publishing this repository to GitHub

The repository is already initialised with git, on branch `main`, with one commit. Publishing it is three steps.

## Before you publish

1. **Licenses.** Open `THIRD_PARTY.md` and confirm the license of each library marked "verify" against its upstream
   page. For any MIT or Apache-2.0 library whose notice is missing from its file, either paste the upstream license
   text into `THIRD_PARTY.md` under its row or restore the header in the live game and re-extract.
2. **Pick the visibility.** This repo was prepared to be public: no API keys, no personal paths, no group or user ids,
   and robloxMeshTools is downloaded by the installer rather than shipped. Choose private instead if the team's own
   framework code (the Runner, AdminSystem) should not be public.
3. **Choose a license for your own code** (optional). Without a `LICENSE` file the code is public to read but nobody
   may legally reuse it. `MIT` is the usual choice; add it with GitHub's *Add file > Create new file > LICENSE*
   template after publishing.

## Option A: GitHub CLI (fastest)

Install the CLI from https://cli.github.com and sign in once with `gh auth login`. Then, from this folder:

```bash
gh repo create roblox-claude-setup --public --source . --remote origin --push --description "Roblox x Claude Code team setup: /setup standard, headless-Blender asset pipeline, Studio tooling and the Runner baseplate"
```

Use `--private` instead of `--public` for a private repo, and `<org>/roblox-claude-setup` to create it under an
organisation.

## Option B: the GitHub website

1. Go to https://github.com/new. Name it `roblox-claude-setup`, choose Public or Private, and **do not** add a README,
   `.gitignore` or license (the repo already has them; adding them makes the first push fail).
2. Copy the repository URL GitHub shows, then from this folder:

```bash
git remote add origin https://github.com/<you>/roblox-claude-setup.git
```

```bash
git push -u origin main
```

## After publishing

- Teammates install with:

```bash
git clone https://github.com/<you>/roblox-claude-setup.git
```

```powershell
powershell -ExecutionPolicy Bypass -File roblox-claude-setup\install.ps1 -ProjectsDir "D:\Roblox"
```

- **Updating it later:** improve the skills in your own `~/.claude/skills`, then from this folder run
  `node maintainer/export.js`, review `git diff`, commit and `git push`. Teammates `git pull` and run the installer
  again (it keeps their own `CLAUDE.md` content and registered projects).
- **Updating the baseplate:** with the source game open in Studio, `node maintainer/baseplate.js all --place-id <ID>`, check the result
  (`CLAUDE.md` § 2), commit and push.
- The repository is about 25 MB: the brush swatch images (22 MB) and the baseplate (0.5 MB) are the bulk. That is well
  under GitHub's limits; no Git LFS is needed.

## If the push is rejected

- **"push declines due to email privacy restrictions":** your GitHub account hides its email, and the commit carries
  your real address. Set the no-reply address GitHub shows under *Settings > Emails*, rewrite the commit, push again:

```bash
git config user.email "<id>+<username>@users.noreply.github.com"
```

```bash
git commit --amend --reset-author --no-edit
```

- **"Updates were rejected because the remote contains work":** the GitHub repo was created with a README or license.
  Delete and recreate it empty, or `git pull --rebase origin main` and push again.
