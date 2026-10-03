# Read this first: your context budget and your rules

The wrapper adds this section to every brief. The brief that follows it is your task.

## Context budget

Your context is limited. When one step's context passes 100K tokens, the wrapper stops your run, and the work you have not finished is lost to you. Obey these rules:

- Do NOT read `AGENTS.md`. The rules you need are in this section.
- Do NOT read `tools/check_lib.sh`, `tools/README.md`, `docs/REPORTING-GATE.md` or `tools/headless.sh`. The brief gives the commands to run. Grep one of them only when the brief tells you to.
- Read only the files and line ranges the brief names. To find anything else, use `grep -n`, then read only the lines you need (`sed -n A,Bp`). Do not read a whole file of more than 300 lines.
- Send build and check output to a file under `logs/`, then read only its last lines or the lines that grep finds.
- Finish in about 40 steps. If the work is larger than that, stop and report what is done and what remains.

## Rules you must obey

- Your brief IS your approval. Implement it; do NOT stop to ask for approval.
- NEVER delete an existing guard, bounds check, invariant, assertion or test to fit new code. If one blocks you, STOP, and report its file and line and why.
- Build ONLY with `BACKEND=posix ./build_macos.sh`. NEVER run `./incursion`.
- Do NOT run, edit or report as failing: `check_flavor_stability.sh`, `check_convert_guard.sh`, `check_stair_warn.sh`, `check_dup_names.sh`.
- Run NO git command that changes state. Read-only git (`status`, `diff`, `log`, `show`, `ls-files`, `rev-parse`) is allowed. Leave all changes in the working tree.
- Run NO `bd` and NO `gh`.
- Put a reproduction (key script, seed, options file, command) in `tools/`. Write any specimen (screen dump, log, save, crash report) under `logs/` only, and name its path in your report.
- Stay in scope: no edits to a spec or plan unless the brief says so, and no unrelated formatting changes. If the brief is wrong, say so with evidence; do not implement what you believe is wrong.
- In your report, list every deletion separately from the additions.
