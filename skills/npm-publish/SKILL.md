---
name: npm-publish
description: Publishing the user's npm packages from any fleet machine. Use when a task ends in `npm publish`, bumps a package version, or hits EOTP / E401 / E403 from the npm registry, or when the user says "publish it", "push to npm", "new npm token", "rotate the npm token".
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "a granular npm token with 2FA bypass in ~/.npmrc (mode 600) on each machine that publishes; never in git"
---

# npm publish

## Where auth lives

One **granular access token** for your npm account, scoped to only the packages the fleet
publishes, with **Bypass two-factor authentication** ticked. It sits in `~/.npmrc` on each machine
that publishes:

```
//registry.npmjs.org/:_authToken=<token>
```

Mode 600, installed by hand, never committed. Keep the procedure in this skill and the value out
of every repo; make sure the fleet repo and any config repo `.gitignore` refuse `.npmrc`.
`npm whoami` printing your npm username proves the machine is ready.

If `npm` lives under nvm, a non-interactive shell needs `. ~/.nvm/nvm.sh` first.

## Publish

From the repo, at a commit that is on `origin/main`:

```bash
git status --short            # clean
npm test                      # green
npm pack --dry-run            # check the file list once
npm publish
git tag v$(node -p "require('./package.json').version") && git push origin --tags
npx --yes <package>@$(node -p "require('./package.json').version") --version
```

The package decides the version: bump `package.json` in the same PR as the change. `@latest` is
what `npx <package>@latest` resolves to, so a publish is live for every skill and machine using it
within about a minute.

A package published under two names (a rename that keeps the old name alive) needs one release
script that tests, bumps, tags, pushes and publishes both names from **one tarball**. If one name
fails, rerun with the version already in `package.json` to publish only the missing one. Never
publish one name alone.

## When it fails

| error | meaning | fix |
| --- | --- | --- |
| `E401` on `npm whoami` | token expired or revoked | rotate (below) |
| `EOTP` on publish, `whoami` fine | token has no 2FA bypass and the account enforces 2FA on writes | regenerate as a granular token with bypass, or ask the user for a code and run `npm publish --otp=<code>` for this one release |
| `E403` | token not scoped to this package | regenerate with the package added |
| `E403` "Package name too similar to existing package" | a name is blocked once `-` `_` `.` are stripped (`pagedrop` vs `page-drop`) | pick another name. A 404 from `npm view` does not mean it is publishable; check the variants too |
| registry shows a staged version, or the new one is missing for minutes | staged publishing queued it | wait a few minutes. `npm stage list` shows anything awaiting `npm stage approve <id>` |

Never ask the user to paste an OTP into a file or a commit. It goes on the command line once.

## Rotate

1. npmjs.com, Access Tokens, Generate new token, Granular. Read and write; packages: only the
   ones the fleet publishes; tick Bypass two-factor authentication; longest expiry allowed.
2. Replace the `_authToken` line in `~/.npmrc` on **every** publishing machine at once, or one
   keeps working on the dead token until it silently doesn't.
3. `npm whoami` on each.
4. Revoke the old token.

A token pasted into a chat is burned: rotate it as soon as the publish it was for is done.

## Packages

Keep a table of what you publish so an agent knows the release path for each:

| package | repo | notes |
| --- | --- | --- |
| `<package>` | `<owner>/<repo>` | release command, any second name, any deploy that is separate from npm |
