---
name: spotify
description: Play the user's Spotify anywhere and control it with the `spotify` CLI, from the controller or a worker. Use whenever the user wants music somewhere ("play X on the TV / speaker / laptop / my phone / here"), to move what's playing to another device, pause, resume, change Spotify volume, see what's playing and where, list playlists or devices, search for a song, get a playlist's tracks newest first, or when any script needs a Spotify access token.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "python3; ~/.config/spotify.env on the machine (mode 600, never in git); a Spotify Premium account"
---

# spotify

`scripts/spotify` in this folder is a stdlib-only Python CLI over the
[Spotify Web API](https://developer.spotify.com/documentation/web-api). Put it on PATH on every
machine: `ln -s ~/.agents/skills/spotify/scripts/spotify ~/.local/bin/spotify`. Run `spotify`
with no args for usage.

```bash
spotify devices                                    # what is online now: name, type, id, active
spotify now                                        # what is playing, and on which device
spotify search "song name"                         # top 5 track URIs (--type album|artist|playlist)
spotify play spotify:track:<id> --device tv        # a track, album, artist or playlist
spotify play "<playlist name>" --device speaker --newest
spotify transfer laptop                            # move what's playing now, keep playing
spotify pause | spotify resume [--device NAME]
spotify volume 30 --device tv
spotify playlists | spotify tracks PLAYLIST --newest
spotify sort PLAYLIST                              # reorder the playlist itself, newest added first
spotify api GET /me/player                         # anything else in the Web API
spotify token                                      # bearer token for another script
```

`--device` takes the exact Spotify name or a plain word from the `ALIASES` table at the top of the
script. Fill that table in with your own devices: run `spotify devices` while each one is awake
and copy its name exactly (macOS names often contain a curly apostrophe).

`--newest` plays a playlist by date added, newest first, shuffle off. The API can't sort a
playlist context, so the CLI sends up to 300 track URIs instead. `sort` rewrites the playlist's
own order to match date added, one move at a time (about 100 s for 400 tracks), because replacing
the item list in one call would reset every track's added date. It backs nothing up, so save
`spotify tracks PLAYLIST` first if the order matters.

## Where to play

A device can only be targeted while it shows in `spotify devices`, and most only show up after
something wakes them. Keep a table like this for your house:

| User says | Spotify name | Shows in `devices` when | If it's missing |
| --- | --- | --- | --- |
| TV, console | `<console or TV name>` | it is on and a phone has picked it since it last started | the user picks it once in the Spotify app on their phone, on the same Wi-Fi |
| speaker | `<speaker name>` (CastAudio) | someone cast Spotify to it recently | the user casts from their phone. Cast speakers can't log themselves in |
| laptop | `<laptop name>` (Computer) | the Spotify app is open | open it (`open -a Spotify` on macOS), wait about 5 s |
| phone | `iPhone` / `<phone name>` | the Spotify app is open on it | only the user can open it |

**"Here"** means the machine the agent runs on. A headless worker has no speakers, so "here" on a
worker is a question: ask where.

**No place named:** if something is already playing, use that device (`spotify now`). If nothing
is, ask. Don't guess a speaker.

**"Move it to X"** is `transfer`, not `play`. It keeps the song and position.

## Rules

- Playback makes sound in someone's house. Only `play`, `resume`, `transfer` or `volume` when the
  user asked. Test at low volume (`volume 20` first), and only at a sensible hour.
- A device the user is listening on right now is theirs. Don't run anything that interrupts it.
- Keep scheduled jobs that use a speaker (an alarm, say) out of each other's windows, and don't
  touch that speaker during them unless asked.
- `resume` on a device that is already playing returns 403. Nothing to fix.

## Headless speakers with librespot

[librespot](https://github.com/librespot-org/librespot) turns a worker into a Spotify Connect
device. Use it as a bridge: it shows up in `spotify devices`, plays, and pipes the audio to
something that can't log itself into Spotify (a cast speaker, an AirPlay sink, a USB DAC).

```bash
librespot --name "<bridge name>" --cache ~/.cache/librespot --enable-oauth --backend pipe | <your sink>
```

librespot can't use this CLI's token (the Web API token has no streaming scope). It logs in once,
either by a phone picking it in the device list or with `--enable-oauth`, and caches the login in
`--cache`. Give the bridge a name that no alias in `ALIASES` is a substring of, so "speaker"
never resolves to the bridge.

## Credentials

`~/.config/spotify.env`, mode 600, on each machine, never committed:

```
SPOTIFY_CLIENT_ID=<your app's client id>
SPOTIFY_CLIENT_SECRET=<your app's client secret>
SPOTIFY_REDIRECT_URI=http://127.0.0.1:8888/callback
SPOTIFY_REFRESH_TOKEN=<written by `spotify auth`>
```

1. Create an app at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard),
   signed in as the account that owns the music. Enable the Web API and add the redirect URI
   above exactly. The dashboard only enables Web API playback control for a **Premium** account.
2. A new app is in Development mode: it works for the owner and up to 5 allowlisted users.
   That is enough for personal use.
3. Fill in the client id and secret, then run `spotify auth` on a machine with a browser. It
   prints a consent URL and waits on `127.0.0.1:8888`. Open the URL in a browser logged into the
   right Spotify account, click Agree, and the refresh token lands in the env file.
4. Copy the file to every other machine: `scp ~/.config/spotify.env <worker>:.config/`.

**Re-auth** when calls fail with `invalid_grant`. A refresh token lasts about 180 days. Spotify
sometimes rotates it on refresh; the CLI writes the new one back to the env file, so copy the
file again if workers start failing after the controller refreshed.
