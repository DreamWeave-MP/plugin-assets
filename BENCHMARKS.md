# plugin-assets benchmarks

`bench/bench.jsl` times the package through its public modules: `check` over a load order (the
references listed or only the findings, counted as a load order or as plugins on their own, cut
down to a severity), over a patch whose models go through the NIF check, over one kind of record
at a time, and over a script list; `commands.check` over plugins named by path; the argument list
read; and every document the command line prints, in each format. The plugins are built in the
bench with `@tes3`, in the mix a master has at about a tenth of Morrowind.esm's size: 4,905
records, three in five of them dialogue responses, a third of those with a result script; then
statics, NPCs that share a model per race and sex, body parts, containers, lights, books, items
that share models and icons, and scripts of some forty lines. The data folder in scratch holds
what most of the references lead to, 5,546 files: small models built with `@nif`, and empty files
for the rest, since a lookup never opens one. A warm workload is warmed up, sized to a batch of
about a tenth of a second, and reported as the median of seven batches with a full collection
between them. A `cold:` workload is the median of seven fresh processes running
`bench/cold.jsl`, which is the command line run once, timed inside the script from its first
`require`. Every workload's answer is weighed, the whole report spelled out and checksummed, and
compared with the one pinned in the file.

```sh
jess run --capability filesystem.read --capability filesystem.write --capability process.spawn \
  --package jpk/plugin-assets --package-path jpk jpk/plugin-assets/bench/bench.jsl \
  <scratch> [filter] [jess binary] [package path]
```

Without the binary (and `process.spawn`) the cold workloads are skipped. A filter is parts
separated by `|`, any of which picks a workload by its name.

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran
  (load average 1.3 to 1.7 over the runs).
- Date: 2026-10-12.
- Binary: the verified release build of Jess on l3i 2.0.2 (Luau 0.742), the same one for both
  sides.
- Base: `25360a9`, the package before the move, with this bench (the bench file as it is now,
  copied over the export: the one-kind workloads were given their files later, and run against
  the old code as they are). Head: `90b8096`.
- Protocol: the whole bench against an export of base and against head, back to back under one
  lock. The warm rows are the median of six runs a side: three rounds base first, then three
  rounds head first. The cold rows are the median of six runs a side of the cold workloads alone,
  the order swapped every round. A difference under 5 percent is called no change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| check a load order, lookups only | 88.48 ms | 48.43 ms | 1.83x |
| check a load order, findings only | 40.91 ms | 20.16 ms | 2.03x |
| check a load order as plugins on their own | 90.78 ms | 49.53 ms | 1.83x |
| check a load order, shown down to broken | 41.40 ms | 20.20 ms | 2.05x |
| check a patch and its 96 models | 12.62 ms | 11.37 ms | 1.11x |
| check a patch and its 96 models, shown down to broken | 12.57 ms | 10.84 ms | 1.16x |
| check 2,048 statics | 108.08 ms | 71.71 ms | 1.51x |
| check 2,048 NPCs of twenty models | 18.26 ms | 10.88 ms | 1.68x |
| check 1,024 items | 76.77 ms | 49.41 ms | 1.55x |
| check 256 scripts | 15.76 ms | 834.24 µs | 18.89x |
| check 256 books | 3.52 ms | 3.26 ms | 1.08x |
| check 4,096 responses | 16.83 ms | 4.05 ms | 4.16x |
| check a script list of 2,048 lines | 10.75 ms | 6.59 ms | 1.63x |
| the command over three plugins by path, as the command line asks | 62.69 ms | 39.27 ms | 1.60x |
| parse 8 argument lists | 10.03 µs | 10.05 µs | no change |
| render a report as yaml | 134.94 ms | 136.14 ms | no change |
| render a report as json | 16.94 ms | 15.65 ms | 1.08x |
| render a report as toml | 25.66 ms | 25.29 ms | no change |
| render a patch, its models, references, and files used as yaml | 49.42 ms | 50.43 ms | no change |
| render a patch, its models, references, and files used as json | 5.40 ms | 5.40 ms | no change |
| render a patch, its models, references, and files used as toml | 11.33 ms | 11.19 ms | no change |
| render the files a patch uses as yaml | 5.96 ms | 5.94 ms | no change |
| say what is missing beside the file list | 317.89 µs | 309.31 µs | no change |
| cold: help | 338.33 ms | 337.32 ms | no change |
| cold: check of a patch, lookups only | 357.78 ms | 358.15 ms | no change |
| cold: check of a patch and its models | 388.71 ms | 393.52 ms | no change |
| cold: check of three plugins, lookups only | 537.76 ms | 514.21 ms | no change |

The first three rounds alone, base always first, read the same on every row that moved, and read
three rows that didn't as slower: the argument lists 0.91x, a report as YAML 0.92x, a patch as
YAML 0.95x. Nothing on the way to any of them is slower code, and six order-swapped rounds of
those rows gave 0.97x, 0.98x, and no difference: they are the machine. The JSON row is on the
edge the other way: 1.00x in those first three rounds, 1.06x in six order-swapped ones, 1.08x in
the six of the table.

