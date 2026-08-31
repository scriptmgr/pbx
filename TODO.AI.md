# TODO

- Pre-existing `grep -c ... || echo 0)` double-counting anti-pattern
  (AI.md lines 171-174 document this as WRONG — double-counts under
  `pipefail`) found in the 4 existing test suites, incidental to creating
  `tests/full-script-test.sh` (which had the same bug, now fixed):
  - `tests/functional-test.sh:58`
  - `tests/enduser-test.sh:218,298,494`
  - `tests/comprehensive-test.sh:135,212,224,373`
  - `tests/deep-test.sh:489,589,603,613,705,1350,861,872,1520`
  Not fixed here — out of scope for the `full-script-test.sh` change.
