# Gemtext Mode

*gemtext-mode* is a major mode for editing [Gemtext](https://geminiprotocol.net/docs/gemtext.gmi)-formatted text. This mode is a free software, licensed under the [GNU GPL, version 3 or later](LICENSE.txt).

## Installation

### Direct download

You can manually download and install gemtext-mode :
* Download a stable version of the file `gemtext-mode.el` (check the latest tag on [the Git repository](https://git.sr.ht/~arjca/gemtext-mode.el)), and save it where GNU Emacs can find it (check the list `load-path` of your configuration !) ;
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

| Key     | Function name             | Description                                                                                         |
|---------|---------------------------|-----------------------------------------------------------------------------------------------------|
| TAB     | gemtext-cycle             | When used on a heading (line beginning with #, ## or ###), show or hide the content of the section. |
| M-RET   | gemtext-insert-ulist-item | Add a new unordered list item (line beginning with *)                                               |
| C-c C-p | gemtext-insert-pre-block  | Add a new preformatted text block with an optional alternative text.                                |

## Alternatives

### `gemini-mode`

* URL: [https://git.carcosa.net/jmcbray/gemini.el](https://git.carcosa.net/jmcbray/gemini.el)

`gemini-mode` is a mode available on `melpa` with similar features: highlighting and some editing utilities. Its source code is very simple, but that simplicity lead to some defects that cannot be (at the best of my knowledge) solved without an important rework. For instance, the mode is struggling with files containing several preformatted text blocks (e.g., it fontifies the content between two blocks as preformatted text); this is due to the way fontification is implemented, based on regular expressions. That design decision make it also inconvenient to implement some features to the mode (e.g., folding sections).

`gemtext-mode` was initially a patch for `gemini-mode`, replacing RegExp-based fontification by syntax propertization but ended with a completely different code base. This is why it was not submitted for merging in `gemini-mode`.
