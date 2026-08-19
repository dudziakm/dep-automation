# AI Provider Layer

This layer exists for one use case: **an agent that attempts to fix a
build that failed after a dependency bump** (Phase 7 of the plan — see
[`docs/AUTOMATION-PLAN.md`](../docs/AUTOMATION-PLAN.md)).
## Overriding principle: the agent is never a gate

An AI agent can **only** propose a change — that is, open a PR or return a
patch as an artifact. It has no authority to:

- evaluate whether a PR passed verification,
- merge anything,
- set the status of a check on which the merge decision is based.

The gate is and remains deterministic CI checks plus status evaluation by
Renovate. The reason is specific: the main risk is not a malicious
coworker, but **a poisoned package changelog that the agent reads as an
instruction**. A model that can be convinced by input content cannot
decide what goes into `main`.

Therefore, in this layer there is and will be no path to `pull_request:
write` or to a merge.
## Why switching a provider is a change of three values

All providers in [`providers.json`](providers.json) speak the same protocol: `POST {base_url}/chat/completions` in OpenAI format, with the key in the `Authorization: Bearer` header. This means that switching a provider does not touch the code — what changes is:

1. **base URL** (`base_url`),
2. **secret name** (`secret`) — meaning where to get the key from,
3. **model name** (`model`).

This is empirically verified, not assumed: the same `ai-call.sh` without any changes received a valid response from DeepSeek (`api.deepseek.com`), from OpenRouter (`openrouter.ai`), and from Kimi (`api.moonshot.ai`), and via OpenRouter also from Gemini models. Details in the "What has been empirically confirmed" section.

### A fourth value that was not here before: parameters

Adding Kimi showed the limit of the above rule, and it is fairer to describe it than to maintain that there are always three values. **Protocol compliance does not mean parameter compliance.** Kimi has `temperature` locked at `1.0` and rejects any other value:

```
HTTP 400: invalid temperature: only 1 is allowed for this model
```

The layer has so far been sending `temperature: 0` for all, so Kimi would not have responded **even once**. That is why a provider can now override any parameter with its own `parametry` block, and `ai-call.sh` resolves them per provider:

```json
"kimi": {
  "model": "kimi-k2.7-code",
  "parametry": { "temperature": 1, "max_tokens": 16384 }
}
```

