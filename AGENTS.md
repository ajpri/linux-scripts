# Repository instructions

This repository contains standalone Linux shell utilities. Keep each utility easy
to download, inspect, and run independently.

## Structure and documentation

- Keep standalone scripts in the repository root.
- Put detailed user documentation in `docs/<script-name>.md`, omitting `.sh`
  from the guide filename. Link each guide back to the README and script source.
- Keep the README's script index and script sections alphabetical, ignoring case.
- Limit README entries to a brief description, requirements, quick-start commands,
  and a link to the detailed guide.
- Update the corresponding guide whenever behavior, options, dependencies, or
  configuration change. Keep examples consistent with the implementation.
- Describe utilities by their general purpose rather than the personal task that
  originally motivated them.

## Shell conventions

- Follow the script's existing Bash conventions and preserve executable modes.
- For new scripts, prefer `set -euo pipefail` with explicit handling of expected
  failures. Do not retrofit strict mode into older scripts without checking its
  effects on their behavior.
- Quote paths and variable expansions, preserve paths containing spaces, and
  validate user input before destructive operations.
- Keep scripts self-contained unless the task explicitly requires shared files.
- Document new dependencies and retain compatibility with existing saved
  configuration unless a change is explicitly requested.

## Validation and privacy

- Run `bash -n` on changed shell scripts and `git diff --check` before committing.
- Test behavior changes with relevant temporary fixtures or mocked services.
  Do not run installers, send proposals, control devices, or stop live processes
  merely to test a change without authorization.
- Check local Markdown links, alphabetical ordering, and examples after
  reorganizing documentation.
- Keep credentials, private configuration, backup archives, and test artifacts
  out of commits. Use placeholder URLs and credentials in examples.
- Do not introduce personal deployment defaults into general-purpose utilities.
  Preserve explicitly approved personal configuration unless asked to change it.
- Report what was tested and any material limitations; do not imply that every
  script has the same level of testing or compatibility.

## Git workflow

- Do not commit or push unless the user requests it. Follow their requested branch
  and scope, and stage only intended files.
- When it is time to commit and push, prefer a single cohesive commit for the
  requested changes rather than multiple incremental commits. Follow an explicit
  request for a different commit structure if given.
- Review the staged diff before committing. Include relevant script and
  documentation changes together, and never rewrite published history merely to
  achieve a single commit without explicit authorization.
