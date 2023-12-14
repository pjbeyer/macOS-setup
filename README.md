macOS-setup
===========

Rationale
---------

When setting up a new Mac, you should set some sensible macOS defaults.

Usage
-----

> Note: The script is idempotent: it can safely be run multiple times.

```bash
./macos-setup
```

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
