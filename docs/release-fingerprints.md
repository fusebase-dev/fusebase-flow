# Release tree fingerprints

Identify a previously cataloged Fusebase Flow tree from a manifest already installed in your
repository. No upgrade is required.

**Self-reference limit:** a tagged tree cannot contain its own fingerprint row. Adding that row
changes the manifest digest being identified. A release's row therefore appears in the next
release and, when available, in an external index.

**Preferred — managed content:**

```bash
python3 -c "import json;print(json.load(open('audit/managed-content-manifest.json'))['manifest_self_sha256'])"
```

**Fallback — hook layer.** Use this if the command above raises `FileNotFoundError`:

```bash
python3 -c "import json;print(json.load(open('audit/hook-layer-manifest.json'))['manifest_self_sha256'])"
```

`audit/managed-content-manifest.json` can be **absent on exactly the installs this table is for**.
An upgrade performed by a pre-4.7.0 engine used a hardcoded top-level file list that omitted newly
added files, so a repository upgraded that way never received it. That was finding F1, fixed in
v4.8.0 by making the content list manifest-driven (`upgrade.sh` → `list-managed --files`) — but the
fix cannot retroactively deliver the file, and the next upgrade is what installs it.
`audit/hook-layer-manifest.json` has shipped far longer and carries the identical field, so it
resolves those installs. Reported by a consumer whose install had exactly this gap.

Match your output to either fingerprint column below; both identify the same tree.