## Each commit's share

The `check` workloads against an export of each commit that was made for speed, three rounds,
each round under its own lock, in the order of the columns. A cell is base's median over that
commit's.

| Workload | `d69fa06` script lines | `68f6924` undecoded | `165f781` files used | `40f5b21` argsort | `ffe61cb` kept lookups | head |
|---|---:|---:|---:|---:|---:|---:|
| check a load order, lookups only | 1.12x | 1.17x | 1.53x | 1.61x | 1.81x | 1.81x |
| check a load order, findings only | 1.21x | 1.52x | 1.46x | 1.64x | 2.00x | 2.01x |
| check a load order as plugins on their own | 1.12x | 1.15x | 1.52x | 1.58x | 1.80x | 1.83x |
| check a load order, shown down to broken | 1.23x | 1.52x | 1.49x | 1.55x | 2.02x | 2.10x |
| check a patch and its 96 models | no change | no change | 1.11x | 1.14x | 1.17x | 1.19x |
| check 2,048 statics | no change | no change | 1.45x | 1.49x | 1.51x | 1.57x |
| check 2,048 NPCs of twenty models | no change | no change | no change | no change | 1.72x | 1.78x |
| check 1,024 items | 1.06x | no change | 1.63x | 1.67x | 1.63x | 1.60x |
| check 256 scripts | 11.36x | 16.98x | 16.66x | 16.89x | 19.63x | 19.51x |
| check 256 books | no change | no change | no change | no change | 1.12x | 1.11x |
| check 4,096 responses | 1.43x | 3.68x | 3.53x | 3.67x | 4.44x | 4.37x |
| check a script list of 2,048 lines | no change | 1.07x | 1.16x | 1.30x | 1.74x | 1.81x |

What moved, and why. Little of it is the dialect: a comprehension is the loop it replaces, and
the one buffer of numbers this package has to hand l3i's data plane is the one it now makes to
sort by. It is a search of bytes where every line was taken apart, records that are not decoded
to learn they say nothing, two sorts that asked a comparator, and lookups that were made again
for every record that names the same file.

- **A script's files, 11x on scripts.** Every line of every script was split into tokens to find
  the three functions that take a file: `Say`, `StreamMusic`, `PlayBink`. A byte at a time, with a
  two-byte string cut at each one to look for `->`. A `@dream/bytes` regex finds where one of the
  names is spelled, in either case, and only that line is split. Most scripts spell none.
- **Records left undecoded, 2.6x more on responses.** A response (INFO) names a file by its sound
  file or in its result script, and most have neither. One with no `SNAM`, and no `BNAM` or none
  of the three names anywhere in its bytes, is not decoded; nor is a script with none of them.
  Record text is in a code page that spells ASCII as ASCII, so the bytes say what the decoded text
  would. On a master this is most of the records.
- **The files used, 1.3x to 1.5x where they are listed.** They were sorted by where each is on
  disk through a comparator that split both paths at their separators, at every comparison. A
  place's key is its path with the separators made NUL, which sorts as bytes into the same order;
  the keys are sorted as strings, and the paths at each place likewise. No comparator is called.
- **The findings' order, 1.05x to 1.12x on a load order.** Severity first, then as found: a
  comparator that looked both findings' places up in a table keyed by the findings. It is
  `data.argsort`, which is stable, over a `u8` buffer of ranks filled by a sink, and a
  comprehension over the permutation: 27x on the sort itself for a list of 1,434 findings
  (1.47 ms to 55 µs, timed apart from the bench), which is what the rows above see of it.
- **Lookups kept, 1.7x where records share files.** Two thousand NPCs name twenty models; a
  load order names most of its files more than once. Where a reference led is kept by its kind
  and path, and by the three other things a lookup reads of it, for the next one that names the
  same file the same way; so is the source it comes from.
- **A report as JSON, 1.06x to 1.08x, on the edge.** `snake` respelled each severity, code, and
  kind for every row with a `gsub` and a callback; the spellings are kept. YAML and TOML spend
  their time in the encoder and don't show it.

Three commits made for speed are too small for these rows to resolve, and are not claimed from
them. Timed apart, the merge of what the inputs refer to went from 0.90 ms to 0.05 ms for plugins
that are no load order (`c0a3ba6`, which no longer finds winners nobody asks for) and from
1.55 ms to 0.97 ms for a load order (`90b8096`, a record's type and then its id as two keys
instead of one spelled from both), at 3,600 references; and a distant model's seventeen names
cost 4.5 µs instead of 5.5 µs to spell and look up (`1b6d958`). Tried and not kept: finding a
record's winner by an `@dream/intern` pool of ids measured no faster than the lowercase string,
because a pool made for one check meets every id for the first time.

