macOS-setup
===========

Rationale
---------

When setting up a new Mac, you should set some sensible macOS defaults.

Usage
-----

> Note: The apply mode is idempotent: it can safely be run multiple times.

Inspect configured settings without changing macOS preferences:

```bash
./macos-setup --help
./macos-setup --list
./macos-setup --dry-run
./macos-setup --check
```

Limit a mode to one section:

```bash
./macos-setup --section screen --check
./macos-setup --section safari --dry-run
```

Apply desired settings explicitly:

```bash
./macos-setup --apply
```

Safety: only `--apply` writes preferences or quits System Settings/System Preferences. Running without a mode exits with an error instead of applying changes.

Compatibility
-------------

This utility is designed to conform to the [XDG Base Directory Specification][xdg-dirspec] and be compatible with [Dotbot][dotbot], [strap][strap], and other system bootstrap tools. Use it standalone or as a `git` submodule in your `dotfiles`.

> Hint: Create a symbolic link to `macos-setup` in either `~` (e.g., `~/.macos`) or in `$PATH` (e.g., `~/.local/bin`).

Helpful documentation
---------------------

* [macOS-Defaults/REFERENCE.md][suttle-reference] - macOS command reference by [@kevinSuttle][@kevinSuttle]
* [macOS defaults][macos-defaults] - List of macOS `defaults` commands with demos by [@yannbertrand][@yannbertrand]

Credit
------

I was inspired by [@mathiasbynens](https://mathiasbynens.be)'s great work fostering a community of interest around documenting macOS default configuration from the command-line.

Thanks Mathias!

[xdg-dirspec]: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
[dotbot]: https://github.com/anishathalye/dotbot
[strap]: https://github.com/MikeMcQuaid/strap
[suttle-reference]: https://github.com/kevinSuttle/macOS-Defaults/blob/master/REFERENCE.md
[@kevinSuttle]: https://github.com/kevinSuttle
[macos-defaults]: https://macos-defaults.com
[@yannbertrand]: https://github.com/yannbertrand
