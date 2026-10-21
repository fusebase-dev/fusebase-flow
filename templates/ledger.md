status: state/status.line
committed: derived, never written: python hooks/local/done.py <slice> writes state/done/<slice>.json

## Next
-

## Handoff
-

## Records
<!--
One line each, in time order, never edited: <YYYY-MM-DDTHH:MMZ> <kind> <scope> <key>=<value> ... [-- one line]
alert   <slice|phase|->  id=<alert id> real=yes|no
deploy  <phase>          env=<env> hash=<deploy hash> approval=<file> rows=<ids> rollback=<class> -- <exact command>
review  <slice>          result=PASS|FAIL agent=<reader agent id> [-- the findings sent back]
verdict <slice|phase>    result=PASS|FAIL agent=<reader agent id> [carried=5.x: a 5.x verdict carried over, no round]
Next: exactly one line, replaced in place. Handoff: at most 10 lines for a successor, replaced in place.
-->
