# IslandZed

A fork of [Zed](https://github.com/zed-industries/zed) carrying a small set of patches for floating-island chrome, rounded content masks, and a few other UI tweaks.

## Layout

- `source/` — git submodule pointing at upstream Zed, pinned to a specific SHA.
- `patches/` — generated patch files applied on top of the pinned source.
- `scripts/` — patch tooling.

## Patch workflow

Patches are stored as files in `patches/`, but the **source of truth** is a local branch `islandzed/applied` inside `source/`. Each commit on that branch corresponds to one patch file. Editing a patch means editing a commit; `patches/*.patch` are regenerated from the branch via `git format-patch`.

This means you never hand-edit unified-diff hunk headers. `git rebase` handles upstream drift automatically.

### First-time setup (after fresh clone)

```sh
git submodule update --init
./scripts/init-patches-branch.sh
```

This builds `islandzed/applied` by replaying `patches/*.patch` as commits on top of the pinned SHA. Identity/date are fixed so the resulting commit SHAs are reproducible across machines.

### Apply patches to a working tree

```sh
./scripts/apply-patches.sh         # apply
./scripts/apply-patches.sh reset   # reset source/ back to pin
```

`apply-patches.sh` uses `git apply` against a clean checkout at the pin. Run `reset` before re-applying after changes.

### Edit an existing patch

```sh
cd source
git checkout islandzed/applied
# edit code, then commit/amend/rebase as usual
git commit --amend       # or: git commit, git rebase -i, ...

cd ..
./scripts/regen-patches.sh
```

`regen-patches.sh` runs `git format-patch <pin>..islandzed/applied` and rewrites `patches/*.patch`. It enforces that the branch has exactly the expected number of commits in the expected subject order — if you reordered commits, added one, or removed one, update the `EXPECTED_PATCHES` array in all three scripts (`apply-patches.sh`, `init-patches-branch.sh`, `regen-patches.sh`) and rerun.

### Bump the submodule pin

```sh
cd source
git fetch origin
git checkout islandzed/applied
git rebase <new-upstream-sha>
# resolve any conflicts per-commit using normal git merge tooling

cd ..
git -C source checkout <new-upstream-sha>   # update detached HEAD that submodule tracks
./scripts/regen-patches.sh
git add source patches/
```

The rebase uses 3-way merge, so context drift in upstream (the pain point that string-based `git apply` chokes on) is handled by git itself. Conflicts surface one commit at a time.

### Adding a new patch

1. Check out `islandzed/applied` and make a commit with a descriptive subject (the subject becomes the patch filename).
2. Add the patch name to `EXPECTED_PATCHES` in all three scripts in the desired apply order.
3. Run `./scripts/regen-patches.sh`.
