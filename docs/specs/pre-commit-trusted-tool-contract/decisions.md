# Trusted-tool contract decisions

**Status:** `LOCKED — A2 + B1`. Operator locked both recommendations in chat on 2026-08-11; implementation of S2b (A2, Git fail-closed) and S2c (B1, per-control positive verdict) is authorized. The residual limits recorded below are locked WITH the decisions: neither A2 nor B1 authenticates git or the interpreter, and no implementation may claim that it does.

North-star: On-vision — the safety kernel retains fail-closed secret scanning and protected paths (`docs/north-star.md:31-34`).  
Dimension: constraint — mechanism must carry the guarantee; prose alone is not a control (`docs/north-star.md:18`).  
Recommendation: proceed with explicit residual-threat labels and no unsupported authenticity claim (`docs/north-star.md:18`; `docs/backlog/index.md:9`).

## D-A — Git resolution versus genuine non-repository execution

### Statement

**D-A:** `hooks/git/pre-commit:20-24` maps both an empty result from bare `git rev-parse` and genuine non-repository execution to `exit 0`, so unavailable, broken, or shadowed Git can skip the hook's security controls (`hooks/git/pre-commit:20-24`).

### Threat model

| Dimension | Decision input |
|---|---|
| Adversary | Same-principal caller who can shape `PATH` for the bare `git` invocation and, under the locked model, can also modify workspace-controlled inputs (`hooks/git/pre-commit:20`; `docs/backlog/index.md:9`). |
| Existing control boundary | Repository discovery occurs before Python environment sanitization; a blank `ROOT` exits successfully and therefore prevents later controls from running (`hooks/git/pre-commit:20-28`). |
| Locked model | This is the existing M17 same-principal model, not a hostile-co-tenant model; hostile-co-tenant resistance needs a trust root Flow does not have, such as remote fetch or signature verification, and K3 records no signing seam (`docs/backlog/index.md:9`). |
| Fixability | **Inference:** local classification can close ordinary missing/broken-Git fail-open behavior, but no workspace-local check can authenticate Git against the same principal that controls `PATH` and workspace state (`hooks/git/pre-commit:20-24`; `docs/backlog/index.md:9`). |

### Options

| Option | What changes | Cost | What it breaks | Failure mode not closed |
|---|---|---|---|---|
| A1 — Fail closed on every root-query failure | Any nonzero/empty `git rev-parse` result blocks instead of skipping (`hooks/git/pre-commit:20-24`). | One branch plus diagnostics around the existing query (`hooks/git/pre-commit:20-24`). | Legitimate direct execution outside a repository no longer exits successfully (`hooks/git/pre-commit:21-24`). | A same-principal PATH shim can return a plausible nonempty root or proxy selectively (`hooks/git/pre-commit:20`; `docs/backlog/index.md:9`). |
| **A2 — Independent repo-context evidence** | Before permitting the skip, classify repository context without trusting the queried Git: upward `.git` file/directory evidence plus explicit hook/Git context; repository evidence + missing/unusable Git blocks, while no evidence preserves the outside-repo skip (`hooks/git/pre-commit:20-24`). | A bounded shell classifier, diagnostics, and coverage for normal repos and linked worktrees (`hooks/git/pre-commit:20-26`). | Nonstandard external `GIT_DIR`/bare layouts need explicit evidence handling or can be misclassified (`hooks/git/pre-commit:20-26`). | The same principal can forge/remove local evidence or supply a Git shim that returns a plausible root; A2 is context/fault detection, not tool authentication (`docs/backlog/index.md:9`). |
| A3 — Explicit outside-repo mode | Default every root-query failure to block; permit `exit 0` only through a documented direct-run opt-out (`hooks/git/pre-commit:20-24`). | A new caller contract and propagation at every legitimate direct-run site (`hooks/git/pre-commit:21-24`). | Existing outside-repo probes block until they opt out (`hooks/git/pre-commit:21-24`). | A same-principal PATH/process attacker can set the opt-out unless it is authenticated by a trust root that is absent (`docs/backlog/index.md:9`). |
| A4 — Accept and document | Keep the current empty-root skip and record Git availability as an environmental assumption (`hooks/git/pre-commit:20-24`). | Documentation only; no runtime cost (`hooks/git/pre-commit:20-24`). | No current invocation behavior changes (`hooks/git/pre-commit:20-24`). | Missing, broken, or zero-behavior Git continues to skip every later control with status 0 (`hooks/git/pre-commit:20-24`). |

