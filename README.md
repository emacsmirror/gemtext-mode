# Gemtext Mode

*gemtext-mode* is a major mode for editing [Gemtext](https://geminiprotocol.net/docs/gemtext.gmi)-formatted text with GNU Emacs. This mode is a free software, licensed under the [GNU GPL, version 3 or later](LICENSE.txt).

## Installation

### MELPA

You can install *gemtext-mode* from MELPA.

First, you have to configure GNU Emacs to get packages from MELPA if you haven't yet:
```elisp
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/") t)
```
Then, you just have to install *gemtext-mode* like any other package:
```elisp
(package-install 'gemtext-mode)
(require 'gemtext-mode)
```

### Direct download

You can manually download and install *gemtext-mode* :

* Download a stable version of the file `gemtext-mode.el` (check [the Git repository](https://git.sr.ht/~arjca/gemtext-mode.el)), and save it where GNU Emacs can find it (somewhere on your `load-path`!) ;

* Add the following lines in your GNU Emacs configuration :
```elisp
(autoload 'gemtext-mode "gemtext-mode"
  "Major mode for Gemtext-formatted text." t)
(add-to-list 'auto-mode-alist '("\\.gmi\\'" . gemtext-mode))
```

### Development version

To contribute to the mode, you can clone locally the [Git repository](https://git.sr.ht/~arjca/gemtext-mode.el) :
```
git clone https://git.sr.ht/~arjca/gemtext-mode.el
```
Instructions for contributing are given in the [CONTRIBUTING file](CONTRIBUTING.md).

## Usage

The mode, when enabled, highlights the syntax of Gemtext files. It also enables some shortcuts that are listed in the following table.

| Key       | Function name               | Description                                                                                               |
|-----------|-----------------------------|-----------------------------------------------------------------------------------------------------------|
| `TAB`     | gemtext-cycle               | When used on a heading (line beginning with `#`, `##` or `###`), show or hide the content of the section. |
| `M-RET`   | gemtext-insert-ulist-item   | Add a new unordered list item (line beginning with `*`)                                                   |
| `C-c C-p` | gemtext-insert-pre-block    | Add a new preformatted text block with an optional alternative text.                                      |
| `C-c C-c` | gemtext-narrow-to-pre-block | Open a buffer with the content of the preformatted text block. `C-c C-c` again to exit.                   |

You can also use `yank-media` to copy your clipboard as a local file and automatically add a link to this file in your document.

## Alternatives

### `gemini-mode`

* URL: [https://git.carcosa.net/jmcbray/gemini.el](https://git.carcosa.net/jmcbray/gemini.el)
