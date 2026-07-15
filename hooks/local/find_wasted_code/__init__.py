"""find-wasted-code — static friction-footgun audit for Fusebase Flow.

Load-bearing package behind hooks/local/find-wasted-code.py and the
flow-skills/find-wasted-code/ skill. Split along the per-rule seam to stay
single-pass readable under the FR-25 800-line module ceiling.

Conservative-by-construction: a finding is `confirmed`/`broken` ONLY when it is
provable from repository state (a root-explicit path that is absent, a Markdown
anchor that no heading yields, a settings hook wired to a missing handler).
Everything ambiguous (cwd-relative paths, placeholders, unsupported constructs)
is reported as `unresolved`/`inconclusive` coverage, never as a confirmed defect
— so the audit never blocks or annoys the operator with a false positive.
"""
