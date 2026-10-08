# Workflow

- `main` is always releasable. Nothing is committed to it directly after the initial commit.
- Every change is a branch: `feature/<short-name>`, `fix/<short-name>`, or `chore/<short-name>`.
- Open a pull request into `main`, then **merge with a merge commit**. Do not squash or rebase-merge, so each branch's history stays visible.
- Delete the branch after merging.
- Releases: run `scripts/release.ps1` on a branch (`chore/release-x.y.z`), merge that PR, then tag `vX.Y.Z` on `main`.