### Recommendation — awaiting operator lock

**Recommend A2.** It preserves the required genuine outside-repository `exit 0` while making conventional in-repository Git loss/failure a blocking condition; unlike A1 it retains the current legitimate skip, and unlike A3 it does not turn an unauthenticated opt-out into the classifier (`hooks/git/pre-commit:20-24`; `docs/backlog/index.md:9`). Label A2 as repository-context/fault detection only: same-principal Git authenticity remains unfixable without the absent trust root (`docs/backlog/index.md:9`).

### Discriminating evidence

| Probe | Distinguishes / proves |
|---|---|
| Invoke the hook from a normal worktree with a `PATH` that leaves required shell tools reachable but makes `git` unresolvable; current behavior exits 0 at root discovery, A1/A2/A3 block, and A4 still skips (`hooks/git/pre-commit:20-24`). |
| Invoke the same artifact from a directory with no repository evidence and the same unresolvable Git; A1 blocks, A2/A4 preserve the required skip, and A3 skips only with its opt-out (`hooks/git/pre-commit:20-24`). |
| Put a selective `git` shim first on `PATH` that reports a plausible root; success against A2 proves the residual same-principal limit rather than Git authenticity (`hooks/git/pre-commit:20`; `docs/backlog/index.md:9`). |

## D-B — Python control completion without interpreter authenticity

### Statement

**D-B:** §1b accepts any resolved `python3` without applying even its fallback version probe, and the four Python control invocations treat status 0 as success without requiring a positive verdict artifact (`hooks/git/pre-commit:85-87,213-217,316-320,503-507,678-682`).

### Threat model

| Dimension | Decision input |
|---|---|
| Adversary | Same-principal caller who can place a stub or selective executable named `python3` first on `PATH`; `command -v python3` is the primary acceptance branch (`hooks/git/pre-commit:85-90`; `docs/backlog/index.md:9`). |
| Existing mitigations | The hook scrubs Python-influencing environment variables, sets `PYTHONSAFEPATH=1`, uses `-S`, controlled `PYTHONPATH`, file-script wrappers, shell-side `git ls-tree` sentinels, and trusted-HEAD extraction; these constrain Python startup/import inputs but do not authenticate the executable selected from `PATH` (`hooks/git/pre-commit:28-45,137-157,189-230,405-436,475-503,678`). |
| Locked model | This is the same M17 same-principal boundary; Flow has no external trust root and no signing seam for authenticating the interpreter (`docs/backlog/index.md:9`). |
| Fixability | **Inference:** a positive artifact can prove that a non-cooperating zero-exit stub did not run the control, but an unsigned artifact cannot prove interpreter authenticity against a same-principal executable that can inspect the invocation and fabricate the expected output (`hooks/git/pre-commit:213-217,316-320,503-507,678-682`; `docs/backlog/index.md:9`). |

### Options

