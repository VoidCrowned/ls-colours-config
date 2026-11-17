# ls_colours_config

My terminal tool for the file that decides the colours of `ls`: it previews, checks, repairs and edits a GNU `dircolors` configuration. One bash script, no dependencies beyond bash and GNU coreutils.

## The editor
<details close><summary>(Click to expand)</summary>
<br>
<p align="center"><img src="docs/edit_view.png" alt="The editor with the picker beside the list: the file types section unfolded, each entry in its colour with the colour in words, and on the right the new and old sample, the foreground and background palettes and the attribute switches"></p></details>

## Select from list/categories
<details close><summary>(Click to expand)</summary>
<br>
<p align="center"><img src="docs/section_view.png" alt="The section view: one row per section with its number of entries, its main colour and how many entries differ, the file types section unfolded"></p></details>

## Select by palette grouping
<details close><summary>(Click to expand)</summary>
<br>
<p align="center"><img src="docs/palette_view.png" alt="The palette view: the entries grouped by colour, most used first, a few groups unfolded to show their entries and sections"></p></details>

## Install

Copy the one file somewhere on your `PATH` and make it executable:

```sh
curl -fsSLo ~/.local/bin/ls_colours_config.sh https://raw.githubusercontent.com/VoidCrowned/ls_colours_config/main/ls_colours_config.sh
chmod +x ~/.local/bin/ls_colours_config.sh
```

## Usage

```sh
ls_colours_config.sh COMMAND [OPTIONS] [FILE]
```

| Command | |
|---|---|
| `preview` | list one sample per entry with the real `ls`, then run `check` |
| `check` | report problems in the file (exit status 1 when there are any) |
| `fix` | walk through the problems found by `check` and repair them |
| `edit` | change colours in a full-screen editor (`?` lists the keys) |
| `sample` | print the built-in sample config |
| `help` | show the help, or the help of a command: `help edit` |

Without `FILE` it takes the first that exists of `$XDG_CONFIG_HOME/dircolors`, `$XDG_CONFIG_HOME/.dir_colors`, `~/.dir_colors` and `~/.dircolors`, or offers to create one from the [sample](examples/dircolors.sample). `ls_colours_config.sh help COMMAND` lists the options.

## What it does to your file

Nothing without your confirmation: you see the diff first, a backup is made next to the file, and lines it does not change stay byte for byte as they are.

## Requirements

- bash 4.0 or newer
- GNU coreutils (`ls`, `dircolors`); `gls` / `gdircolors` and `gnuls` / `gnudircolors` work too

GNU only: the BSD `LSCOLORS` format is not supported, and macOS is untested.

## Tests

```sh
tests/run.sh          # add --json for a summary line to paste into an issue
```

## Licence

Copyright © 2026 VoidCrowned. This program is free software. It comes without any warranty, to the extent permitted by applicable law. You can redistribute it and/or modify it under the terms of the Do What The Fuck You Want To Public License, Version 2, as published by Sam Hocevar. See [LICENSE](LICENSE) or http://www.wtfpl.net/ for more details.
