# Plan: Docs capability contract + Confluence reference adapter

## Summary
- **Contract** (`doc/architecture/capability-adapters.md`, new docs section): read-only `describe`, `doc-search <query> [--limit N]`, `doc-read <ref> [--section H] [--max-chars N]`, `doc-stat <ref>`; same exit codes and three rules as the tracker. `describe` gains an optional `link_pattern` (spots page links in prose; `ref_pattern` alone can't — a bare page id looks like a GitHub issue number).
- **Caps:** search ≤10 results by default (max 25), excerpts ≤300 chars; `doc-read` ≤24,000 chars by default (max 100,000), always emits `truncated`, full length, and the page's headings so a caller can re-ask for one section.
- **Confluence adapter** `tools/adapters/docs/confluence.sh` (curl + jq): reads pages as ADF and flattens to a Markdown subset with jq (reusing the Jira adapter's ADF approach); section via `--section` or a URL's `#anchor`. Credentials: `CONFLUENCE_EMAIL`/`CONFLUENCE_API_TOKEN` fall back to the Jira pair only when **both** are unset; site falls back to `JIRA_BASE_URL`.
- **Gates:** conformance checker generalized by `describe.capability`, run over `tools/adapters/*/*.sh`; its mutation test gains docs mutations; new 22nd gate `docs-adapter` feeds a canned page through a fake curl to prove conversion, section cutting and truncation. Gate-count prose updated.
- **Sessions:** 5 commands (next-step, plan, implement, pre-pr, process-pr), repo + template: one extra line in an existing shell block (prints nothing when absent) + one short paragraph with the three triggers. No trigger → no call.
- **Docs:** process doc §2.16, overview, CLAUDE.md, engineering-practices, architecture index; roadmap items merged into one ticked line. No new ADR (0007 covers it).
- **Risk:** some Confluence API details are from memory (flagged below); the live test confirms them — needs the user to export Atlassian credentials.
- **Deviations:** requirement 5 goes 4 → 5 commands (adds `/cdd-plan`); gate count 21 → 22.

## Approach
Contract first, then the adapter, then the gates, then the prompts, then docs. Steps:

1. **Contract doc** — `doc/architecture/capability-adapters.md`: retitle to cover both capabilities (e.g. "Capability adapters: the tracker and docs contracts"), make the intro and "What an adapter is"/exit codes/`describe` sections capability-neutral where they say "tracker", and add a `## The docs verbs` section (shapes below, in "Shapes to pin"), `## The Confluence adapter` section (config table, fallback rule, format, limits), update `## The conformance gate` for per-capability probes and the new `docs-adapter` gate, and a short "When a session calls it" subsection (the three triggers + announcement rule applied to docs). The `describe` field table gains `link_pattern` (optional; docs only today).
2. **Adapter** — new `tools/adapters/docs/confluence.sh`, executable (mode 755), modelled line-for-line on `tools/adapters/tracker/jira.sh` (header comment shape, `err`, `json_escape`, `require_config`, `require_tools`, `scratch`, curl `--config -` credential passing, dispatch-order rule). Detail in "Adapter design" below.
3. **Conformance checker** — `scripts/adapter-conformance-check.sh`: read `.capability` from `describe` and branch on a per-capability table (contract verbs, usage-error probe, missing-backend probe); validate optional `link_pattern` as an ERE when present; default subject unchanged. `scripts/ci.sh` `gate_adapter_conformance` loops `tools/adapters/*/*.sh`.
4. **Checker's mutation test** — `scripts/adapter-conformance-assert.sh`: add a docs section (control + mutations), update the header comment and final count line.
5. **Fixture gate** — new `scripts/docs-adapter-assert.sh` + registry line `docs-adapter|jq|…` in `scripts/ci.sh` + `gate_docs_adapter()`.
6. **Session wiring** — five commands × two copies (`.claude/commands/` and `template/.claude/commands/`): `cdd-next-step.md`, `cdd-plan.md`, `cdd-implement.md`, `cdd-pre-pr.md`, `cdd-process-pr.md`. Keep repo and template text identical so `drift` stays green.
7. **Process doc + other docs + roadmap** (see "Doc and roadmap edits").
8. **Live test** — ask the user to export credentials, run `doc-read` (whole page and `--section CCA3`), `doc-stat`, `doc-search`, against the Notes page. Fix whatever the live payload contradicts (see flagged External findings).
9. `./scripts/ci.sh` green.

### Shapes to pin (contract)
- `describe`: `{"capability":"docs","contract":1,"backend":"confluence","ref_pattern":"…","link_pattern":"…","verbs":["doc-search","doc-read","doc-stat"]}` (+ optional `search_scope`, e.g. `"TT @ avy-wiki.atlassian.net"` when `CONFLUENCE_SPACE_KEYS` and a base URL are set — human-readable only, omitted otherwise; mirrors `create_target`).
  - `ref_pattern` (required, anchored ERE): what `doc-read`/`doc-stat` accept. Confluence: a numeric page id or a page URL: `^([0-9]+|https?://[^[:space:]]+/wiki/[^[:space:]]*pages/[0-9]+[^[:space:]]*|https?://[^[:space:]]+/wiki/[^[:space:]]*[?&]pageId=[0-9]+[^[:space:]]*)$`.
  - `link_pattern` (optional, unanchored ERE): finds a reference *inside prose*. Sessions use it for trigger 1; absent → trigger 1 never fires. Confluence: page URLs only (never bare ids — `^#?[0-9]+$` is the tracker's shape). When a base URL is configured, restrict the host to it (escape dots); otherwise `https?://[A-Za-z0-9.-]+\.atlassian\.net/wiki/[^[:space:])>"]*(pages/[0-9]+|pageId=[0-9]+)[^[:space:])>"]*`. Built with printf + `json_escape`, no jq (describe stays hermetic and jq-free, as in `jira.sh:233-248`).
- `doc-search <query> [--limit N]` → array, `[]` when empty: `{"ref":"<id>","title":"…","url":"…","excerpt":"…","updated_at":"…Z","space":"<space name>"}` (`space` omitted if absent). Default limit 10, max 25 (larger → exit 2). Excerpt ≤300 chars, whitespace-collapsed, highlight markers stripped; an excerpt cut at the cap ends in `…`. Pages only (`type = page`).
- `doc-read <ref> [--section <heading>] [--max-chars N]` → object: `{"ref":"<id>","title":"…","url":"…","version":17,"updated_at":"…Z","format":"markdown","content":"…","truncated":false,"content_chars":5123,"sections":["System Minimum Requirements",…],"section":"CCA3"}`. `content_chars` = length of the full (or full-section) content before capping; `truncated` always present (bool, not null); `sections` = all headings of the page, in order, capped at 100 entries; `section` present only when one was requested. Default cap 24000 chars, `--max-chars` 1..100000 (outside → exit 2). On truncation, cut at the cap and append nothing inside `content` — the flag is the signal; also print one stderr line ("truncated at N of M chars; use --section …").
  - Section selection: from the heading whose normalized text equals the normalized request, up to (not including) the next heading of level ≤ its own. Normalize = lowercase, drop every non-alphanumeric char (so `Installation procedure steps`, `installation-procedure-steps` and a URL fragment `#Installation-procedure-steps` all match). Source of the request: `--section` if given, else the URL fragment of the ref if any, else whole page. Not found → exit 1, stderr lists the available headings.
- `doc-stat <ref>` → `{"ref":"<id>","title":"…","url":"…","version":17,"updated_at":"…Z"}`. No body fetched.
- Exit codes: unchanged table. Specifics: no/invalid ref, missing query, bad `--limit`/`--max-chars`, unknown option → 2 (before config); config missing → 4; curl/jq missing → 4; 401/auth-failed/404/other → 1; section not found → 1; URL ref whose host differs from the configured site → 1 naming both hosts.

### Adapter design (`tools/adapters/docs/confluence.sh`)
- **Config (env only):**
  | Var | Meaning |
  | --- | --- |
  | `CONFLUENCE_BASE_URL` | site, `https://<site>.atlassian.net` (bare host gets `https://`; a trailing `/wiki` or `/` is stripped; the adapter appends `/wiki`). Falls back to `JIRA_BASE_URL`. |
  | `CONFLUENCE_EMAIL` + `CONFLUENCE_API_TOKEN` | credentials. **Pair fallback:** if *both* are unset and both `JIRA_EMAIL` and `JIRA_API_TOKEN` are set, use the Jira pair and say so once on stderr ("using JIRA_EMAIL / JIRA_API_TOKEN; CONFLUENCE_* unset"). If exactly one Confluence var is set, no fallback — exit 4 naming the missing one (never mix one var from each set). |
  | `CONFLUENCE_SPACE_KEYS` | optional, comma-separated space keys `doc-search` is restricted to (`space in ("TT","ENG")`); unset → site-wide. Validate each key `^[A-Za-z0-9_~-]+$`, else exit 4. |
  Site fallback is independent of the credential fallback (Atlassian API tokens are account-level, so a Jira pair works on a different site of the same account). A missing site after fallback → exit 4 naming `CONFLUENCE_BASE_URL` (hint mentions the `JIRA_BASE_URL` fallback). `config_hint` style as `jira.sh:85-94`.
- **Binding:** `.cdd/docs` execs it, exporting only non-secret coordinates (`CONFLUENCE_BASE_URL`, `CONFLUENCE_SPACE_KEYS`). Does not self-install (per-project binding, same reason as Jira). Confluence Cloud only.
- **Ref normalization** (global `$REF`/`$FRAGMENT`, not `$(...)`, same reason as `jira.sh:64-80`): numeric id as is; URL → id from `/pages/([0-9]+)` or `pageId=([0-9]+)`, fragment from `#…` (URL-decoded minimally: `+`/`%20` → space is enough, normalization drops the rest). Tiny links (`/wiki/x/…`) are not accepted (exit 2 via ref_pattern) — documented limitation. Host check after config is resolved.
- **HTTP:** copy `jira_request` (`jira.sh:136-172`) as `confluence_request`: credential via `curl --config -` on stdin, 401 or `X-Seraph-LoginReason: AUTHENTICATED_FAILED` header → exit 1 "rejected the credentials (check CONFLUENCE_EMAIL / CONFLUENCE_API_TOKEN, or the JIRA_* pair it fell back to)"; 404 → "no such page, or no access"; error detail from `.message // .errors[]?.title` (Confluence error shape, verify live).
- **Endpoints** (see External findings for confidence):
  - `doc-read`: `GET /wiki/api/v2/pages/<id>?body-format=atlas_doc_format`. Title `.title`, version `.version.number`, updated `.version.createdAt | iso_utc`, url `._links.base + ._links.webui` (fallback `$BASE/wiki` + webui if `base` absent). ADF at `.body.atlas_doc_format.value` — **a JSON string**: `(if type=="string" then fromjson else . end)`.
  - `doc-stat`: `GET /wiki/api/v2/pages/<id>` (no body-format).
  - `doc-search`: `GET /wiki/rest/api/search --get --data-urlencode "cql=type = page AND text ~ \"<q>\"[ AND space in (…)]" --data-urlencode limit=N --data-urlencode excerpt=highlight`. Escape `\` and `"` in the query for CQL. Map `.results[]`: ref `.content.id`, title `.content.title // .title` (strip highlight markers from title too), url `._links.base + .url` (`.url` is site-relative webui path; fallback `.content._links.webui`), excerpt `.excerpt` with `@@@hl@@@`/`@@@endhl@@@` removed, HTML entities `&amp; &lt; &gt; &quot; &#39;` decoded, whitespace collapsed, cut to 300; updated `.lastModified | iso_utc`; space `.resultGlobalContainer.title`.
- **ADF → Markdown (jq):** a new `JQ_LIB` in the Confluence adapter, starting from `jira.sh:181-226` (`iso_utc` copied verbatim; ADF functions adapted — no shared library file, adapters stay single-file). Differences from Jira's `adf_text`: headings → `"#"*level + " " + text`; `codeBlock` → fenced ```` ``` ```` (with `attrs.language` when present); inline `code` mark → backticks; `link` mark → `[text](href)`; `strong`/`em` may be dropped or rendered `**`/`_` (implementer's call, keep simple); `inlineCard` → its url; `expand`/`panel`/`layoutSection`/`blockquote` → recurse into content (blockquote prefixed `> `); media/extension nodes → dropped (or `[attachment]` placeholder); tables → rows joined with ` | ` as in Jira. Empty paragraphs dropped. Sections computed on the top-level `content` array (headings are top-level in ADF; the test page confirms).
  - Truncation in jq: `$full | length` → `content_chars`; `.[0:$cap]`. jq `length` counts codepoints — say "characters" in the doc.
- **describe** reads only env (base URL for `link_pattern` host, `CONFLUENCE_SPACE_KEYS` for `search_scope`) — never jq, never network; `search_scope` omitted unless both a base URL (own or Jira fallback) and space keys are set.
- **Dispatch order:** exactly as `jira.sh:376-447`: args (2) → config (4) → tools (4) → backend. `doc-search` with no query → 2; `doc-read`/`doc-stat` with no ref → 2.

### Conformance checker generalization (`scripts/adapter-conformance-check.sh`)
- After check 1, read `CAPABILITY=$(jq -r .capability)`; `case` table:
  - `tracker`: contract verbs as now (`:39`), usage probe `issue-read` (no args → 2), missing-backend probe `issue-list` (→ 4).
  - `docs`: contract verbs `["doc-search","doc-read","doc-stat"]`, usage probe `doc-read` (no args → 2), missing-backend probe `doc-stat 12345` (valid ref, scrubbed env → 4; must not be 2).
  - anything else → fail "unknown capability".
- Check 2's jq replaces the hardcoded `(.capability == "tracker")` with membership in the known set and uses the capability's verb list; add: `link_pattern`, if present, is a non-empty string and a valid ERE (same grep trick as `:170-173`).
- Checks 5 and 6 use the table's probes; messages name the probe. Final line says "satisfies the <capability> contract".
- The nobackend PATH (`:83-88`) has no jq — fine, the docs adapter's describe must not need it (conformance check 1 enforces that).
- Header comment: say it covers every capability with a published contract.

### Mutation test additions (`scripts/adapter-conformance-assert.sh`)
Add a Confluence section after the Jira one (`:224-247`), same helpers:
- control: unmutated Confluence copy passes;
- describe requires credentials, with fake `CONFLUENCE_*` **and** `JIRA_*` exported (scrub check);
- missing config exits 1 instead of 4 (awk over `require_config()` / whatever the config function is named);
- `link_pattern` not a valid ERE → "not a valid ERE" (or a docs-specific needle);
- declares `doc-publish` (not a contract verb) → "not contract-shaped";
- control: `link_pattern` omitted passes (optional field stays optional).
Update header comment and the final count line (currently "17 mutations, 3 controls") to the new totals. Remember the awk-anchor rule at `:112-121` (no backslashes; use bracket expressions).

### Fixture gate (`scripts/docs-adapter-assert.sh`, gate `docs-adapter`, needs `jq`)
- Scratch dir, stub `curl` first on PATH that: reads its argv, finds the URL (last arg), and `cat`s a fixture chosen by path (`/wiki/api/v2/pages/<id>` with/without `body-format`, `/wiki/rest/api/search`), writes `200` for `-w '%{http_code}'`, writes an empty headers file for `-D`, writes the body to the `-o` path. It must consume stdin (`--config -`) and **assert the token never appears in argv** (grep its own `"$@"` for the fake token → exit 99). Unknown page id → 404.
- Fixtures inline as heredocs: a v2 page JSON whose `body.atlas_doc_format.value` is a JSON **string** of an ADF doc with h2/h3 headings, a bullet list, an ordered list, a code block, a link, an inlineCard; a big page (generated by jq, >24000 chars); a search result with `@@@hl@@@` markers and an entity.
- Run the adapter with `env -i PATH=… HOME=… CONFLUENCE_BASE_URL=https://example.atlassian.net CONFLUENCE_EMAIL=… CONFLUENCE_API_TOKEN=fake-not-a-secret` and assert:
  1. `doc-read <id>`: `format=="markdown"`, contains `## ` headings, fenced code, `[text](href)`; `truncated==false`; `content_chars == (content|length)`; `sections` in order; `updated_at` ends in `Z`; url = base + webui.
  2. `doc-read <id> --section "CCA3"`-style: content starts at that heading and stops before the next same-level heading; `section` echoed; a URL ref with `#Heading-Text` fragment gives the same result.
  3. `--section nope` → exit 1, stderr lists headings.
  4. big page: `truncated==true`, `content|length == 24000`, `content_chars > 24000`; `--max-chars 500` → length 500; `--max-chars 0` and `100001` → exit 2.
  5. `doc-stat` → version/updated_at/title/url, no `content`.
  6. `doc-search foo` → array, excerpt has no `@@@`, ≤300 chars, entity decoded; `--limit 26` → exit 2; CQL sent contains `type = page` and escaped quotes for a query with `"` (stub logs the decoded `cql` it received — `--data-urlencode` values arrive urlencoded in argv as `cql=…` before curl encodes them, so the stub can read them raw).
  7. Credential fallback: CONFLUENCE_EMAIL/TOKEN unset + JIRA_EMAIL/TOKEN set → succeeds and stderr names the fallback; only CONFLUENCE_EMAIL set → exit 4 naming CONFLUENCE_API_TOKEN; no base URL but JIRA_BASE_URL set → uses it.
  8. URL ref on a different host → exit 1.
- Registry line in `scripts/ci.sh` after `adapter-conformance-contract`: `"docs-adapter|jq|the Confluence docs adapter against canned pages: conversion, sections, truncation (offline)"`, plus `gate_docs_adapter() { ./scripts/docs-adapter-assert.sh; }`.
- `scripts/ci-runner-assert.sh` — check whether it pins the registry size or slugs; update if so.

### Session wiring (5 commands × repo + template, identical text)
Existence check — one line appended to a shell block each command already runs; prints only when found, never fails the block:
```bash
for c in .cdd/docs ~/.cdd/adapters/docs; do [ -x "$c" ] && { echo "docs adapter: $c"; break; }; done; true
```
Where it piggybacks:
- `cdd-next-step.md`: the §0a freshness block (`.claude/commands/cdd-next-step.md:48-52`) — runs in every mode (the §0 tracker block at `:22-24` only matters for classification).
- `cdd-plan.md`: step 1 path block (`.claude/commands/cdd-plan.md:11-16`).
- `cdd-implement.md`: §1 path block (`.claude/commands/cdd-implement.md:9-14`).
- `cdd-pre-pr.md`: §0 base-branch block (`.claude/commands/cdd-pre-pr.md:7-10`).
- `cdd-process-pr.md`: §1 `git rev-parse --abbrev-ref HEAD` block (`.claude/commands/cdd-process-pr.md:11-13`).
Paragraph (≈4–6 lines, placed right after that block or where the session reads its inputs), same core text in all five, one clause tailored per command (next-step: platform context while scoping, and a page central to the task may be excerpted into the handoff's `## Notes`; plan: integration contracts while exploring — record what it read under `## External findings` with the page ref and version; implement: the contract it codes against; pre-pr: checking the change against an external standard or spec; process-pr: a page a reviewer cites). Core content:
- "If that printed nothing, skip this — no call, no line." (i.e. prints nothing when absent)
- It is not called by default. Triggers, strongest first: (1) a reference matching the adapter's `describe` `link_pattern` in the handoff, issue, review comment or user message; (2) a line in `CLAUDE.md` saying what lives in the doc store, matching this task; (3) the task depends on an external system the repo does not document. No trigger → no lookup.
- When called: run `describe` first (same acceptance rule as the tracker — exit 0, parses, contract 1; else one line and stop using it), announce the rung once, prefer `doc-search` then `doc-read --section`, check `truncated`; the repo stays the source — never copy page content into repo docs.
Keep the prompt free of shapes/caps/exit-code detail beyond naming `--section` and `truncated` (template prompts cannot link to `capability-adapters.md`, which is not shipped — the prose must stand alone). Check `prompt-seam-check.sh` still passes; if a seam check would benefit (e.g. pin that all five commands carry the `.cdd/docs` line), that is optional — don't add unless trivial.

## File map
- `doc/architecture/capability-adapters.md` — currently tracker-only (title `:1`, intro, `describe` table, tracker verbs, GitHub/Jira sections, conformance gate section). Add docs sections; generalize wording; conformance section lists per-capability probes and the `docs-adapter` gate; says ci.sh runs over `tools/adapters/*/*.sh`.
- `tools/adapters/docs/confluence.sh` — new. Template: `tools/adapters/tracker/jira.sh` (whole file; `JQ_LIB` `:181-226`, `jira_request` `:136-172`, describe `:233-248`, dispatch `:376-447`).
- `scripts/adapter-conformance-check.sh` — `:39` hardcoded tracker verbs; `:147-155` hardcoded `capability == "tracker"`; `:202-204` usage probe `issue-read`; `:209-211` missing-backend probe `issue-list`; `:216` scan of `.cdd/` stays.
- `scripts/adapter-conformance-assert.sh` — add Confluence block after `:224`; update header `:1-40` and count at `:247`.
- `scripts/docs-adapter-assert.sh` — new.
- `scripts/ci.sh` — registry `:65-87` (add `docs-adapter`; reword adapter-conformance description from "tracker adapters" to "capability adapters"); `gate_adapter_conformance` `:164-173` glob `tools/adapters/tracker/*.sh` → `tools/adapters/*/*.sh` (and its FAIL message); `:92` syntax/shellcheck glob already covers `tools/adapters/*/*.sh`.
- `scripts/prompt-seam-check.sh` — `check_gate_count` `:203-208` pins "N gates" in `CLAUDE.md` and `.claude/commands/cdd-pre-pr.md`; becomes 22.
- `.claude/commands/{cdd-next-step,cdd-plan,cdd-implement,cdd-pre-pr,cdd-process-pr}.md` and `template/.claude/commands/` same five — wiring. `cdd-pre-pr.md:46` (cdd-only block) "21 gates" → 22 and mention the docs adapter check.
- `CLAUDE.md` — `:50` gate list (21 → 22, add `docs-adapter`, "tracker adapters" → "capability adapters"); module layout table: add `tools/adapters/docs/confluence.sh` row; key references row for capability-adapters.md: "(tracker and docs verbs, shapes)"; `tools/` row mention is generic already.
- `doc/knowledge_base/claude-driven-development.md` §2.16 `:242-263` — last paragraph: docs capability live too (read-only, Confluence reference adapter); one or two sentences at workflow altitude: sessions consult it only on a trigger, it is read-only, context-capped, and the repo remains the source (replace-vs-mirror unchanged). Session wiring should be reflected briefly (e.g. a sentence that any session may read through it) — no shapes, no caps numbers (altitude rule).
- `doc/architecture/overview.md` — tree `:38-41` add `docs/confluence.sh`; `:60` guard paragraph: covers both capabilities, glob; add a sentence on the `docs-adapter` fixture gate (correctness offline for the docs adapter, unlike the verb-probe floor).
- `doc/architecture/index.md` `:11` — capability-adapters description: tracker and docs.
- `doc/knowledge_base/engineering-practices.md` `:23-24` — glob wording, mutation count; add a line for `./scripts/docs-adapter-assert.sh`.
- `doc/knowledge_base/roadmap.md` `:207-208` — merge + tick.
- `.github/workflows/template-smoke.yml` — no change (delegates to ci.sh).

## External findings
- **Test page content, fetched 2026-09-24 via the Atlassian MCP (`getConfluencePage`, cloudId `avy-wiki.atlassian.net`, pageId `2808119297`, format adf):** title "Avy GCS software setup (clients instructions)", space TT "Team Tech", webui `/spaces/TT/pages/2808119297/Avy+GCS+software+setup+clients+instructions`. ADF top-level nodes: paragraph; heading level 2 "System Minimum Requirements"; bulletList; h2 "Pre-requisites"; nested bulletLists with `code` marks and `strong`/`backgroundColor` marks; h2 "Installation procedure steps"; h3 "AvyBase" (orderedList with codeBlocks, hardBreaks, `annotation` marks); h3 "CCA3" (orderedList `attrs.order: 8`); h3 "Simulator" (codeBlocks with `attrs.language: "shell"`); h3 "Manuals" (link marks with `attrs.href`); h3 "Net Tools"; empty paragraphs (no `content`); `rule`; h3 "RustDesk" (an `inlineCard` with `attrs.url`, a listItem whose only child is a codeBlock). Headings are all top-level. Roughly 5–6 KB of text, so a whole-page read fits the default cap; `--section CCA3` should return the CCA3 h3 through its list, stopping at "Simulator"; `--section "Installation procedure steps"` (h2) runs to the page end (AvyBase through RustDesk, past the `rule`), because no heading of level ≤ 2 follows it. That is correct per the rule; use it as a live check of the rule.
- **Confluence v2 `GET /wiki/api/v2/pages/{id}`** — WebFetch of https://developer.atlassian.com/cloud/confluence/rest/v2/api-group-page/ (summarized, not verbatim): query params `body-format`, `include-version`, `version`; response has `id`, `title`, `spaceId`, `version` with `number` and `createdAt`, `body` with `storage` / `atlas_doc_format`, `_links` with `webui` and `base`. From prior knowledge, **not confirmed verbatim — verify in the live test**: `body-format` values include `storage`, `atlas_doc_format`, `view`; `body.atlas_doc_format` is `{"value":"<ADF as a JSON string>","representation":"atlas_doc_format"}` (hence `fromjson`, guarded by a type check); `version.createdAt` is ISO-8601 with milliseconds and `Z` (e.g. `2026-06-02T09:14:03.123Z`) — `iso_utc` from `jira.sh` expects a `±hh:mm` offset, so extend its regex to also accept `Z` (or it passes through unchanged, which is already ISO-UTC but with milliseconds; strip `.sss`).
- **Confluence v1 `GET /wiki/rest/api/search`** — WebFetch of https://developer.atlassian.com/cloud/confluence/rest/v1/api-group-search/ (summarized): params `cql` (required), `limit`, `excerpt`, `cursor`; results carry `content.id`, `title`, `excerpt`, `url`, `lastModified`, `resultGlobalContainer`; top-level `totalSize`, `_links`. Quoted deprecation: "CQL input queries submitted through the `/wiki/rest/api/search` endpoint no longer support user-specific fields like `user`, `user.fullname`, `user.accountid`, and `user.userkey`" (irrelevant — we don't use them). From prior knowledge, **verify live**: `excerpt` values `highlight`, `indexed`, `none`, `highlight_unescaped`, `indexed_unescaped`; `highlight` wraps matches in `@@@hl@@@`…`@@@endhl@@@` and HTML-escapes the text; `url` is site-relative (`/spaces/…/pages/…`), `_links.base` is `https://<site>.atlassian.net/wiki`. v2 has no CQL search endpoint, which is why search uses v1.
- **Auth:** Confluence Cloud REST accepts the same basic auth (email + API token) as Jira Cloud; API tokens are per Atlassian account, not per site (prior knowledge; consistent with the Jira adapter's live validation).
- **Credentials for the live test:** none are exported in this shell (`JIRA_*`, `CONFLUENCE_*` all unset on 2026-09-24). Ask the user to export them (or type `! export …`) at test time; never write them anywhere.

## Dead ends
- **Storage format (XHTML) + tag stripping in jq:** rejected — lossy regex HTML handling, no reliable heading structure for section cuts; ADF is JSON and the Jira adapter already has an ADF flattener.
- **`body-format=view` (rendered HTML):** same problem, worse (macro output, styling).
- **Using `ref_pattern` for free-text recognition:** a bare numeric page id collides with the built-in tracker shape `^#?[0-9]+$`; hence the separate optional `link_pattern` (URLs only).
- **MCP tools for the adapter:** ADR 0007 is CLI-first; the MCP was used only to inspect the test page's shape during planning.
- **Resolving tiny links (`/wiki/x/…`):** would need an extra redirect-following request; out of scope, documented as unsupported.
- **A shared jq library file between Jira and Confluence adapters:** adapters are single-file executables a project `exec`s; copying the ~40 lines is the accepted cost.
- **`doc-sync` / `doc-publish`:** out of scope and not added to the roadmap (handoff decision).
- WebFetch of the Atlassian REST reference returns summaries, not verbatim text — don't retry it for verbatim quotes; the live test is the verification.

## Open questions resolved
- **Content format of `doc-read`:** ADF fetched via v2 and flattened to a Markdown subset by jq; `format: "markdown"`.
- **How `describe` advertises the reference shape:** required anchored `ref_pattern` (id or page URL) for what verbs accept, plus optional unanchored `link_pattern` (page URLs on the site) for spotting references in prose.
- **Caps and truncation signal:** search default 10 / max 25 results, excerpt ≤300 chars; read default 24000 / max 100000 chars via `--max-chars`; `truncated` (always present), `content_chars`, `sections`, stderr hint.
- **Credential naming and fallback:** `CONFLUENCE_BASE_URL`, `CONFLUENCE_EMAIL`, `CONFLUENCE_API_TOKEN`, optional `CONFLUENCE_SPACE_KEYS`. Email+token fall back to the Jira pair only as a pair and only when both Confluence ones are unset; the site falls back to `JIRA_BASE_URL` independently.
- **Where the existence check piggybacks:** listed per command in Approach → Session wiring.
- **Conformance gate:** generalized by `describe.capability` with a per-capability probe table (no separate docs checker); plus a new offline fixture gate `docs-adapter` (user approved).
- **ADR:** none; ADR 0007 already names the docs capability and defers its mitigations to "when this capability is built". Specifics go in `capability-adapters.md`.
- **Requirement 5 amended (user agreed):** original — "The four session commands (`/cdd-next-step`, `/cdd-implement`, `/cdd-pre-pr`, `/cdd-process-pr`), repo and template copies, use the docs adapter only when one is installed and the task gives a reason; with none installed they make no extra call and print nothing." Replaced by — the same, for **five** commands: those four **plus `/cdd-plan`** (the exploration session).
- **Requirement 4 note:** "`./scripts/ci.sh` passes" now includes a 22nd gate, `docs-adapter` (user agreed).

## Doc and roadmap edits
- `doc/architecture/capability-adapters.md` — as in File map (the main contract edit).
- `doc/knowledge_base/claude-driven-development.md` §2.16 — docs capability live; read-only, trigger-gated, context-capped, repo stays the source. Workflow altitude only; one-line pointer to `capability-adapters.md`. If §3.x session descriptions enumerate what each session reads, add nothing unless one explicitly lists inputs exhaustively.
- Template: the five commands' template copies (above). No other template file needs a change (the template ships no contract doc). Check `template/CLAUDE.md` — if it has a place where a project records "what lives where", optionally add one fill-in line for trigger 2 (e.g. `<Where external docs live, if any: "integration specs live in Confluence space XYZ">`); keep it generic and optional. Judgement call; mention it in the summary either way.
- `CLAUDE.md`, `doc/architecture/overview.md`, `doc/architecture/index.md`, `doc/knowledge_base/engineering-practices.md` — as in File map.
- Roadmap `doc/knowledge_base/roadmap.md:207-208`: replace both lines with one ticked line ≤200 chars, e.g. `- [x] Docs capability (read-only verbs, JSON shapes, context-cost caps) + Confluence reference adapter, wired into every session and validated on a real page.` Check length with `./scripts/ci.sh roadmap-length`. Do **not** add a `doc-sync` item.

## Verification
- `./scripts/ci.sh` — all 22 gates green; iterate with `./scripts/ci.sh adapter-conformance adapter-conformance-contract docs-adapter seams drift shellcheck`.
- `./scripts/adapter-conformance-check.sh tools/adapters/docs/confluence.sh` standalone passes.
- New `scripts/docs-adapter-assert.sh` assertions (Fixture gate section) — including the token-never-in-argv assertion in the stub curl.
- Extended `scripts/adapter-conformance-assert.sh` mutations + controls (Mutation test section).
- **Live (requirement 3):** with user-exported credentials, run and show the user:
  - `tools/adapters/docs/confluence.sh doc-read 'https://avy-wiki.atlassian.net/wiki/spaces/TT/pages/2808119297/Avy+GCS+software+setup+clients+instructions' | jq '{title,version,updated_at,truncated,content_chars,sections}'`
  - `… doc-read 2808119297 --section CCA3 | jq -r .content`
  - `… doc-stat 2808119297`, `… doc-search "AvyBase" --limit 3`
  - once with only `JIRA_*` exported (fallback path), if that's how the user's credentials are set.
  Fix anything the live payload contradicts in External findings, and update the contract doc accordingly. Never echo the token.
- Manual check that with no `.cdd/docs` and no `~/.cdd/adapters/docs`, the added shell line prints nothing and exits 0 (`bash -c '<line>'; echo $?`).