What didn't move, and what is left. The command line run once is 340 ms before it does anything:
loading `@vfs` (about 145 ms), `@tes3` (115 ms), and `@nif-assets` with `@nif` (80 ms); this
package's own modules are 19 ms of it, 2 ms more than before. Every document is written by
`@jess/data/value`'s encoder. Of a check that lists the files used, half is now
`fs.canonicalize`, once a loose file at about 20 µs: 26 ms of the 48. A file's canonical path is
its folder's and its name only where the file is no link and the name is spelled as the disk
spells it, and what a canonical path is on Windows this package can't say from here, so it is
left as it was; `@vfs` knows its roots and could answer for a whole folder at once. The rest is
`@tes3` decoding the records that do name files, `@vfs` answering whether a path exists
(seventeen times for each distant model that might have levels of detail), and `@nif-assets`
searching for icons and textures. A model's NIF check is `@nif-assets`' time.

## Which modules are native, and why

Jess compiles to machine code only what is marked (`--!native` on a module, `@native` on one
function), and every load pays for what is marked. A module carries `--!native` when a row below
spends its time there and the module is small (12 KB or less); a larger module carries `@native`
on the functions the row spends its time in, and nothing else.

Measured 2026-10-15 with `jess 0.1.0`, the verified release build of jess `4ff67ea` on l3i
2.1.0, on the i7-10870H, the one-minute load 0.30 and 1.48 at the start of the two
sessions. In each session the bench ran alternately on this package and on a copy of it with
every module marked, three fresh runs of `bench/bench.jsl` each, every run's row the median of
its batches; a column is the median of the three, and a ratio is against the all-marked runs of
the same session. Which functions a row spends its time in comes from `jess run --profile` of
that row alone, unmarked. The load cost is a fresh `jess run --package <this package>
--package-path jpk` of a script that only requires `@plugin-assets`, the two sides alternating, the
median of five each after one warm-up.

| Requiring `@plugin-assets` | All marked | This state |
| --- | ---: | ---: |
| Unmarked | 0.208 s | 0.201 s |
| Final | 0.204 s | 0.202 s |

| Row | All marked (ms) | Unmarked / all marked | Final (ms) | Final / all marked |
| --- | ---: | ---: | ---: | ---: |
| check a load order, lookups only | 42.51 | **1.081×** | 42.24 | 0.994× |
| check a load order, findings only | 17.46 | **1.118×** | 17.49 | 1.001× |
| check a load order as plugins on their own | 43.88 | **1.053×** | 44.06 | 1.004× |
| check a load order, shown down to broken | 17.23 | **1.100×** | 16.99 | 0.986× |
| check a patch and its 96 models | 9.233 | 1.019× | 9.197 | 0.996× |
| check a patch and its 96 models, shown down to broken | 9.210 | 1.024× | 9.182 | 0.997× |
| check 2,048 statics | 63.19 | 1.034× | 62.28 | 0.986× |
| check 2,048 NPCs of twenty models | 8.907 | 1.044× | 8.787 | 0.986× |
| check 1,024 items | 46.08 | 1.021× | 45.38 | 0.985× |
| check 256 scripts | 0.7297 | **1.162×** | 0.7210 | 0.988× |
| check 256 books | 2.848 | **1.072×** | 2.878 | 1.010× |
| check 4,096 responses | 3.558 | **1.138×** | 3.536 | 0.994× |
| check a script list of 2,048 lines | 5.488 | **1.141×** | 5.421 | 0.988× |
| the command over three plugins by path, as the command line asks | 32.08 | **1.083×** | 31.99 | 0.997× |
| parse 8 argument lists | 0.00794 | **1.140×** | 0.00922 | **1.161×** |
| render a report as yaml | 124.7 | 1.028× | 117.9 | 0.946× |
| render a report as json | 13.08 | 0.999× | 13.19 | 1.008× |
| render a report as toml | 21.15 | 1.016× | 20.96 | 0.991× |
| render a patch, its models, references, and files used as yaml | 45.42 | 0.989× | 43.52 | 0.958× |
| render a patch, its models, references, and files used as json | 4.687 | 1.012× | 4.696 | 1.002× |
| render a patch, its models, references, and files used as toml | 9.375 | 1.002× | 9.351 | 0.997× |
| render the files a patch uses as yaml | 5.440 | 1.000× | 5.249 | 0.965× |
| say what is missing beside the file list | 0.2549 | **1.159×** | 0.2916 | **1.144×** |

What carries the directive (every module here is one a row spends its time in, unmarked):

- Whole: `init`, `internal/references`.
- Unmarked: `cli`, `commands`, `internal/paths`, `main`.

Marked by function first (`init`'s lookups and claims, `internal/references`' readers and
trimming), every check and render stayed 1.06x to 1.14x slower than all marked: the two modules
are 26 KB and 19 KB of record walking, and a check spends its time across all of it, not in a
few functions. So both are marked whole, and every check and render row came back within 5%.
The two rows still above it are once-a-run work in `cli`, which parses a command line and is
never marked: `parse 8 argument lists` (1.161x, of 8 µs) and `say what is missing beside the file
list` (1.144x, of 0.3 ms), `cli.diagnostics` formatting a report's summary.
