---
name: codex-image-creation
description: Generate or edit an AI image (a PNG file) with Codex (ChatGPT image generation). Use whenever the user asks to generate, make, create, design or draw an image, picture, photo, illustration, logo, icon, mockup, poster, flyer, banner, social media post graphic, YouTube thumbnail, cover art or wallpaper, including graphics with text on them, says "use codex to get an image", or wants an existing image edited, restyled or given a transparent background.
metadata:
  harness: [claude, cursor, opencode]
  platform: [darwin, linux]
  scope: controller
  requires: "curl, jq, and either a CLIProxyAPI hub (cliproxy section of ~/.codex/config.toml) or OPENAI_API_KEY"
---

# Codex image creation

Codex itself is left out of `harness`: it generates images natively. Every other harness gets
them through this script.

## How it works

[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) is a small server that signs in to
your ChatGPT (Codex) subscription and exposes it as an OpenAI-compatible API. In the fleet it
runs on the worker as the shared model hub ([`packages/cliproxy`](../../packages/cliproxy/)).
Besides chat completions, it serves OpenAI's image routes and forwards them to ChatGPT's own
image generation on a signed-in account:

| Route | Body | Use |
| --- | --- | --- |
| `POST <hub-url>/images/generations` | JSON: `model`, `prompt`, `quality`, `background`, `output_format`, `n` | new image |
| `POST <hub-url>/images/edits` | multipart: the same fields plus `image[]=@file` per reference | edit, restyle, use as reference |

Both answer with `{"data":[{"b64_json": "..."}], "quality": ..., "size": ...}`. The script
decodes `b64_json` to a PNG. `<hub-url>` already ends in `/v1`.

The script reads the hub address and its bearer token from `[model_providers.cliproxy]` in
`~/.codex/config.toml` (`base_url`, `experimental_bearer_token`), the same block that points
Codex at the hub. So the controller uses the hub's tailnet URL and the worker uses
`http://127.0.0.1:<port>/v1`, with no extra config. No OpenAI API key and no API credits: the
images count against the subscription.

**No hub?** Export `OPENAI_API_KEY` and the script calls `https://api.openai.com/v1` with the
same routes. That route is billed per image, and the model name matters (`IMAGE_MODEL`,
default `gpt-image-1`).

## Run it

```bash
bash ~/.agents/skills/codex-image-creation/gen.sh "<prompt>" "<short-kebab-name>.png" [--ref <image>]...
```

- **Where it goes.** Every original lands in `$IMAGE_DIR` (default `~/Pictures/generated`). A
  bare filename goes straight there. If a task needs the image elsewhere (a repo asset, a T3
  project icon), pass that path: the script keeps the original in `$IMAGE_DIR` (named
  `<folder>-<file>.png`) and copies it to the path. Don't write images anywhere else yourself.
- **Edits and references.** `--ref <path>` per image, up to 5.
- **Transparent background.** Say "transparent background" in the prompt; the script asks for
  real alpha.
- **Several images** ("generate 3"): one run each, in parallel in the background, distinct names,
  wait for all before replying. A single run can stay in the foreground with a 10 minute timeout.

## Write the prompt out in full

ChatGPT picks the quality tier from how much the prompt specifies. Model and quality settings
are ignored through the hub.

| Prompt | Tier | Time |
| --- | --- | --- |
| One line | low | 15 to 25 s |
| Some exact text in the scene | medium | 25 to 45 s |
| Fully specified: subject, foreground, midground, background, camera or medium, lighting, textures, exact text in quotes | high | about 2 min |

Expand a short request into a full scene, but keep everything the user asked for. Quality words
("ultra detailed, 8k") do nothing. Size comes from the prompt, not a parameter, so repeat any
dimensions or aspect ratio the user gave word for word. Warn about the two minute wait for long
prompts.

## After the run

The script prints `IMAGE: <absolute path>` and, when you passed an outside path,
`COPY: <absolute path>`. Use those exact paths for what comes next: embedding, a follow-up edit
with `--ref`, wiring it into a repo, or uploading it when a public URL is needed. The script never
uploads.

Check the dimensions and alpha it prints against the request. Existing is not the same as
correct. On failure (non-zero exit, no `IMAGE:` line) report the error and don't claim success.
Don't pipe the script through `tail`, which hides the exit code. It already retries once on a
5xx. Embed every image in the reply by its `IMAGE:` path; reading the file only shows it to you.

Always run the script yourself. Don't delegate images to a Codex thread or a subagent. For
back-and-forth, rerun with `--ref` on the last image.

The hub's request logs (`v1-images-*.log` in its log dir on the worker) show which account
served each image, if you run several.

## Testing the trigger

`trigger-eval.sh [model...]` asks cheap Claude models which skill they would load for a set of
prompts that should and should not trigger this one. It gives the model only the Skill tool and
no MCP servers, in an empty temp dir, so a negative case can't take a real action. An earlier
version that only blocked Bash, Write and Edit took a real screenshot through a GUI MCP.