| Release / tree | `VERSION` | managed-content `manifest_self_sha256` | assets | hook-layer `manifest_self_sha256` | assets |
|---|---:|---|---:|---|---:|
| `v4.7.0` earlier target `664503b` | 4.7.0 | `f73edc0f6aec96176274859a98c118c6d0daf16f1bf202c0fe6fd0c9018f8149` | 279 | `feb9d19ef2c890a2523ee32f08ec097d6ef8a03db6f74653f08e5712e54d16ae` | 134 |
| `v4.7.0` current target `bad4d92` | 4.7.0 | `d929ac3a5203199e5000260a1f7d7a828e7d6162a5e75063533f7c8ae04cd478` | 286 | `6595d0977ce9a983a4ce3fbc1441ae7e0f7bdbf6c22b9bd838786ea9c9cb0b91` | 140 |
| `v4.7.1` | 4.7.1 | `bd281972043d1eb9f9f42a65d2f7759e831ec0c06ec2e7d54d215c05dba7ce6d` | 287 | `5f77a4eefae40466ad02d904a0253c56b6c3a61f184376881da1e2c292447213` | 141 |
| `v4.8.0` target `20fd707` | 4.8.0 | `8d81303e329320ae8e9437394370cb9a4044f15392a3b2b96eae49cc2a0371c2` | 305 | `df4a04f7cc5b673725feed031870fa53dcc46e592f93a2abe6976a36f2a5e787` | 156 |
| `v4.9.0` | 4.9.0 | `d514dd1c1888c76ec15cd711826231a25bfdf4239bf6a87dbcbfe9733e55b348` | 313 | `3a4881fe01bec0ad4439e3c5a1c17097151ceb352001eb55f1eee9b232830e35` | 164 |
| `v4.9.1` | 4.9.1 | `ed4fc0cd755fa10707d5de8b6480dda2086840db5ecd3c30e4e56617ef644120` | 314 | `8e561250d35f3cb9a8aa8ab90f0cad454bfa60967a25a73e4c7ece5de1f27be7` | 165 |
| `v4.9.2` | 4.9.2 | `57cae17b7db4ed1cd7e3ac17b4120062abb85e5804f2a386f60c2ba0791c6513` | 315 | `a38e92abaccdeade5ad25a8f3ce16c697f98152654a12c4eccd62c916e4966c2` | 166 |
| `v4.10.0` | 4.10.0 | `fa7bb5cf4a4fefd8e86f35e24555f0dc82daf47e498f24c8b888e5b3fff10f65` | 323 | `faf2199c81ca9c816cb203a4f71892fd8c5353cb931a45d16f33032d70cafbe5` | 174 |
| `v4.10.1` | 4.10.1 | `1e0b4fbab00a6c8578d2773c91c2f370eb2eebc8e57c416237283d9b61b6b2dd` | 323 | `665de96876ad5137f467e8ce247728726e8568a76864708e22b2a4933f55db01` | 174 |
| `v4.11.0` | 4.11.0 | `c0bd8faad60785a62cadce5626e92baa606fbb09547e4352b5fa0ae67a667a82` | 326 | `343031372b215473a388c87c544e308b84e63103ee3e7af6b8c20fde66ca9aca` | 177 |
| `v4.12.0` | 4.12.0 | `cdf2f1470a1f911b6beda7d4a2cdc42f79de947a97d8e1fc4607a70491fef272` | 330 | `e3e1de0bceb53da3eaf6d64e0389e307ff589c026b25652f12d65a9698b199bf` | 181 |
| `v4.13.0` | 4.13.0 | `1ba7eca049ecdc83563312fd46bf27a9d1c56143d6b9989c6fafbad7d3f01d12` | 338 | `4533bf38fbc26a1ac464fd0ab3741fd61b0eed63c85fb2d34b3f9de8d167a1ec` | 189 |
| `v4.13.1` | 4.13.1 | `a58970e42a5decae4c35581de69a9c0111d9ec37b5d7b21a8eacc4ae11e5f36a` | 338 | `bda07f44f2378e75ba55fca1f7cc6484e440c3cb760c284324cee09c836bc066` | 189 |
| `v4.14.0` | 4.14.0 | `8e2148042e2cd3e470f3b91af52c3ee4c5e64863fbd2e9e22f9ac110b67bc7f8` | 341 | `e44537591a44bdb6a67209b70dc6e8b0b9242287dd29bb92047ec17e4a8803ad` | 192 |
| `v4.14.1` | 4.14.1 | `70adc826c268d11db863f3fbdeb878b0423fad70ae1132549dbf7c28d15c209c` | 342 | `e48b7a040b206765ec47466b0f6ec56f0aa059c9c8cdb71a8c74e69862ab01d8` | 193 |
| `v4.15.0` | 4.15.0 | `b058dab0b326c7fb2f736f82bdbb63c0be1c4f30d9f0d8162a15a1981f330573` | 375 | `4abf3f57df693542d4f97cb2410c48d79e9dccd2066f88501ae811a8c9f7a60c` | 212 |
| `v4.15.1` | 4.15.1 | `ec0681229de3bfed1d920d08abc8386bc73d19875bf5de34b224b24b71fadc19` | 376 | `f8e06cea670965c6bac6bc679638bf7f7ae77f74a06e8c368495ed8c0f591469` | 212 |
| `v4.15.2` | 4.15.2 | `5a70a1b662edd6ae193550fba91ba173b80aa7b92a28b06c35c0ce0cbcb4eea0` | 376 | `bd11c9d889aca539a900d89efbe4f52f2fa1a9aef577972f682146f4da2f62d8` | 212 |
| `v4.15.3` | 4.15.3 | `e779a351266ba742a52ff9806cc3eb76514146957b62b4184e5a2d83817b8a2a` | 376 | `a2f38290444ff4c818b0655b83263fdd0088dd0c1bc1724ab414b2b73fe55e6d` | 212 |
| `v4.16.0` | 4.16.0 | `e6867bd7363b6bbcfd6e73ce0b32259c6c675cad9ed536eacbf5d261f1f5f8a7` | 378 | `1d8964b0650200634f494868c2ca0bcec1b33f80aa23aa942d97fec95b92a77c` | 214 |
| `v4.16.1` | 4.16.1 | `05566f4efd0be7d3ed36a07174b02bc103cbc11bb5476219b57abef74fb1f5eb` | 378 | `beb6fd95255bbb1db7684f38628a0286489885e2df3ccd4c497a70d56d2a3a99` | 214 |
| `v4.16.2` | 4.16.2 | `dc6ae918cafb804d98b8851a36936d54e9522c5344ae24c5b4b2a07ec5412169` | 378 | `d35fa70d4a3387bedeb69acc93ea517cacb4506f931bb9627fd07c0d0ae9a18e` | 214 |
| `v4.16.3` | 4.16.3 | `68386664bece97d4b9ff78e45daaf8c176a039e8a29faf7a342f4716d1a1e296` | 378 | `9c5f714140af702bd31c6e9376c96b90e5f8c3ad03e01f5990d03482faea9c7a` | 214 |
| `v4.16.4` | 4.16.4 | `7de8ce5e911c3a1aa689e78b33f7a1bad21a5d33f3a23d2dae18043c1256a0b5` | 381 | `0cfad8ef6c769cc7050149ecc91076f25e41f3360cfb0039b9d5e95bfe41db86` | 217 |
| `v4.16.5` | 4.16.5 | `3d31f318011ad89b0529c34c549850c6672d02052107d15ecfdd2889f37abcd7` | 383 | `ef7250453fe54d4bf0c406097898f845f5701151b45408a9761e183f2b5cb8f0` | 218 |
| `v4.16.6` | 4.16.6 | `d1bae643315a9342e5d6a8999121c2f954a1fc05545e9cffd68cee6511d8e33a` | 386 | `5b634bb9a0f3f89548758666702f948fcac4c6e466c16234941ee7437424d839` | 220 |

