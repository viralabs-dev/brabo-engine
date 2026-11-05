# prompts/

Agent prompt templates, versioned as `.md` files, outside the Elixir code that loads them today. This is the FIRST batch of extracted content — four templates, today heredoc/inline strings in `lib/engine/**`.

Reading by agent started in this same wave, with THREE templates:

- **Psychologist** (`lib/engine/workers/psychologist_worker.ex`, `render_kickoff/4`) and **Anamnese** (`lib/engine/workers/anamnese_worker.ex`, `initial_message/1`) resolve `psychologist-kickoff`/`anamnese-kickoff` via `EngineApiClient.get_prompt_template/2` when the `graph_templates_enabled?` flag is on (`GRAPH_TEMPLATES_ENABLED` at runtime, **default OFF**, `false` — a new capability is born disabled until proven, the same criterion as `psychologist_enabled?`/`anamnese_enabled?`), with a MANDATORY FALLBACK to the inline text on any failure (api down, template not yet seeded, flag off). The `.ex` files keep carrying the original text as plan B, never removed.
- **ux-designer** (`lib/engine/harness/agents.ex`, `identity/1`) resolves `ux-designer-identity` via `Engine.Harness.InstructionFiles.graph_template/2`, behind its OWN flag, `graph_instruction_templates_enabled?` (`GRAPH_INSTRUCTION_TEMPLATES_ENABLED`, also default `false`) — a separate name on purpose: the two flags would collide with OPPOSITE defaults if they shared the same key (see the comment in `config/runtime.exs`). Same fallback discipline: failure or flag off falls back to the inline string.

- **`ContextManager`** (`lib/engine/harness/context_manager.ex`, `prompt/1`, called by `summarize/2`) resolves `context-manager-summarize` behind the SAME `graph_templates_enabled?` as Psychologist/Anamnese, replacing `{{turnos}}` with the same `<role>: <content>` body that the inline path already built. It closes the last of the four templates in the batch — none is left without a consumer.

The four templates in this batch have a consumer. Each `.ex` keeps carrying the inline text as plan B, never removed: with the flag off (the default) the graph api is not even called.

## Why separate prompt from code

The pattern in this folder — and the trigger for proposing it here — came from studying the repository [`ErickWendel/neo4j-ai-experiments`](https://github.com/ErickWendel/neo4j-ai-experiments), by Erick Wendel. That project keeps its NL→Cypher translation prompts, context-assembly prompts and answer-formatting prompts as files of their own, deliberately outside the application logic that calls them, and that is not just folder organization: it is what makes each prompt reviewable in an isolated diff, versionable without recompiling anything, and readable by someone who never opened the surrounding Elixir/TypeScript code. It is the same separation this directory pursues for Brabo, and it is worth recording the credit: the concrete inspiration — simple front-matter, one file per responsibility, a hash as the idempotency key when indexing — came from reading Erick Wendel's material on how he organizes prompts for Neo4j/GraphRAG agents. Thank you for the open knowledge base; it saved a whole round of trial and error on "where does the prompt live when it no longer lives in the code".

## Format

Each file `prompts/<name>.md` has YAML front-matter at the top:

```yaml
---
name: nome-do-arquivo
version: "1"
---
```

- `name` — the template identifier. By convention, the same name as the file (without `.md`).
- `version` — a string, not a number (avoids ambiguity between `1` and `1.0`). It goes up when the CONTENT of the template changes in a way the consumer needs to know about — the body hash (see below) already detects any byte change, so `version` is for human reading, not for deduplication.
- Extra fields are allowed and document properties of the original `.ex` that are not prompt text — today only `pinned: true`, in the two kickoffs (Psychologist, Anamnese) whose original message is born pinned and therefore is never compacted by `Engine.Harness.ContextManager`.

The body (everything after the second `---`) is the prompt text. Where the original `.ex` interpolates dynamic data (`#{...}` — something that changes per session, project or turn, not fixed text), the Markdown uses a `{{variavel}}` placeholder instead of trying to reproduce the interpolation. Each file documents its placeholders in a final section "## Variáveis", explaining what each one represented in the original code. **This section is NOT seeded**: the template body ends at the `## Variáveis` line, and the seeder discards everything from there on (AT-244). It cites the same `{{placeholders}}` as the body, and each consumer replaces ALL occurrences — seeded, the model would receive the documentation and the data twice. Prompt text never goes after it, and the body does not use that heading for anything else. **This work only documents the placeholders — the real substitution (a template engine reading `{{variavel}}` and resolving it against the turn's context) is the job of the wave that will consume this, and is not implemented yet.**

## Templates extracted in this batch

| File | Origin in the `.ex` |
| --- | --- |
| `ux-designer-identity.md` | `lib/engine/harness/agents.ex`, the `"ux-designer"` entry of `@identities` |
| `psychologist-kickoff.md` | `lib/engine/workers/psychologist_worker.ex`, `initial_message/4` |
| `anamnese-kickoff.md` | `lib/engine/workers/anamnese_worker.ex`, `initial_message/1` |
| `context-manager-summarize.md` | `lib/engine/harness/context_manager.ex`, `summarize/2` |

## How to run the seeder

```bash
node scripts/dev/seed-prompts.ts
```

The script (`scripts/dev/seed-prompts.ts`):

1. Reads every `prompts/*.md` (except this README), parses the front-matter and separates `name`/`version`/`body` — the `body` runs from the front-matter up to the `## Variáveis` section, exclusive.
2. Computes the `sha256` of the `body` (`crypto.createHash('sha256')` from Node — no new lib).
3. Calls `POST /internal/graph/prompt-templates` (`{ name, version, body, hash }`), authenticated with the internal service token (`x-brabo-service-token`, value of `BRABO_SERVICE_TOKEN`) against `API_PUBLIC_URL` (default `http://localhost:3000`).
4. It is idempotent by hash: running it twice with the same content does not create a new version — the endpoint's response decides this (`active` stays the same version when the hash already exists).

**Status of this delivery**: the route `POST /internal/graph/prompt-templates` is a contract agreed with the workstream that builds the read infrastructure (api/engine, in parallel) — it may not exist yet when you run the seeder. If the call fails with 404/connection refused, the script reports clearly that the local read/parse/hash steps ran OK and that the round trip against the api depends on that workstream being up; it does not pretend success.

## What this directory does NOT do, today

- The placeholder substitution of each consumed template lives in the agent itself (`Engine.Workers.PsychologistWorker`, `Engine.Workers.AnamneseWorker`, `Engine.Harness.ContextManager.Default`), reusing the SAME formatting functions as the inline path — so the text does not diverge between the two paths. There is no shared template engine, and that is deliberate: the set of placeholders belongs to the template, not to the mechanism.
- There are no templates beyond the four listed above; the rest of the inline prompts stay in the code until the wave that migrates them.
- Real consumption still requires TWO things outside this directory: the corresponding flag turned on (default off for both) and the seeder having run against a running api — without that, every path falls back to the inline text, silently.