| Option | What changes | Cost | What it breaks | Failure mode not closed |
|---|---|---|---|---|
| **B1 — Per-control positive verdict** | Each of the four wrappers writes an exact control ID plus fresh shell-issued nonce only after successful completion; shell code requires and removes that artifact in addition to status 0 (`hooks/git/pre-commit:213-217,316-320,503-507,678-682`). | Four producer/consumer seams and fail-closed cleanup paths across §2 and §3 (`hooks/git/pre-commit:213-230,316-320,503-507,678-682`). | A real control that returns 0 without materializing its verdict now blocks, intentionally converting silent incomplete execution into failure (`hooks/git/pre-commit:213-217,316-320,503-507,678-682`). | A same-principal smart stub can read the script/environment/temp state and fabricate the unsigned verdict; B1 proves completion protocol only, not interpreter trust (`docs/backlog/index.md:9`). |
| B2 — One interpreter challenge | Require structured output from a startup self-test before the four existing calls (`hooks/git/pre-commit:85-105`). | One probe and parser, with less control churn than B1 (`hooks/git/pre-commit:85-105`). | Interpreters/wrappers incompatible with the challenge format block before controls (`hooks/git/pre-commit:85-105`). | Passing one challenge does not prove any later control ran, and a PATH stub can emulate the challenge (`hooks/git/pre-commit:213,316,503,678`; `docs/backlog/index.md:9`). |
| B3 — Pin/hash/sign the interpreter | Resolve an absolute interpreter and verify it against an external identity before use (`hooks/git/pre-commit:85-105`). | Cross-platform distribution, rotation, and trust-root lifecycle not present in Flow (`docs/backlog/index.md:9`). | Portable user-managed Python discovery and legitimate upgrades fail until re-authorized (`hooks/git/pre-commit:87-105`). | A workspace-local hash/path manifest is still replaceable by the same principal; a real fix requires the absent remote/signature seam (`docs/backlog/index.md:9`). |
| B4 — Accept and document | Keep status 0 as the complete success contract and state that interpreter integrity is outside the model (`hooks/git/pre-commit:213-217,316-320,503-507,678-682`). | Documentation only; no runtime cost (`hooks/git/pre-commit:213,316,503,678`). | No current invocation behavior changes (`hooks/git/pre-commit:213,316,503,678`). | A zero-exit `python3` stub continues to disable all four Python controls silently (`hooks/git/pre-commit:87,213,316,503,678`). |

### Recommendation — awaiting operator lock

**Recommend B1, explicitly as fault/completion detection rather than a trusted-interpreter defence.** It closes the verified zero-exit-only stub path at every control boundary and complements the existing startup/import mitigations without claiming the trust root B3 would require (`hooks/git/pre-commit:28-45,213-230,316-320,503-507,678-682`; `docs/backlog/index.md:9`). The same-principal authenticity defect is unfixable under the locked model; operator lock of B1 accepts that residual limit (`docs/backlog/index.md:9`).

### Discriminating evidence

| Probe | Distinguishes / proves |
|---|---|
| Put a `python3` stub that exits 0 for every argument first on `PATH`, then exercise each of the four control paths; current/B4 behavior reports success, B2 blocks at its challenge, and B1 blocks once per missing verdict (`hooks/git/pre-commit:87,213-217,316-320,503-507,678-682`). |
| Replace it with a smart stub that emits B2's response or writes B1's visible nonce/verdict; success demonstrates that neither local protocol authenticates a same-principal interpreter (`docs/backlog/index.md:9`). |
| Run the real interpreter through the current sanitized `-S` file-script paths; B1 must distinguish genuine end-of-control completion from mere process status without relaxing the existing mitigations (`hooks/git/pre-commit:28-45,213-230,316-320,503-507,678-682`). |

## What must NOT be done

- Do not call a version-string or `sys.version_info` response a stub-interpreter defence: the existing fallback probe already asks only for version semantics, primary `python3` bypasses that probe, and a PATH-controlled executable can return the expected result (`hooks/git/pre-commit:85-90`; `docs/backlog/index.md:9`).
- Do not describe A2, B1, a nonce, a verdict file, an absolute path, or a workspace-local hash as a trust root; a same-principal attacker who controls `PATH` can still proxy selectively, inspect arguments/scripts/environment, fabricate unsigned outputs, and alter workspace-local evidence (`hooks/git/pre-commit:20,85-90,213,316,503,678`; `docs/backlog/index.md:9`).
- Do not require remote fetch or signature verification without explicitly creating and operating the trust root/signing seam that the framework currently lacks (`docs/backlog/index.md:9`).
- Do not weaken the existing environment sanitization, `-S`, controlled `PYTHONPATH`, file-script wrappers, or trusted-HEAD extraction while addressing executable selection or verdict completion (`hooks/git/pre-commit:28-45,204-230,316,503,678`).

No implementation may begin until the operator locks these decisions (`docs/specs/msys-hardening-roadmap/roadmap.md:73-74`).