`v4.9.0`, `v4.9.1`, `v4.10.0`, `v4.15.0`, `v4.15.1`, `v4.15.2`, `v4.16.0` and `v4.16.3` are unpublished tagged
trees: their release workflows failed (2026-08-12, 2026-08-13, 2026-08-15, 2026-09-07 and 2026-09-10)
and published nothing. Each row identifies an immutable tag target; none is evidence of publication.
No tag was moved — `v4.9.2` superseded the first two, `v4.10.1` superseded `v4.10.0`, and published
`v4.15.3` superseded the v4.15.x trees, and published `v4.16.1` superseded `v4.16.0`. The
`v4.16.0` [run `34438811255`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34438811255)
passed `verify-windows-msys` at 682/682, failed `verify-linux` at 681/682 on one test-fixture
portability row, and `publish` never dispatched; `v4.16.1`
[run `34441536913`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34441536913) passed
both legs at 682/682 and published. Adopters holding a 4.16.0 tree should move to 4.16.1: the two
trees differ only in test fixtures and documentation, but only 4.16.1 is verified on both platforms. A tree cloned from `main` during any of those windows is
identifiable here rather than absent from the table.

`v4.16.3` (`022b011`, 2026-09-10) is the newest unpublished tagged tree. Its [run `34506385370`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34506385370) passed `verify-linux` in 3.2 min and failed `verify-windows-msys` after 49.8 min: the `secret-scan-staged` phase hit its 1800 s bound (rc 124) after 17 of its 39 rows, hanging in the T31 trusted-HEAD dispatch that runs the real `hooks/git/pre-commit` inside a throwaway repo. `verify-gate` went red and `publish` never dispatched, so no Release exists for this tag. The tag is immutable and was not moved. The phase is a pre-existing profile member that took 98 s on the green `v4.16.2` run of the same code: `git diff 46d1125 022b011` touches no file under `hooks/git/`, `hooks/shared/`, `policies/` or `test-secret-scan-staged.sh`, and every other phase on this leg matched v4.16.2 within seconds — including all four newly promoted phases (4 s, 5 s, 1 s, 32 s). The cause was diagnosed and closed in `v4.16.4` (`c1706aa`): a command substitution capturing a git/hook process tree, which under MSYS a Windows-native descendant can hold open past exit. 27 such sites existed on that surface and 0 remain; `git-capture-guard` now rejects the class by shell syntax in the essential profile. On the `v4.16.4` gate the same phase ran in 78 s ([run `34523554892`](https://github.com/fusebase-dev/fusebase-flow/actions/runs/34523554892), `verify-windows-msys` 21.5 min, 763/763 PASS across 37 phases). `v4.16.3` stays unpublished and its tag was never moved; this row identifies that tree.

`v4.10.0` failed for a reason worth recording, because it was self-inflicted: the fingerprint-row
check added in `v4.9.2` read a tag's target with
`--format='%(*objectname)%(objectname)'`, which CONCATENATES the commit and the tag object for an
**annotated** tag. Its self-reference exemption compared that 80-character field against a
40-character `HEAD` and never matched, so the tag being cut always looked like a missing row and no
release could pass its own gate. Its test passed because the fixture built a lightweight tag — a
shape this project never ships. Fixed in `v4.10.1` (prefix comparison, annotated + lightweight rows).

Every value above is read from the tagged tree, never transcribed by hand. Regenerate them with
`hooks/local/print-release-fingerprints.sh <ref>…`; a hand-typed hook-layer count in the first
revision of this table was wrong (203 instead of 156) and a consumer propagated it.

The two 4.7.0 rows share a `VERSION` because the `v4.7.0` tag was moved from `664503b` to
`bad4d92`. Their fingerprints distinguish the trees; the lookup does not itself detect a moved tag.

This is a lookup table, not a guarantee that tags will remain immutable. The immutability policy
and its not-yet-complete enforcement are documented in
[`PUBLISHING.md`](../PUBLISHING.md#published-tag-immutability-policy).
