# My neovim config based on kickstart

Dependencies: [DEPENDENCIES.md](DEPENDENCIES.md). Plugin versions are pinned in `lazy-lock.json`
(`:Lazy restore` installs them; after `:Lazy update` run the tests and commit the lock).

## Tests

`tests/run.sh` checks the config on the small Java / Python / C projects in `tests/fixtures`,
copied to a fresh temporary directory:

- `tests/run.sh` — startup of each language (servers, IDE keys, no errors) and the debugger
  stopping at a breakpoint in each;
- `tests/run.sh scenario [N]` — a work session in a real nvim inside a private tmux server:
  tests from the context, debugging, files changed behind the editor (an "LLM agent"), Recent
  Changes, Rename, tests again, then N random tool-window / IDE actions;
- `tests/run.sh all` — both. The exit status is the number of failures.
