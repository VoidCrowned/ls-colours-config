# ls_colours_config

My terminal tool for the file that decides the colours of `ls`: it previews, checks, repairs and edits a GNU `dircolors` configuration. One bash script, no dependencies beyond bash and GNU coreutils.

<p align="center"><em>Screenshot placeholder: <code>docs/screenshot.png</code> (the editor with the colour picker open)</em></p>

## Install

Copy the one file somewhere on your `PATH` and make it executable:

```sh
curl -fsSLo ~/.local/bin/ls_colours_config https://raw.githubusercontent.com/VoidCrowned/ls_colours_config/main/ls_colours_config
chmod +x ~/.local/bin/ls_colours_config
```

## Usage

```sh
ls_colours_config COMMAND [OPTIONS] [FILE]
```

Without `FILE` it takes the first that exists of `$XDG_CONFIG_HOME/dircolors`, `$XDG_CONFIG_HOME/.dir_colors`, `~/.dir_colors`, `~/.dircolors`. If there is none, it offers to create one from the built-in sample ([examples/dircolors.sample](examples/dircolors.sample)).

### `preview`

Creates a temporary directory with one sample per entry and lists it with the real `ls`, with the colours loaded through `dircolors -b` the way a shell does it. The listing is grouped by the section comments of the file, covers the file types as well (directory, links, fifo, setuid and so on) and ends with the findings of `check`.

- `--codes`: one entry per line with its pattern and colour code.
- `--keep`: keep the sample directory and print its path.
- In a pipe the output is plain text; `--colour always` keeps the colours.

### `check`

A linter. It exits with 0 when the file is clean and 1 when it found something, and reports:

- patterns that are defined more than once, with every definition and the one in effect
- black or concealed text, blink, malformed and unknown colour codes, 256-colour codes when `--256` is off
- keys without a value and unknown keywords
- the obsolete keywords `COLOR`, `OPTIONS` and `EIGHTBIT`
- `TERM` lines that restrict nothing, and colour lines that the current `TERM` switches off
- entries in a section that contradicts them (a video extension under "audio"), and case twins with different colours
- entries whose colour differs from the one at least 80 % of their category have
- file types that are not set and common patterns without a colour

`--ignore LIST` skips kinds of findings; `ls_colours_config help check` lists the names.

### `fix`

Walks through those findings and repairs them. Every step asks first:

1. **Duplicates:** pick the definition to keep. Enter keeps the last one, which is the one `ls` uses already.
2. **Lines that do nothing:** obsolete keywords, dead `TERM` lines, redundant case twins.
3. **Colours that stand out:** entries that differ from the colour nearly all entries of their category have (one red document among blue ones). Change all, some or none.
4. **Missing entries:** new entries get the colour that most entries of the same category have in your file; if there is no majority, the value from `dircolors --print-database`. Accept all, per category or per entry. Each suggestion says where it comes from: the built-in table, the system database, or `--scan DIR` (extensions that occur under `DIR` and get no colour).
5. **Reorganise:** group the patterns by category and sort each section, case twins next to each other. This is the only step that moves lines.

Then it shows the complete diff and asks once before writing.

### `edit`

A full-screen editor for the colours of existing entries. Each row shows a sample name in its current colour. Enter opens a picker for foreground, background and bold, dim, underline, reverse and blink with a live preview; typing a code by hand is possible (`e`) but never needed.

Keys: arrows or `h` `j` `k` `l`, Enter, `/` search, `c` join or separate case pairs, `u` undo, `s` save, `q` quit, `?` help.

Case pairs such as `.deb` / `.DEB` are one entry and are edited together. Changes are staged and only written after you have seen the diff and confirmed.

## Options

| Option | Effect |
|---|---|
| `--256` | Allow 256-colour codes: the picker offers the full palette and `check` stops reporting them. Existing 256-colour values are always shown correctly and never altered unless you edit them. |
| `--case-sensitive` | Treat `.deb` and `.DEB` as two separate entries. |
| `--dry-run`, `-n` | `fix` and `edit` show what would change and write nothing. |
| `--scan DIR` | `check` and `fix` also suggest the extensions found under `DIR`. |
| `--term NAME` | Judge `TERM` lines as if `$TERM` were `NAME`. |
| `--colour WHEN` | `auto` (default), `always` or `never`. `--no-colour` is short for `never`. |

Every option with "colour" in its name also accepts the spelling "color".

## What it does to your file

- Nothing without your confirmation in that run.
- Lines it does not change stay byte for byte as they are: comments, blank lines, order and whitespace.
- Before the first write it makes a backup next to the file (`FILE.bak-DATE-TIME`), then replaces the file atomically. If nothing changed, nothing is written.

## Upper-case twins

Many configs list every extension twice (`.jpg` and `.JPG`). Newer versions of GNU `ls` match extensions without regard to case as long as the differently-cased entries do not disagree, which makes the twins redundant. The tool tests the installed `ls` instead of guessing from a version number; where the twins are redundant, `check` says so and `fix` offers to drop them.

## Requirements

- bash 4.0 or newer
- GNU coreutils (`ls`, `dircolors`). Where they are installed as `gls` / `gdircolors` (macOS with Homebrew coreutils) or `gnuls` / `gnudircolors`, those are used.

## Known limitations

- GNU only. The BSD `LSCOLORS` format is not supported, and macOS is untested.
- `edit` changes existing entries only; adding and moving entries is the job of `fix`.
- Sections are recognised by the comment line above a group of patterns, and their category by words in that comment ("archives", "audio", ...). Unusual headings give a section no category.
- The picker offers 16 or 256 colours. 24-bit colours are displayed and kept, but can only be entered as a code.
- Sockets and device nodes cannot be created without help, so `preview` lists existing ones from `/run` and `/dev`, or leaves them out.
- `fix` reorganises only patterns that apply to every terminal; lines behind a `TERM` line stay where they are.

## Tests

```sh
tests/run.sh          # add --json for a summary line to paste into an issue
```

## Licence

Copyright © 2026 VoidCrowned. This program is free software. It comes without any warranty, to the extent permitted by applicable law. You can redistribute it and/or modify it under the terms of the Do What The Fuck You Want To Public License, Version 2, as published by Sam Hocevar. See [LICENSE](LICENSE) or http://www.wtfpl.net/ for more details.
