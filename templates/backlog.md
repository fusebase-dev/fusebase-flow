# Backlog

<!--
One block per item; one field per line. Exactly one of criterion or test. Example:

## B1 Magic-link sign-in expires after 15 minutes
- source: owner:2026-10-16
- criterion: A magic link older than 15 minutes shows "link expired" and signs nobody in.
- risk: auth
- status: open
- inputs:
  - packages/core/src/auth/magic-link.ts
  - dep:jose
- answers: A1

source: <slice id> | <flag id> | owner:<YYYY-MM-DD>
test: <repo path>::<test name>   (instead of criterion)
risk: none | auth | data | prod
status: open | done | dropped
inputs: <repo path>, <repo path>#<anchor>, <url>, <kind>:<reference>, dep:<package>, env:<NAME>, cfg:<key>
-->

## Answers

<!--
The owner's answers, verbatim. Example:

### A1 How long is a magic link valid?
- answered: 2026-10-16
> 15 minutes.
-->