This is still a **change of data, not code** — but there are four values, not three. The limitation is documented by the provider: `kimi-k2.7-code` and `kimi-k3` have `temperature` "fixed at `1.0`", while `kimi-k2.6` and `kimi-k2.5` have `1.0` in thinking mode and `0.6` outside of it ([Model Parameter Reference](https://platform.kimi.ai/docs/api/models-overview)). The remaining providers do not have a `parametry` block and receive exactly what they have so far — I checked with `--dry-run` that `temperature=0` and `max_tokens=4096` are still sent to them.

### How to switch — three ways, from least to most permanent

```bash
# 1. One-off, for a single call:
echo "$PROMPT" | ai/scripts/ai-call.sh -p openrouter

# 2. For an entire session or a CI job, without touching the repo:
AI_PROVIDERS_CONFIG=/sciezka/do/wlasnego-providers.json ai/scripts/ai-call.sh ...

# 3. Permanently: change .lancuch.domyslny in ai/providers.json and merge the PR.
```
## Chain: DeepSeek Flash → DeepSeek Pro → OpenRouter → Kimi

| Role | Provider | Model | When it kicks in |
|---|---|---|---|
| default | `deepseek` | `deepseek-v4-flash` | every first attempt |
| escalation | `deepseek-pro` | `deepseek-v4-pro` | harder case, or when Flash failed |
| fallback | `openrouter` | `google/gemini-3.7-flash` | DeepSeek unavailable: 401, 429, 5xx, provider outage |
| fallback | `kimi` | `kimi-k2.7-code` | OpenRouter did not respond either — third independent provider |

This is the **entire** list: four entries, all active, all in the chain.
There are no providers here "planned for the future" or disabled — an entry either
works and is used, or it does not exist.

A role in `lancuch` takes a provider name **or a list of names** tried in
sequence — `"zapas": ["openrouter", "kimi"]`. Adding another fallback is
therefore a one-line change in the configuration.

`ai-call.sh` traverses this chain automatically. A provider is skipped when
its secret is missing or when no response was received. Escalation can also be triggered
directly:

```bash
# Straight to Pro, because I know the case is difficult:
echo "$PROMPT" | ai/scripts/ai-call.sh --escalate

# Only default, without escalation and without fallback (e.g. when watching costs):
echo "$PROMPT" | ai/scripts/ai-call.sh --no-escalate
```

### Why escalation stayed on DeepSeek, and not OpenRouter

I checked this live, not from memory. `GET https://api.deepseek.com/models`
returns **exactly two** models: `deepseek-v4-flash` and `deepseek-v4-pro`. An attempt
to call a non-existent name confirms this with the provider's own message:
"The supported API model names are deepseek-v4-pro or deepseek-v4-flash".
`deepseek-v4-pro` responds correctly (HTTP 200) and is **actually a more powerful
variant of the same family** — it costs three times as much and has a five times
lower concurrency limit (500 versus 2500), which is a direct signal that it is a
model with a different compute profile, and not the same one under a different name.

Therefore, escalation is `deepseek-pro`, not OpenRouter. Three reasons:

1. **Escalation is supposed to change the model's power, not the provider.** Changing the provider changes
   too many things at once: the model, tokenizer, thinking handling, and behavior on
   long input. If escalation went straight to another provider, it would be impossible
   to tell whether the improved result came from a more powerful model or from
   chance.
2. **Escalation is a single-field change.** `deepseek` and `deepseek-pro` share the same
   `base_url` and the same secret — they differ solely in the model name. It does not
   require a second key, so it cannot break due to missing configuration.
3. **OpenRouter has a different job.** It is the answer to the question "what if DeepSeek
   is not responding", not "what if the task is hard". A provider outage and a difficult
   case are two different problems and should not share a single solution.

It is worth noting that the Flash → Pro pair is the **only** "same provider,
two power tiers" pair in this layer, and nothing can replace it. Kimi is not suitable for escalation
(different provider, different key — see the paragraph on Kimi below), OpenRouter even less so.
Therefore, the principle from point 1 has exactly one application, and it is this pair —
if it were ever to disappear, escalation would cease to make sense as a separate role, rather than
merely changing its destination.

If it turns out that Pro cannot handle it either, the right next step is **not**
another model, but a human. See the paragraph on loops below.

### When to escalate to Pro

Escalation is three times more expensive: Pro is `$0.66 / $1.98` per million
input and output tokens off-peak, compared to `$0.22 / $0.66` for Flash (in peak hours,
`$1.32 / $3.96` and `$0.44 / $1.32`, respectively). In absolute numbers, this is
still pennies, but the principle remains the same:

- **Flash is always the default.** A typical fix after bumping a dependency involves
  reading an `npm ci` or `mvn verify` log and making a single change in the manifest. This does not
  require a more powerful model.
- **Pro only when Flash failed**: it returned an error, returned an empty
  response, or its proposal did not pass the CI gate (and it was the CI that determined that
  it didn't pass — not the model).
- **We do not escalate in a loop.** One Flash run, one Pro run. If both
  failed, the issue goes to a human. A "keep trying" loop is the easiest
  way to get an uncontrolled bill.

### The role of OpenRouter

OpenRouter is a **fallback in case of an outage, not a second opinion**. It is in the chain because:

- it is an **independent provider and an independent key** — an outage or an exhausted rate limit on
  DeepSeek's side does not affect it,
- its API is **OpenAI-compatible** (empirically confirmed), so it does not require
  a single extra line of code,
- it provides **access to Gemini models without having a Google key** — which is the
  only way Gemini participates in this layer today.

A deliberate downside that must be kept in mind: OpenRouter adds **yet another
intermediary** in the path traversed by the contents of third-party changelogs
read by the agent. For an agent whose main risk is prompt injection, each additional hop
is additional attack surface. That is why it is a fallback, not the default.

### Role of Kimi — the second fallback, and why specifically there

```bash
# Kimi on demand, without touching the chain:
echo "$PROMPT" | ai/scripts/ai-call.sh -p kimi
```

Kimi is the **second fallback, after OpenRouter** — not the default and not an escalation.
Three reasons, in order of importance:

1. **Account limits exclude it from early links in the chain.** The account is on the lowest
   pricing tier: **3 requests per minute and concurrency 1**
   ([Recharge and Rate Limiting](https://platform.kimi.ai/docs/pricing/limits)).
   I did not make this up from a table — I got this live:
   `HTTP 429: request reached organization max RPM: 3`. A provider that accepts
   three requests per minute one at a time cannot sit at the beginning of a chain
   triggered on every failed build.
2. **It adds a third provider and a third key — which is exactly what was
   missing.** `deepseek` and `deepseek-pro` share **one key and one host**,
   so a revoked key or an outage of `api.deepseek.com` takes down both default
   and escalation at once. Until now, only OpenRouter rescued from this, single-handedly. Kimi
   gives the chain three independent points of failure instead of two.
3. **It does not disrupt anything that is already working.** Kimi is appended to the **end**
   of the fallback list, so every existing path looks identical character-for-character
   up to the point where the chain previously gave up. The default call still
   goes to DeepSeek — verified by running it, not assumed.

**Why not as an alternative escalation**, even though the model is specialized for
code: escalation in this layer is by definition supposed to change the **model's power with the same
provider** (rationale above, in the paragraph on `deepseek-pro`). Putting another
provider there would simultaneously change the model, tokenizer, and thinking handling, so it
would be impossible to tell whether a better result came from a more capable model or from
changing the provider. For deliberately reaching for a coding model, there is the `-p kimi` flag —
and that is the right path when someone *wants* Kimi, rather than when *everything else has failed*.

#### Which Kimi model and why — decided by measurement, not a hunch

The account sees five models from the Kimi family. All five **responded** to an actual
chat call, so availability alone settles nothing. What settled it was a test on
a real task of this layer: an `npm ci` log with a peer dependency conflict after
bumping `vite` from 5 to 7, `max_tokens: 4096`, 378-token prompt.

| Model | Time | Response tokens | of which thinking | Result |
|---|---|---|---|---|
| `kimi-k2.5` | 131.5 s | 4096 | 4095 | **empty** — `finish_reason=length` |
| `kimi-k2.6` | 57.7 s | 2058 | 1879 | correct diagnosis |
| **`kimi-k2.7-code`** | **18.8 s** | **600** | **463** | **correct diagnosis** |
| `kimi-k2.7-code-highspeed` | 17.4 s | 4096 | 4095 | **empty** — `finish_reason=length` |
| `kimi-k3` | 17.7 s | 597 | 329 | correct diagnosis |

Prices from Moonshot's official price list, per million tokens, in USD, excluding taxes:

| Model | Input (cache hit) | Input (cache miss) | Output | Context | Source |
|---|---|---|---|---|---|
| `kimi-k2.5` | 0.10 | 0.60 | 3.00 | 262 144 | [pricing/chat-k25](https://platform.kimi.ai/docs/pricing/chat-k25) |
| `kimi-k2.6` | 0.16 | 0.95 | 4.00 | 262 144 | [pricing/chat-k26](https://platform.kimi.ai/docs/pricing/chat-k26) |
| **`kimi-k2.7-code`** | **0.19** | **0.95** | **4.00** | **262 144** | [pricing/chat-k27-code](https://platform.kimi.ai/docs/pricing/chat-k27-code) |
| `kimi-k2.7-code-highspeed` | 0.38 | 1.90 | 8.00 | 262 144 | [pricing/chat-k27-code](https://platform.kimi.ai/docs/pricing/chat-k27-code) |
| `kimi-k3` | 0.30 | 3.00 | 15.00 | 1 048 576 | [pricing/chat-k3](https://platform.kimi.ai/docs/pricing/chat-k3) |

I chose **`kimi-k2.7-code`**. Four arguments, each with a number:

1. **Code specialization is free here.** `kimi-k2.7-code` has **the identical
   input and output price as the general-purpose `kimi-k2.6`** (0.95 / 4.00) — they differ
   solely in the cache hit price (0.19 versus 0.16). The provider describes it as a
   "coding-focused model that completes programming tasks with higher success
   rates in long contexts". Since it costs the same, and the layer exists to read build
   logs, choosing a general-purpose model would be paying the same for a less
   tailored tool.
2. **On a real task, it came out the cheapest, despite a higher unit price than
   K2.5.** Calculated from measured tokens and prices from the table (cache miss):
   `k2.7-code` **$0.00276**, `k2.6` $0.00859, `k3` $0.01034. That means it is **3.1×
   cheaper than K2.6 at the same price per token** — because it used 3.4× fewer output
   tokens for the same correct response.
3. **The cheapest per token turned out to be the most expensive per response.** `kimi-k2.5` has
   the lowest price list (0.60 / 3.00), but burned through its entire budget of 4096 tokens on
   thinking and **returned nothing**, costing $0.01252 in the process — the highest among all
   five, for zero content. This is exactly the trap described below in the paragraph on
   thinking tokens, only measured on Kimi.
4. **`kimi-k3` and the `-highspeed` variant were eliminated on price, not quality.** K3 gave
   an equally good response, but costs **3.2× more on input and 3.75× on
   output**, and its advantage — a 1M token context — is irrelevant for build
   logs that fit within thousands of tokens. `-highspeed` is straightforwardly
   **the same model** as `kimi-k2.7-code` ("the same model as Kimi K2.7 Code, but
   with an output speed of approximately 180 Tokens/s"), sold for **exactly
   twice the price** solely for speed. The CI agent runs in the background and no one is waiting on
   its response, so paying 2× for latency is unjustified here.

#### Why `max_tokens` for Kimi is 16384, and not the default 4096

Because `temperature` is locked at `1.0` and **cannot be lowered to zero**, making
Kimi's outputs inherently non-reproducible. The same prompt run on
`kimi-k2.7-code` seven times produced between **552 and 1336 thinking tokens** — a
2.4× spread on identical input.

To be fair: **`kimi-k2.7-code` itself never once exceeded 4096** in those
seven runs. Raising the limit is a margin of safety, not a patch for an observed
failure. Three things justify it: the same model under the alias
`kimi-k2.7-code-highspeed` **returned empty** at 4096, `kimi-k2.5` did the same,
and my test log had 378 tokens — real failed build logs are
significantly longer, so there will be more thinking as well. Moreover, `max_tokens` is a
**limit, not a fee**: you pay for tokens actually generated, so a higher
ceiling costs nothing until the model actually uses it.

#### When to reach for Kimi instead of DeepSeek

Kimi **is not cheaper** and is not here for that reason. Compared to the default
`deepseek-v4-flash` (0.22 / 0.66 off-peak), it costs **4.3× more on input
and 6× on output**. Sensible reasons to reach for it:

- **DeepSeek is not responding and OpenRouter is not either** — then no action is needed, Kimi
  will engage automatically as the last link in the chain.
- **The task is clearly code-related and I want a coding model** — `-p kimi`. Typically:
  a long compilation log, a peer dependencies conflict, an API migration between major
  versions.
- **During DeepSeek's peak hours, the price difference almost disappears.** Peak hours (01:00–04:00
  and 06:00–10:00 UTC) double DeepSeek's rates: `deepseek-v4-pro` then costs
  1.32 / 3.96, which is **more on input than Kimi** (0.95) and practically the same
  on output (4.00). If escalation falls during peak hours anyway, `-p kimi` is
  comparable in price and provides a model specialized for code.
- **I want a second opinion from an independent provider** — but in that case remember that it is
  still just a proposal. The gate is CI checks, never the agreement between two models.

What Kimi **does not** solve: it is not faster (18.8 s versus fractions of a second for
DeepSeek on the same control question), it is not cheaper, and at 3 requests
per minute it is unsuitable for anything batch-oriented. Raising the limits requires a
higher top-up tier, not changes in this repo.

### Why Gemini is not present as a provider

Gemini **is not** a provider in this layer, and the `gemini-flash` and
`gemini-pro` entries were removed from the configuration along with the
`GEMINI_API_KEY` secret. The reason is financial, not technical: the available Google key
sits on the **free tier**, and moving to the paid tier is an expense of around 40 PLN, for
which there is no approval.

This is not a guess — the free tier was measured using this key, and the result is
unambiguous:

| Model | Response | What this means |
|---|---|---|
| `gemini-3.6-flash` | **HTTP 200** | Flash on the free tier works |
| `gemini-3.1-pro-preview` | **HTTP 429**, metrics with `-FreeTier` suffix and `limit: 0` | Pro has a **zero quota** on this account — not "small", but none at all |

So the free tier provided **half** of what the layer needs: the base
model, yes, but the more powerful variant for escalation had a limit of zero.
A provider whose escalation can never execute is worse than having none at
all, because it looks available and only fails on the fly. This matches
Google's pricing: Pro models were removed from the free tier on 01.04.2026.

There is also a second reason not to fall back on the free tier here, and it would
not go away even with a limit greater than zero: **content sent to the free tier
is used to improve Google products**, which the pricing page does not hide. This
layer's agent reads build logs from private repositories, so the free tier was a
bad idea for it regardless of limits.

**If this decision ever changes in the future**, coming back involves three steps —
starting with a top-up, because without it Pro will continue returning 429:

```bash
# 1. Paid tier in Google AI Studio (without this, gemini-3.1-pro-preview has limit 0).
# 2. Secret — never in a file in the repo:
gh secret set GEMINI_API_KEY --repo dudziakm/dep-automation
# 3. Entry in ai/providers.json with base_url https://generativelanguage.googleapis.com/v1beta/openai
#    and adding the name to .lancuch — CI makes sure that one does not pass without the other.
```

Prices from the latest check, for reference when making this decision: `gemini-3.6-flash`
is 1.50 / 7.50 USD per million input and output tokens, `gemini-3.1-pro-preview`
2.00 / 12.00 (and 4.00 / 18.00 above 200k input tokens) —
[Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing). For
comparison, the default `deepseek-v4-flash` costs 0.22 / 0.66 off-peak, so
Gemini Flash alone is **about seven times more expensive on input and over
eleven times on output**. Opting out of Gemini is therefore not merely a saving
of 40 PLN at the outset.

Note, if the entry is ever brought back: CI ensures that a provider with `aktywny`
status **is** in the chain, and a provider from the chain **is** active. Doing half the job
will turn `validate ai layer` red — by design.

Gemini models still participate in this layer, but **exclusively through
OpenRouter** (`google/gemini-3.7-flash` as the first fallback). This is a different route,
a different key, and a different bill — it requires neither a Google account nor a paid Gemini tier.
## Secrets

In the configuration, we keep **only the names** of variables. Values never go
into the repo.

| Secret | For whom | Where to get | Required |
|---|---|---|---|
| `DEEPSEEK_API_KEY` | `deepseek`, `deepseek-pro` | [platform.deepseek.com](https://platform.deepseek.com/) | yes — this is the default path and escalation |
| `OPENROUTER_API_KEY` | `openrouter` | [openrouter.ai/keys](https://openrouter.ai/keys) | recommended — first fallback for a DeepSeek outage |
| `KIMI_API_KEY` | `kimi` | [platform.moonshot.ai](https://platform.moonshot.ai/) | optional — second fallback; without it, the chain simply ends at OpenRouter |

Three secrets, three providers, end of list. `GEMINI_API_KEY` **has been removed**
from the repository secrets along with the Gemini entries — reason above.

One DeepSeek key handles both the default provider and escalation: `deepseek` and
`deepseek-pro` have the same `base_url` and the same secret. This is a convenience,
but also a weakness: both go down together when the key or host goes down. That is
why the fallbacks — OpenRouter and Kimi — have **their own keys with their own providers**.

The Kimi key works exclusively on the global host `api.moonshot.ai`. The same key
on `api.moonshot.cn` gets HTTP 401, so the Chinese host is not in the configuration
and should not be.
## Where secrets live on a personal account

This question has one inconvenient answer, so I am stating it directly, with proof.

### There are no Actions secrets at the personal account level

GitHub documentation lists **three** levels of Actions secrets, and not a single one
is the user level: "Secrets allow you to store sensitive information in
your **organization, repository, or repository environments**"
([docs](https://docs.github.com/en/actions/concepts/security/secrets)).
Sharing a single entry across repositories is provided **exclusively** by the
organization level, along with an access policy selecting repositories.

I also checked this against the API, because documentation can be incomplete. The difference in
response codes is decisive:

| Request | Response | What it means |
|---|---|---|
| `GET /user/actions/secrets` | **404** Not Found, generic `documentation_url` | endpoint **does not exist** |
| `GET /users/dudziakm/actions/secrets` | **404** | same thing |
| `GET /user/codespaces/secrets` | **403** "Must have admin rights to Repository", with `documentation_url` pointing to `rest/codespaces/secrets#list-secrets-for-the-authenticated-user` | endpoint **exists**, only the token scope was missing |

In other words, user-level secrets do exist, but **only for Codespaces**—and
that is a different store that Actions does not read. The `dudziakm` account is `type=User`
and does not belong to any organization (verified: `GET /user/orgs` returns an empty
list), so the organization level is currently unavailable.

**Conclusion: on a personal account, it is impossible to share an Actions secret across
repositories other than by creating an organization.** An alternative worth knowing about
so as not to waste time on it: `secrets: inherit` in reusable workflow calls is **not**
a workaround—it inherits secrets visible to the calling repository, so the secret must
still exist there.

### Recommended layout: one secret in the controlling repo

```
dudziakm/dep-automation  (public, controlling repo)
├── secrets: DEEPSEEK_API_KEY, OPENROUTER_API_KEY,  <- only place with keys
│            KIMI_API_KEY
├── ai/                                             <- provider layer
└── agent workflow (NOT deployed yet)               <- runs from here, reaches into other repos via token

remaining repositories
└── without any AI key
```

```bash
gh secret set DEEPSEEK_API_KEY   --repo dudziakm/dep-automation
gh secret set OPENROUTER_API_KEY --repo dudziakm/dep-automation
gh secret set KIMI_API_KEY       --repo dudziakm/dep-automation
```

The AI key resides in one repo and only there. Instead of copying it to 100 repositories,
we copy **invocations**: the agent workflow runs in `dep-automation`, and inspects
the target repository using a token.

### Token reaching into other repos — specific permissions

Fine-grained PAT, not classic. The permission names below are exactly those
that GitHub displays in the token creation form:

| Permission | Level | Specifically why |
|---|---|---|
| **Metadata** | Read | mandatory, GitHub automatically includes it with every other repo permission |
| **Contents** | Read | checkout of the target repository, reading manifests |
| **Actions** | Read | reading the log of a failed run (`gh run view --log-failed`) |

And nothing more. In particular, do **not** grant:

- **Pull requests: Write** — the agent has no right to open or comment on PRs.
  As long as the output is produced as an artifact, this permission is unnecessary.
- **Contents: Write** — no write access is the only hard guarantee that the model will not
  commit anything to `main`.
- **Checks** — here, the limitation of fine-grained PATs actually works in our favor:
  such a token **cannot** call the Checks API
  ([docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#fine-grained-personal-access-tokens-limitations)),
  so it cannot be used to set a status that merge decisions rely upon.

Set the repository scope to **Only select repositories** and list specific ones,
not "All repositories". Ultimately, the token is stored in a secret of the controlling repo,
e.g., `DEP_AGENT_TOKEN`, and is passed exclusively to the step that needs it.

### Rotation and what breaks when the token expires

- **Expiration period**: 1 to 366 days; "no expiration" is technically possible
  and **should not be selected**. A reasonable cycle is 90 days with a calendar
  reminder—GitHub sends a notification about upcoming expiration, but it goes to
  email, not CI.
- **Zero-downtime rotation**: generate a new token, `gh secret set DEP_AGENT_TOKEN
  --repo dudziakm/dep-automation` (overwrites in place, workflow requires no
  changes), verify with a single manual run, and only then revoke the old one.
  The order is important: secrets are read at the time the run is **queued**,
  so an already running workflow will finish using the old value.
- **When it expires**: the agent workflow starts receiving `401 Bad credentials` on
  target repository checkout and **fails with an error**. This behavior is
  acceptable because the agent is not a gate—its failure neither blocks nor
  passes any PR. Nothing "passes silently"; there is simply no diagnosis.
- **Surprise revocation**: GitHub automatically deletes tokens unused for a year, and
  a fine-grained PAT pushed to a public repo or gist is **revoked automatically**.
  The second point is a real risk because `dep-automation` is public—which is why
  the token must never end up in a file, only in a secret.
- **AI keys are rotated separately**, at the providers. These are two independent cycles
  and there is no point in coupling them.

### Drawbacks of this layout that I do not intend to gloss over

1. **The token is tied to an individual.** The fine-grained PAT belongs to the
   `dudziakm` account and "becomes inactive if the user loses access to the resource"
   ([docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)).
   The target solution is a **GitHub App** — short-lived installation tokens,
   independent of the user. The plan already foresees an App for Renovate, so the
   same mechanism can be reused.
2. **Limit of 50 fine-grained PATs per account** ([docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)).
   Inconsequential with one token for this task, but it rules out the "token
   per repository" pattern for 100 repos.
3. **Centralization is a single point of failure and a single point of compromise.** Anyone
   who gains write access to `.github/workflows/` in `dep-automation` will gain
   access to all secrets in this repo. Therefore, it is worth keeping branch protection
   on `main` in this repo and reviewing workflow changes with extra care.
4. **Actions minutes count for private repositories.** The Free account has 2000
   minutes per month ([docs](https://docs.github.com/en/billing/reference/product-usage-included));
   runs in public repositories are free. An agent triggered manually and
   infrequently will not come close to the limit, but automation fired on every failed
   build across several dozen private repos will. This is an additional argument for
   `workflow_dispatch`.
5. **The controlling repo is public.** For the `ai/` layer itself, this is irrelevant
   because it contains no secrets (CI enforces this), and as a bonus it simplifies the template:
   the second checkout of `dudziakm/dep-automation` does not require a token. But every
   prompt and every path hardcoded into the workflow is public — logs
   from private repos must never end up in any artifact of this repo.

### When creating an organization is worth it after all

If the number of places requiring the key grows, an organization is the only
mechanism that provides **a single entry for multiple repositories** along with an access
policy. One must understand what is lost in the process: repositories must be transferred,
and GitHub Free for organizations describes private repositories as having a
"limited feature set" ([docs](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)).
**I have not empirically verified** whether organization secrets work for private
repos on the free organization plan — GitHub documentation does not list them
among the features reserved for the Team plan, but I have encountered secondary sources
claiming otherwise. Without an organization account, I cannot settle this, so
I leave it open rather than stating it as fact. With two secrets in a single repo,
this decision is premature anyway.

### How the script protects the key

- The key is read **only** from the environment variable named in the
  configuration, via `printenv`.
- The key **does not enter process arguments**: the URL and authorization header go to
  `curl` via a configuration file on stdin (`curl --config -`). Verified: during
  invocation, the key is not visible in `ps -Ao args`.
- Every error message passes through the `scrub` function, which wipes the key
  value from it before the text goes to stderr.
- A key containing unusual characters (quote, backslash, newline) is
  **rejected** rather than forcedly quoted — a clear error is better than a broken header.
## `ai-call.sh` Usage

```bash
ai/scripts/ai-call.sh --help      # full list of options
ai/scripts/ai-call.sh --list      # what is in the configuration
ai/scripts/ai-call.sh --check     # which secrets are set (without values)
echo "prompt" | ai/scripts/ai-call.sh --dry-run   # what it would do, without network

# real invocation: prompt from file or stdin, response to stdout
ai/scripts/ai-call.sh prompt.txt > odpowiedz.md
```

Diagnostics (which provider, which model, how many tokens) go to **stderr**, the model response itself to **stdout** — so `> file` gives a clean response.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | success, response to stdout |
| 1 | usage error or configuration error |
| 2 | missing required tool (`jq`, `curl`) |
| 3 | no provider in the chain has a secret set |
| 4 | all providers in the chain failed |

### Pitfall you will run into: thinking tokens eat the response budget

All models in this configuration "think" by default, and **thinking tokens count as output tokens and are included in `max_tokens`**. This also applies to DeepSeek: thinking mode is the default for both V4 variants (its model table states this). For Gemini 3 models, thinking **cannot be turned off** — Google documentation states this directly ("Reasoning cannot be turned off for Gemini 2.5 Pro or 3 models").

Practical effect: with a `max_tokens` that is too small, you get **HTTP 200 and an empty response** with `finish_reason=length`. Measured live on this script, on the prompt "answer in exactly one word":

| Model | Thinking tokens | Total response tokens |
|---|---|---|
| `deepseek-v4-flash` | 42 | 51 |
| `deepseek-v4-pro` | 67 | 75 |
| `google/gemini-3.7-flash` via OpenRouter | 124 | 131 |

An earlier measurement on `gemini-3.7-flash` (108 thinking tokens per 1 content token) with `max_tokens: 16` gave an empty response, and with 256 a correct one — which means a single-word response can cost two orders of magnitude more tokens than its length suggests.

That is why `max_tokens` in `providers.json` is 4096, not a few hundred, and `ai-call.sh` with empty content reports this explicitly and provides the reason instead of pretending success.

`reasoning_effort` (`minimal`/`low`/`medium`/`high`) can be set using the `--reasoning-effort` flag, but this **limits**, does not disable: with `low` and `max_tokens: 64`, the model still used 61 tokens for thinking and did not manage to respond.
## How this maps to `github/gh-aw`

The plan envisions the [`github/gh-aw`](https://github.github.com/gh-aw/) framework
(GitHub Agentic Workflows) in Phase 7. I checked its documentation — the providers from this
layer map to it as follows:

| Provider here | Path in gh-aw | Notes |
|---|---|---|
| `deepseek`, `deepseek-pro`, `openrouter`, `kimi` | **no built-in engine** | workaround route: `engine: copilot` in BYOK mode, via `COPILOT_PROVIDER_BASE_URL`, `COPILOT_PROVIDER_API_KEY`, `COPILOT_MODEL`, and `COPILOT_PROVIDER_TYPE: openai` — i.e. exactly the same three values as here. For Kimi, a fourth matter arises: `temperature` must remain `1`, and this route does not expose it as a separate field — **untested** whether it can be enforced there |

The built-in gh-aw engines are `copilot`, `claude`, `codex`, `gemini`, and `pi`.
**None of the four providers in this layer are on this list**, so the entire
layer requires the BYOK route in gh-aw, rather than a built-in engine. This is a known cost
of the decisions made, not a surprise — and actually low, because BYOK accepts the same
three values (`base_url`, key, model) that we keep in
`providers.json` anyway.

The only built-in engine that this layer could reach for directly is `gemini`
— and we opted out of it precisely for the reasons described above. It is worth knowing this,
because when deploying gh-aw it is easy to consider the built-in engine a shortcut; here,
it would be a route through the paid Gemini tier.

The security mechanisms that gh-aw relies on (and which are the reason why
the plan chose it): the agent job is **read-only and sandboxed** by default, outbound
traffic passes through a firewall with an allowlist of hosts, and writes to
GitHub go through separate, validated `safe-outputs` jobs with narrow
permissions. This does not change the principle from the top of this document: even in gh-aw, the agent
proposes, and CI is the gate.
## Workflow template — disabled by default

[`templates/ai-fix-build.yml`](templates/ai-fix-build.yml) is a template to
be copied to the target repo. **It is located in `ai/templates/`, not in
`.github/workflows/`, so it will never run on its own.** At this stage, it
is optional and intentionally inactive — no repo receives it automatically.

Hard assumptions of the template:

- `on: workflow_dispatch` — manual run only, no trigger from a PR
  or from a `workflow_run` event,
- `permissions: contents: read` and nothing more — no `pull-requests: write`, no
  path whatsoever to merge,
- `persist-credentials: false` in checkout. This is not cosmetic: through this exact
  path (`.git/config`), researchers exfiltrated a token from Google's Gemini CLI
  workflow and achieved a push to `main`,
- the output comes out as a **patch artifact**, not as a commit. Applying the patch is
  a separate, conscious human decision or a separate job with its own token.
## Current model identifiers and costs

As of 18.08.2026. Prices per million tokens, in USD.

| Role | Provider | Model | Input | Output | Free tier | Source |
|---|---|---|---|---|---|---|
| **default** | DeepSeek | `deepseek-v4-flash` | 0,22 / 0,44 | 0,66 / 1,32 | no | [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing/) |
| **escalation** | DeepSeek | `deepseek-v4-pro` | 0,66 / 1,32 | 1,98 / 3,96 | no | [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing/) |
| **fallback** | OpenRouter | `google/gemini-3.7-flash` | 0,375 | 1,875 | no | [openrouter.ai/api/v1/models](https://openrouter.ai/api/v1/models) |
| **fallback** | Kimi (Moonshot) | `kimi-k2.7-code` | 0,95 (0,19 cache hit) | 4,00 | no | [platform.kimi.ai/docs/pricing/chat-k27-code](https://platform.kimi.ai/docs/pricing/chat-k27-code) |

Four rows, four active entries — the table matches one-to-one with
`providers.json`. No row describes a model that the layer cannot invoke
today.

DeepSeek provides two prices because it has hourly rates: the first is off-peak,
the second is peak. Peak is 01:00–04:00 and 06:00–10:00 UTC. Input cache
hits are extremely cheap with it (`$0,007`–`$0,014` per million for Flash,
`$0,022`–`$0,044` for Pro), which matters for an agent repeatedly reading the same
build log.

Cost breakdown justifying the choice: the default `deepseek-v4-flash` is
**about seven times cheaper on input and more than eleven times on output** than
`gemini-3.6-flash`, which was the default provider in the first version of this
layer. This difference decided the switch to DeepSeek and is a separate reason —
alongside the top-up cost — why Gemini did not return here.

I pulled the DeepSeek and OpenRouter prices from machine-verifiable
sources: the DeepSeek table from the pricing page, the OpenRouter price directly from
`GET /api/v1/models` (`prompt = 0.000000375`, `completion = 0.000001875` per
token, i.e. 0,375 and 1,875 per million). I took Kimi's pricing from the pricing pages
of individual models on `platform.kimi.ai`, in the `.md` version — column headers are
explicit there (`Input Price (Cache Hit)`, `Input Price (Cache Miss)`, `Output
Price`), so I did not have to guess which number is which.

**Kimi is the most expensive active entry in this layer, and that is deliberate.**
It costs 4.3× more on input and 6× more on output than the default Flash. What is
being paid for here is not the price, but independence from the two other providers — and
you only pay when both fail, because Kimi is the last link in the chain.
## What was empirically confirmed and what was not

Tests performed on 18.08.2026 on this script and this configuration. All three
layer keys — `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY`, and `KIMI_API_KEY` — were
available in the environment. The Gemini key was available only for the duration of the free
tier measurement, after which Gemini was removed from the layer.

### Confirmed by execution

The entire chain after switching to DeepSeek was run live:

| What | Result |
|---|---|
| **Default invocation, without any flags** | `provider=deepseek model=deepseek-v4-flash`, HTTP 200, correct content, `exit 0` |
| **`--escalate`** | `provider=deepseek-pro model=deepseek-v4-pro`, HTTP 200, correct content, `exit 0` |
| **Fallback to backup on DeepSeek failure** | invalid `DEEPSEEK_API_KEY` substituted: both DeepSeek entries dropped out on HTTP 401, `openrouter` responded correctly, `exit 0` |
| **Fail-closed when all keys are missing** | `exit 3` with a message, never `exit 0` |
| **Positive control of the same test** | with keys, the same invocation ends with `exit 0` and returns content — meaning test 3 measures the lack of keys, not something else |
| DeepSeek model list | `GET https://api.deepseek.com/models` → HTTP 200, exactly two: `deepseek-v4-flash`, `deepseek-v4-pro` |
| Absence of a third, more powerful DeepSeek model | attempting `deepseek-v4`, `deepseek-v4-pro-thinking` → HTTP 400 with provider message listing only these two |
| Old aliases `deepseek-chat` and `deepseek-reasoner` | still accepted, but **both map to `deepseek-v4-flash`** (visible in the response `model` field) — therefore canonical names are in the configuration |
| OpenRouter `https://openrouter.ai/api/v1/chat/completions` | HTTP 200, correct content, model `google/gemini-3.7-flash` |
| Compatibility of all four active entries with the OpenAI format | yes — the same code without a single per-provider branch |
| Switching provider without code changes | yes, via three methods: `-p` flag, `AI_PROVIDERS_CONFIG` variable, editing `.lancuch.domyslny` |
| Key does not appear in `ps -Ao args` | confirmed during live invocation |
| Key does not appear in error message | fake key substituted: **0 occurrences** in entire output, despite two authorization error messages |
| **Gemini free tier is not enough for this layer** | with a free tier key: `gemini-3.6-flash` → HTTP 200, but `gemini-3.1-pro-preview` → HTTP 429 with `-FreeTier` metrics and `limit: 0`. The escalation model had a **zero** quota, so Gemini was removed instead of being left disabled |
| Exit codes 1, 3, and 4 | invoked intentionally and consistent with the documentation above |
| Thinking tokens consume `max_tokens` | measured on both DeepSeek models and on Gemini via OpenRouter — table above |
| New rules in `validate-ai.yml` catch regression | control test on three intentionally broken configurations (default set to disabled, active outside chain, typo in name) — each yielded red, actual state green |
| **Kimi: key and host** | `GET https://api.moonshot.ai/v1/models` → HTTP 200, twelve models. Same key on `api.moonshot.cn` → HTTP 401, therefore only the global host is in the configuration |
| **Kimi: all five K2.5+ models actually respond** | `kimi-k2.5`, `kimi-k2.6`, `kimi-k2.7-code`, `kimi-k2.7-code-highspeed`, `kimi-k3` — each HTTP 200 on chat invocation. Presence on the `/models` list did not guarantee this, so I checked each separately |
| **Kimi rejects `temperature: 0`** | HTTP 400 "invalid temperature: only 1 is allowed for this model" on `k2.5`, `k2.6`, and `k2.7-code`. Without overriding the parameter, Kimi would not have responded a single time — this was a real bug to fix, not cosmetics |
| **Kimi: model selection resolved on a real task** | `npm ci` log with a peer dependency conflict after bumping `vite` 5→7. `k2.7-code` and `k3` gave a correct diagnosis, `k2.6` as well but at 3.4× higher token cost, `k2.5` and `-highspeed` returned **empty** with `finish_reason=length` — table above |
| **Kimi: limit of 3 requests per minute** | HTTP 429 "request reached organization max RPM: 3" live, according to the threshold table in the pricing |
| **Kimi: spread of thinking tokens** | seven runs of the same prompt on `kimi-k2.7-code`: 552–1336 thinking tokens. `temperature` locked at 1.0, so repeatability cannot be enforced |
| Default invocation **still** goes to DeepSeek after adding Kimi | without flags: `provider=deepseek model=deepseek-v4-flash`, HTTP 200, `exit 0`. Checked specifically so it wouldn't turn out that adding a backup silently switched the default |
| Other providers did not receive Kimi parameters | `--dry-run`: `deepseek`, `deepseek-pro`, and `openrouter` still `max_tokens=4096 temperature=0`, only `kimi` has `16384` and `1` |
| `-p kimi` returns content | HTTP 200, `finish=stop`, `exit 0` |
| Fallback down the chain all the way to Kimi | corrupted `DEEPSEEK_API_KEY` and `OPENROUTER_API_KEY` substituted: first three entries dropped out on HTTP 401, `kimi` responded correctly, `exit 0` |
| Kimi key does not appear in error message | fake key substituted: HTTP 401 "Invalid Authentication", **0 occurrences** of the key in stdout and stderr, `exit 4` |
| Leak scanner in CI covers Kimi key format | key matches existing pattern `sk-[0-9a-zA-Z]{20,}`, so the rule required neither expansion nor weakening |
| `validate-ai.yml` rules catch regression — fourteen cases | validation step taken directly from workflow and run against fourteen configuration variants. **Two were expected to pass and passed**: actual state and a new provider disabled and kept outside the chain (this is allowed). **Twelve were expected to show red and showed red**: Kimi disabled but in chain, Kimi active but outside chain, entire `zapas` role removed with active OpenRouter, typo `kimmi` in list, `lancuch.domyslny` and `lancuch.eskalacja` pointing to **deleted** Gemini entries, missing `base_url`, `temperature` as string, `max_tokens` as string, provider name with a space, disabled provider added to chain, active provider outside chain |
| Rules do not trigger too broadly | the two green cases above are more significant here than the twelve red ones: if the rule "active must be in chain" were written too aggressively, it would fail on a legitimate disabled entry. It does not fail |
| Gemini removal is **complete** | `lancuch.domyslny = "gemini-flash"` and `lancuch.eskalacja = "gemini-pro"` now yield "points to a nonexistent provider", and not "has status disabled" — meaning the entries are truly absent from the configuration, rather than merely set aside |
| Control test detected a **real bug in the new rule** | the first version of the "active outside chain" check had a scope error in jq (`index(.key)` referred `.key` to the chain array, not to the provider entry) and failed on a **valid** configuration. Without positive control, all other cases would show red for the wrong reason |
| Rules for **lists** in the chain also work in real CI | two runs on a temporary branch, both red with the proper annotation: typo `"kimmi"` in the backup list → "lancuch.zapas wskazuje na nieistniejacego providera 'kimmi'", and Kimi active after removal from the list → "providerzy ze statusem 'aktywny' poza lancuchem: kimi". It was the second of these rules that previously had a bug in jq, so I specifically did not want to leave it verified only locally. Branch deleted after test. |
| Real CI catches regression **after Gemini removal** | another temporary branch with `lancuch.domyslny = "gemini-flash"`: `validate ai layer` run red with annotation "lancuch.domyslny points to a **nonexistent** provider 'gemini-flash'". The message content is proof in itself here — had the entry only been disabled instead of removed, CI would have said "has status 'disabled'". Branch deleted after test. |
| Lack of Actions secrets at personal account level | `GET /user/actions/secrets` → **404** (endpoint does not exist), `GET /user/codespaces/secrets` → **403** (exists, missing scope). Account `dudziakm`: `type=User`, `GET /user/orgs` → empty list |
| `reasoning_effort: "none"` / disabling thinking for Gemini 3 | **does not work** — OpenRouter responds with HTTP 400 "Reasoning is mandatory for this endpoint and cannot be disabled", which matches Google documentation |

### Unconfirmed and why

| What | Why not |
|---|---|
| Whether `deepseek-v4-pro` actually **fixes builds better** than Flash | I confirmed that it exists, responds, and is priced and rate-limited differently. That it yields better fixes — no; that requires a series of real failed builds, not a single control question. |
| Whether `kimi-k2.7-code` **actually fixes builds better** than `kimi-k2.6` or `kimi-k3` | same caveat. I measured cost, time, and that all three gave a **correct** diagnosis for one case. I base the choice on price per response, token consumption, and the vendor's declared specialization — **not** on quality advantage, as a single task is not enough for that. |
| Whether `kimi-k2.5` and `-highspeed` are **permanently** worse, or just hit a bad run | `temperature` is locked at 1.0, so results are non-deterministic, and I ran each of them on this task **once**. Empty responses may be bad luck rather than a property of the model. Resolving this requires a series, which the limit of 3 requests per minute practically does not allow. |
| Whether `max_tokens: 16384` for Kimi is **needed** | `kimi-k2.7-code` across seven runs fit into 4096 with room to spare (max. 1336 thinking tokens). The higher limit is a buffer for longer logs and the observed variance, not a response to a failure of this specific model. It costs nothing until used. |
| Kimi's behavior on a **real** failed build from a real repo | I tested on a manually assembled `npm ci` log (378 tokens). Real logs are longer and messier; neither times nor token consumption necessarily translate one-to-one. |
| Whether the BYOK route in `gh-aw` can enforce `temperature: 1` for Kimi | the BYOK mapping exposes `base_url`, key, and model. I did not find a field for `temperature` in the documentation, and I did not run `gh-aw` itself — so I do not know whether Kimi can be called through it without an HTTP 400 error. |
| Whether Kimi limits can be raised for this account | the threshold table states that the limit increases with total top-ups (Tier1 at $10 is 200 RPM). I did not top up the account, so I rely solely on the price list. |
| Whether organization secrets work for private repos on the organization free plan | lack of an organization account to check this on. GitHub documentation does not list them among Team-only features, secondary sources claim otherwise. |
| Behavior of workflow template in GitHub Actions | not run — it is disabled and located outside `.github/workflows/`. Only YAML syntax validity was verified. |
| Integration with `gh-aw` | not run. The mapping in the table above comes from gh-aw documentation, not from a working workflow. |
| Behavior of the `DEP_AGENT_TOKEN` token when accessing other repos | no such token was created or used. The permission set in the secrets section comes from GitHub documentation and the fine-grained PAT permission list, not from a working run. |

**First thing to do after adding any new provider** —
exactly this path caught the `temperature` restriction with Kimi before the entry was added to the
chain:

```bash
export NOWY_API_KEY=...   # do not write this into any file in the repo
ai/scripts/ai-call.sh --check
echo 'Odpowiedz jednym slowem: OK' | ai/scripts/ai-call.sh -p nowy
```

The `-p` flag allows checking an entry **without** touching the chain, so verifying a
new provider never has to switch the default. If the call returns
HTTP 400, read the message literally: with Kimi, that is where it turned out that
`temperature: 0` is rejected and that the provider needs its own
`parametry` block. Only when `-p` returns content does it make sense to add the name to
`.lancuch` — CI will not allow half-done work in either direction anyway.
