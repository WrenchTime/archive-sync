# archive-sync

Keeps the [WrenchTime](https://github.com/WrenchTime) archive in step with the open vehicle data the WrenchTime app reads, so that data survives if an upstream repository is deleted or made private.

| Upstream | Kept as | Licence |
|---|---|---|
| every repository of [OBDb](https://github.com/OBDb), the community signalset database, including `obdb.community`, which carries the generated index `public/data/matrix_data.json` | fork | CC BY-SA 4.0 (data) |
| [meatpiHQ/wican-fw](https://github.com/meatpiHQ/wican-fw), WiCAN vehicle profiles | fork | GPL-3.0 |
| [foerbsnavi/OBDex](https://github.com/foerbsnavi/OBDex), generic trouble-code catalog | fork | CC0-1.0 data, MIT code |
| [mcgyver78/WiCAN_W906](https://github.com/mcgyver78/WiCAN_W906), Sprinter W906 profile | mirror (it is itself a fork of `wican-fw`, and GitHub allows one fork per network) | GPL-3.0 |

An upstream repository named like one of the archive's own (`.github`, `archive-sync`) is forked as `<owner>-<name>`.

## How it runs

`.github/workflows/sync.yml` runs `sync.sh` every day and on demand (with an optional dry run). Each run:

1. forks any upstream repository not yet in the archive;
2. fast-forwards every fork to its upstream;
3. pushes the mirrors' branches and tags.

Then `dtc-catalog.sh` reads the YAML of the `OBDex` fork with Bun (`dtc-catalog.ts`; nothing of OBDex is executed) and publishes the short title of every generic trouble code, one JSON per language, to [dtc-catalog](https://github.com/WrenchTime/dtc-catalog), which the app downloads. It commits only when a code or a title changed.

When an upstream disappears its fork stops syncing and keeps the last state it had, and the run lists it under sync failures without failing.

To run it from a Mac instead, with your own `gh` login: `./run-local.sh` (Docker required; `--dry-run` works here too).

## Setup

- Organization secret or repository secret `ARCHIVE_TOKEN`: a fine-grained personal access token whose resource owner is `WrenchTime`, on all repositories, with **Administration**, **Contents** and **Workflows** read and write. It expires after a year at most; renew it before then.
- Organization Actions policy limited to this repository, so the workflows that forks inherit from their upstreams never run here.

## Contributing

Nothing here is the place to contribute. Send changes to the upstream repositories.
