---
name: content-principles
description: The psychology behind short-form content that holds attention. Use it whenever you plan, write, review or edit a short-form video script (Reels, TikTok, Shorts), a hook, or a social post. It teaches how a viewer's mind works, never a template to fill in, so apply the principles silently instead of turning them into a checklist or format.
metadata:
  harness: [claude, codex, cursor, opencode]
  platform: [darwin, linux]
  scope: fleet
  requires: "nothing to run. The full text comes from aiwithremy/content-principles (fetch it, see below)"
---

# Content principles

The real skill is Remy Gaskell's [aiwithremy/content-principles](https://github.com/aiwithremy/content-principles).
Its repo has no license file, so this folder does not copy its prose. Install the original:

```bash
git clone --depth 1 https://github.com/aiwithremy/content-principles /tmp/cp
cp /tmp/cp/content-principles/SKILL.md ./SKILL.md        # then re-add the metadata block above
```

Or paste the repo URL into your agent and ask it to install the skill. To keep it current, run the same copy from a
nightly job and record the upstream commit in a `SOURCE` file next to it.

What follows is a short summary in my own words, enough to know what the skill does and to work
from if you haven't installed it yet.

## How to use it

Let the principles shape the reasoning. Don't repeat them to the user and don't turn them into a
checklist, a rubric or a beat sheet. If you can name the format you used, or the script would
still work with the subject swapped out, you followed a template instead of thinking about the
viewer. Start again from the viewer.

## The ideas, briefly

1. **Write to one person.** Picture one specific viewer and send the video to them. Ask the user
   who that is if you don't know. Put specificity in the thing (a dollar amount, a date), not in
   naming the viewer's job.
2. **Value against time.** A scroller weighs how useful this looks against how long it will
   take. The opening makes the first big and the second small. The gap between what you know and
   what they know is the product.
3. **Line by line.** Short form is judged one line at a time. Each line has to earn the next.
4. **Curiosity loops.** The hook is the first open question. Open the next one before closing the
   last, keep the viewer (not someone on screen) holding the question, and never deflate a loop
   with a joke reveal.
5. **Specific beats vague.** Numbers, names and dates instead of summaries.
6. **Simple sentences for new ideas.** Could a ten-year-old follow each line? Can the idea be said
   in ten words?
7. **Value early.** Promise it in the first seconds and deliver something real within about ten.
   Platforms test on a small audience first, so the opening is what gets measured.
8. **Cut what doesn't serve the hook**, including lines that are interesting but off the point.
   Keep sentences short.
9. **Disarm the likely objection** ("this is an ad", "I'd need to code", "this won't work for me")
   at the moment it would occur.
10. **The edit follows the script.** More distinct beats give the editor more places to cut. Cuts
    refresh attention, loops create it.

Treat all of it as priors, not rules. A script that breaks them and still holds attention wins.

Credit: Remy Gaskell ([aiwithremy](https://github.com/aiwithremy), [aiwithremy.com](https://www.aiwithremy.com)). Read the original for the
examples, tables and the full reasoning.
