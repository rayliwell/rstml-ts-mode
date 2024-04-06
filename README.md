# rstml-ts-mode

A major-mode for editing [rstml](https://github.com/rs-tml/rstml) (rust + html).

This library relies on tree-sitter support added to Emacs 29.1 to provide a better editing experience with Rust web frameworks, like [Leptos](https://github.com/leptos-rs/leptos). It is based on [rust-ts-mode](https://github.com/emacs-mirror/emacs/blob/master/lisp/progmodes/rust-ts-mode.el).

| **Before (`rust-ts-mode`)**                      | **After (`rstml-ts-mode`)**                    |
|--------------------------------------------------|------------------------------------------------|
| ![before](/assets/emacs_before_highlighting.png) | ![after](/assets/emacs_after_highlighting.png) |

## Installation

Using a package manager, such as [straight.el](https://github.com/radian-software/straight.el):

```elisp
(use-package rstml-ts-mode
  :straight (rstml-ts-mode :host github
                           :repo "rayliwell/rstml-ts-mode"))
```

### Grammar installation

The `rust_with_rstml` language grammar from [tree-sitter-rstml](https://github.com/rayliwell/tree-sitter-rstml) must be compiled and installed. This can be done by calling `rstml-ts-mode-install-language-grammar` or by evaluating:

```elisp
(add-to-list 'treesit-language-source-alist
             '(rust_with_rstml
               "https://github.com/rayliwell/tree-sitter-rstml"
               "main"
               "rust_with_rstml/src"))
```

Then running `M-x treesit-install-language-grammar [RET] rust_with_rstml`. This should only need to be done once.

## Usage

To automatically switch to `rstml-ts-mode` whenever a Rust file is open, the easiest way is to modify `major-mode-remap-alist`:

```elisp
(use-package rstml-ts-mode
  :straight (rstml-ts-mode :host github
                           :repo "rayliwell/rstml-ts-mode")
  :config
  (add-to-list 'major-mode-remap-alist '(rust-ts-mode . rstml-ts-mode)))
```

## License

This package is based on [rust-ts-mode](https://github.com/emacs-mirror/emacs/blob/master/lisp/progmodes/rust-ts-mode.el).

> Copyright (C) 2022-2024 Free Software Foundation, Inc.
> Copyright (C) 2024 Ryan Halliwell
>
> This program is free software; you can redistribute it and/or modify
> it under the terms of the GNU General Public License as published by
> the Free Software Foundation, either version 3 of the License, or
> (at your option) any later version.
>
> This program is distributed in the hope that it will be useful,
> but WITHOUT ANY WARRANTY; without even the implied warranty of
> MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
> GNU General Public License for more details.
>
> You should have received a copy of the GNU General Public License
> along with this program.  If not, see <https://www.gnu.org/licenses/>.
