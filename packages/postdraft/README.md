# postdraft

Agents write a plan, report, set of mocks or screenshot, and you get a link you can open on your
phone. [`postdraft`](https://github.com/Aryan-Saini/postdraft) renders Markdown into one
self-contained HTML page and publishes it to **your own** server, a small Convex app on your
account, so nothing goes through anyone else's. It started as a fork of Theo's
[postplan](https://www.npmjs.com/package/postplan) ([t3dotgg](https://github.com/t3dotgg)) and
keeps his HTML security policy.

```bash
postdraft upload plan.md          # renders, publishes, prints the URL; re-upload keeps the URL
postdraft asset shot.png          # permanent public URL for a screenshot, e.g. to embed in a PR
postdraft asset export.csv --private   # stable /a/ link, each visit a short-lived signed URL
postdraft send build.apk          # a download page you open on your phone
postdraft generate-upload-link    # a page to send files in from a phone or another person
postdraft versions <url>          # every version of a draft; nothing is ever overwritten
```

## Skills that ship with it

The npm package carries four skills, and `fleet link` puts them in every harness:

| skill | what an agent does with it |
| --- | --- |
| `html-communication` | writes a plan, spec, report or mock as Markdown (charts, diagrams, questions, file cards) and publishes it as a link |
| `file-upload` | publishes a screenshot, recording or build and returns a permanent URL |
| `send-file-link` | sends files out to a page you preview and download on a phone |
| `request-upload-link` | makes a page for sending files in |

When a release changes them, the CLI reinstalls them and prints `Re-read the SKILL.md`. Skip
SETUP.md's own "install the skills" step in a fleet; `fleet link` does it.

## The server: Convex, plus S3 if you want it

The server is the repo's `convex/` folder deployed to a Convex project on your account. Convex
serves the API and the pages (`https://<deployment>.convex.site`), holds drafts, versions, answers
and asset records, and runs a daily cleanup cron. Bytes go to one of two places:

| storage | set up | public assets | private assets (`/a/<slug>`) | expiry |
| --- | --- | --- | --- | --- |
| Convex file storage (default) | nothing | `<deployment>.convex.cloud/api/storage/<uuid>` | redirect to that storage URL | daily cron deletes expired bytes |
| S3 (when `S3_BUCKET` is set) | a bucket and an IAM user | the bucket's plain URL under `public/` | 302 to a 5-minute presigned GET | bucket lifecycle rule on a tag |

Switching storage affects new uploads only.

### Server environment (names only)

Set with `npx convex env set --prod <NAME> <value>` from your server checkout:

| name | required | what |
| --- | --- | --- |
| `POSTPLAN_API_KEY` | **yes** | the key the CLI sends. Unset means anyone who finds the URL can publish HTML on your origin |
| `POSTPLAN_PUBLIC_BASE_URL` | yes | `https://<deployment>.convex.site` |
| `S3_BUCKET`, `S3_REGION`, `S3_PREFIX` | S3 only | where drafts go; the prefix (e.g. `drafts`) stays private |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | S3 only | the IAM user below |
| `ASSETS_BUCKET`, `ASSETS_REGION` | S3 only, for `asset` | can be the same bucket; without them asset endpoints answer 503 |
| `MAX_HTML_BYTES` | no | upload size cap |

### The S3 bucket

One bucket is enough. Its layout:

| prefix | readable by | what |
| --- | --- | --- |
| `drafts/` | nobody directly | HTML, content-addressed, served only through `/d/<id>` |
| `public/<project>/` | anyone, via bucket policy | `asset` default: permanent unguessable URLs |
| `protected/<project>/` | nobody directly | `--private` assets, reached through `/a/<slug>` and presigned GETs |

Settings:

- **Block Public Access:** `BlockPublicAcls=true`, `IgnorePublicAcls=true`,
  `BlockPublicPolicy=false`, `RestrictPublicBuckets=false`. ACLs stay off; one bucket policy
  makes only `public/*` readable.
- **Bucket policy:** `Allow`, `Principal: "*"`, `s3:GetObject` on `arn:aws:s3:::<your-bucket>/public/*`.
  Nothing else is public.
- **Lifecycle:** one rule, filter on tag `autodelete=7d`, expire after 7 days. The server tags
  builds and anything expiring within a week (it signs the `x-amz-tagging` header, which S3 refuses
  unsigned on a presigned PUT).
- **IAM user** for the server, inline policy, no `ListBucket`:
  `s3:GetObject`, `s3:PutObject`, `s3:PutObjectTagging`, `s3:DeleteObject` on
  `arn:aws:s3:::<your-bucket>/*` (or scoped to `drafts/*`, `public/*` and `protected/*`).
- **CORS**, for the phone pages in S3 mode: the upload page PUTs bytes straight to the bucket
  from your `.convex.site` origin, and the send page reads them back. Allow that origin only:

  ```json
  [{"AllowedOrigins": ["https://<deployment>.convex.site"],
    "AllowedMethods": ["PUT", "GET", "HEAD"],
    "AllowedHeaders": ["*"], "ExposeHeaders": ["ETag"], "MaxAgeSeconds": 3600}]
  ```

  `aws s3api put-bucket-cors --bucket <your-bucket> --cors-configuration '{"CORSRules": [...]}'`.

### The upload flow

1. The CLI asks `POST /api/assets/sign` (with the API key) for a presigned PUT. The server builds
   the object key, so a client can never write outside `public/` and `protected/`.
2. The CLI sends the bytes straight to storage. Convex never proxies them.
3. `POST /api/assets/record` reads the size and type back from storage and writes the row, so a
   PUT that never landed leaves nothing behind.

Drafts are simpler: `POST` the rendered HTML, the server checks it against the upload policy
(`src/html-policy.js`, the real gate), stores it by content hash, and serves it at `/d/<id>` with a
strict CSP (no fetch, no frames, no forms, no remote scripts). Re-uploading the same source file
bumps the version and keeps the URL; `/d/<id>/v/<n>` never changes.

## Install

1. Enable it on every machine that runs agents. `./install.sh` runs `npm i -g postdraft`.
2. **Once, from the controller:** deploy your server. Paste into your agent:

   ```text
   Set up postdraft for me by following https://raw.githubusercontent.com/Aryan-Saini/postdraft/main/SETUP.md
   ```

   It asks Convex storage or S3, clones the server to `~/postplan-server`, logs in to Convex
   (you approve), creates the project, `npx convex deploy`s it, generates `POSTPLAN_API_KEY`, sets
   the server env, and runs `postdraft auth set <key> --api-url <site-url>`. In S3 mode it creates
   the bucket, policy, lifecycle rule and IAM user above. Add the CORS rule if you use the phone
   pages.
3. **Every other machine:** the same server and key. The CLI reads the URL from
   `~/.postplan/config.json` and the key from `~/.postplan/credentials.json` (mode 600), or
   `POSTPLAN_API_URL` / `POSTPLAN_API_KEY` from the environment. Copy both files, or run the same
   `auth set` line there.

## Verify

```bash
echo '# hello' > /tmp/t.md && postdraft upload /tmp/t.md     # prints a URL
curl -sL -o /dev/null -w '%{http_code}\n' <that URL>          # 200
```

## Health

`check.sh`: the CLI is installed and has a server and a key. With `FLEET_PROBE=1` it also runs
`postdraft whoami` against your server. No heal: a missing key needs you.

## Updating

`npm i -g postdraft@latest` on each machine; the skills follow. The server updates separately,
when a release note says it changed: `cd ~/postplan-server && git pull && npm install && npx convex deploy -y`.
