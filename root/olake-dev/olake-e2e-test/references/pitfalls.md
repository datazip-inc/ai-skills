# Pitfalls

Lessons that apply across steps.
A lesson that belongs to one step lives in that step of `SKILL.md`, not here.
After every test, add each new mistake here with the rule that prevents it; when it clearly belongs to one step, move it into that step instead.

## Planning

1. Test only supported paths.
   Ask before testing anything marked deprecated in the code or the docs.
2. A case that is expected to fail gets the smallest retry setting, and runs last or in the background.
   A retry setting of 0 often means "use the default", not "no retries": check the spec.

## Deploy

3. Start slow or emulated containers (amd64 on an ARM Mac) first, in the background.

## Shell

4. Never print raw discover or sync logs, or discover result files: the catalog is one huge line.
   Filter logs with `grep` and cut lines with `cut -c1-250`; read result files with a script that prints only the fields needed.
5. Never keep a command in a shell variable, and never send stderr to `/dev/null` while seeding.
   zsh does not word-split variables, so the command silently does nothing.
6. macOS has no `timeout` command.
   Bound commands with the tool timeout or a polling loop.
7. Never put inline code inside a quoted shell string in a polling loop (`python3 -c '...'` with nested quotes).
   It breaks silently, prints nothing, and the loop never sees the end state.
   Write the code to a file.
8. Quote every argument that holds `*`, `?` or `[`, such as `--include='*.go'` or `-o 'custom-columns=IMAGE:.spec.containers[0].image'`.
   zsh treats them as a filename pattern, and when no file matches it aborts the command with `no matches found` before the command runs.
