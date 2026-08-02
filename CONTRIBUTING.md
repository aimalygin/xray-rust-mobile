# Contributing

Changes to wrappers should normally be made and tested in `xray-rust` first,
then synchronized here with `scripts/sync-upstream.sh --force`. The flag is
required because synchronization replaces the adapter snapshots and removes
extra files. Distribution-only
changes belong in this repository.

Before opening a pull request:

~~~sh
scripts/check-release.sh --prepare
~~~

Run the platform build relevant to the change. Never commit credentials,
private keys, live proxy profiles, downloaded geodata, native build outputs,
or signing identities.
