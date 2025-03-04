;;; gemtext-mode.el --- Major mode for Gemtext-formatted text -*- lexical-binding: t; -*-

;; Copyright (C) 2023-2024 Antoine Aubé

;; Author: Antoine Aubé <courriel@arjca.fr>
;; Created: 28 Oct 2023

;; Package-Requires: ((emacs "29.1"))
;; Version: 1.0
;; Keywords: languages, gemtext, gemini
;; URL: https://sr.ht/~arjca/gemtext-mode.el/

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.
;; If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This file provides a major mode for editing Gemtext files (common
;; extension: .gmi).  This mode highlights the syntax of Gemtext and
;; adds some editing utilities.

;; Many source code elements of this file are derived from the code
;; of `markdown-mode.el'.


;;; Code:

(require 'cl-lib)
(require 'outline)

(defvar jit-lock-start)
(defvar jit-lock-end)

(defgroup gemtext nil
  "Major mode for editing text files in Gemtext format."
  :prefix "gemtext-"
  :group 'text
  :link '(url-link "https://sr.ht/~arjca/gemtext-mode.el/"))

(defvar gemtext-mode-hook nil
  "Hook run when entering Gemtext mode.")


;;; Syntax regular expressions

(defconst gemtext-regexp-heading
  "^\\(?1:#\\|##\\|###\\)[[:blank:]]+\\(?2:.*\\)$"
  "Regular expression for matching any heading.
Group 1 matches the markup.
Group 2 matches the title.")

(defconst gemtext-regexp-ulist-item
  "^\\(?1:*\\)[[:blank:]]+\\(?2:.*\\)$"
  "Regular expression for matching unordered list items.
Group 1 matches the bullet.
Group 2 matches the item content.")

(defconst gemtext-regexp-blockquote
  "^\\(?1:>\\)[[:blank:]]*\\(?2:.*\\)$"
  "Regular expression for matching blockquote lines.
Group 1 matches the angle bracket.
Group 2 matches the quoted text.")

(defconst gemtext-regexp-link
  "^\\(?1:=>\\)[[:blank:]]?\\(?2:[^[:blank:]\n]+\\)\\(?3:[[:blank:]]?.*\\)?$"
  "Regular expression for matching links.
Group 1 matches the markup.
Group 2 matches the URL.
Group 3 matches the optional label.")

(defconst gemtext-regexp-pre-fence-begin
  "^\\(?1:```\\)[[:blank:]]*\\(?2:.*\\)$"
  "Regular expression for matching opening fence of pre blocks.")

(defconst gemtext-regexp-pre-fence-end
  "^\\(?1:```\\)[[:blank:]]*$"
  "Regular expression for matching preformatted text blocks closing fence.")


;;; Syntax propertization

(defun gemtext-syntax-propertize (start end)
  "Function used as `syntax-propertize-function'.
START and END delimit region to propertize."
  (with-silent-modifications
    (save-excursion
      (remove-text-properties start end gemtext-syntax-properties)
      (gemtext-syntax-propertize-pre-blocks start end)
      (gemtext-syntax-propertize-headings start end)
      (gemtext-syntax-propertize-ulists start end)
      (gemtext-syntax-propertize-blockquotes start end)
      (gemtext-syntax-propertize-links start end))))

(defvar gemtext-syntax-properties
  (list 'gemtext-pre-fence-begin nil
        'gemtext-pre-fence-end nil
        'gemtext-pre-text nil
        'gemtext-heading nil
        'gemtext-ulist nil
        'gemtext-blockquote nil
        'gemtext-link nil)
  "Property list of all Gemtext syntactic properties.
These properties are used for fontification and folding headings.")

(defun gemtext-syntax-propertize-pre-blocks (start end)
  "Match preformatted text blocks from START to END."
  (save-excursion
    (goto-char start)
    ;; start from previous unclosed block, if exists
    (let ((prev-begin-block (gemtext-find-previous-open-pre-block)))
      (when prev-begin-block
        (let* ((enclosed-text-start (min (point-max)
                                         (1+ prev-begin-block))))
          (gemtext-propertize-pre-end-match end
                                            enclosed-text-start))))
    ;; find all new blocks within region
    (while (re-search-forward gemtext-regexp-pre-fence-begin end t)
      ;; we assume the opening constructs take up (only) an entire line,
      ;; so we re-check the current line
      (let* ((enclosed-text-start (save-excursion (min (point-max)
                                                       (1+ (line-end-position))))))
        (save-excursion
          (beginning-of-line)
          (re-search-forward
           gemtext-regexp-pre-fence-begin
           (line-end-position)))
        ;; mark starting, even if ending is outside of region
        (put-text-property (match-beginning 0)
                           (match-end 0)
                           'gemtext-pre-fence-begin
                           (match-data t))
        (gemtext-propertize-pre-end-match end
                                          enclosed-text-start)))))

(defun gemtext-find-previous-open-pre-block ()
  "Get the starting position of the open preformatted text block at POS.
If there is one, returns the position of the first character of preformatted
content.
If not, returns nil."
  (let ((start-pt (point))
        ;; Position of the previous opening fence
        (closest-opening-fence-pos
         (gemtext-find-previous-prop 'gemtext-pre-fence-begin)))
    (when closest-opening-fence-pos
      (let* (;; Location where the property ends
             (end-prop-loc
              (save-excursion
                (save-match-data
                  (goto-char closest-opening-fence-pos)
                  (and (re-search-forward gemtext-regexp-pre-fence-end start-pt t)
                       (match-beginning 0))))))
        ;; If there is no closing fence after the closest opening fence,
        ;; then the block is not closed
        (and (not end-prop-loc)
             closest-opening-fence-pos)))))

(defun gemtext-find-previous-prop (prop &optional lim)
  "Find previous place where property PROP is non-nil, up to LIM.
Return a point that contains non-nil PROP."
  (let ((res (if (get-text-property (point) prop)
                 (point)
               (previous-single-property-change (point)
                                                prop
                                                nil
                                                (or lim
                                                    (point-min))))))
    ;; When res has nil PROP but the previous character does not
    (when (and (not (get-text-property res prop))
               (> res (point-min))
               (get-text-property (max (point-min)
                                       (1- res))
                                  prop))
      (cl-decf res))
    ;; When res has non-nil PROP
    (when (and res
               (get-text-property res prop))
      res)))

(defun gemtext-propertize-pre-end-match (end middle-begin)
  "Get match for pre fence up to END, if exists, and propertize appropriately.
MIDDLE-BEGIN is the start of the \"middle\" section of the block."
  (when (re-search-forward gemtext-regexp-pre-fence-end end t)
    (let ((close-begin (match-beginning 0)) ; Start of closing line.
          (close-end (match-end 0))         ; End of closing line.
          (close-data (match-data t)))      ; Match data for closing line.
      ;; Propertize middle section of fenced block.
      (put-text-property middle-begin
                         close-begin
                         'gemtext-pre-text
                         (list middle-begin close-begin))
      ;; Propertize closing line of fenced block.
      (put-text-property close-begin
                         close-end
                         'gemtext-pre-fence-end
                         close-data))))

(defun gemtext-syntax-propertize-headings (start end)
  "Propertize heading from START to END."
  (gemtext-syntax-propertize-markup-on-single-line start end
                                                   gemtext-regexp-heading
                                                   (list 'gemtext-heading)))

(defun gemtext-syntax-propertize-ulists (start end)
  "Propertize unordered list items from START to END."
  (gemtext-syntax-propertize-markup-on-single-line start end
                                                   gemtext-regexp-ulist-item
                                                   (list 'gemtext-ulist)))

(defun gemtext-syntax-propertize-blockquotes (start end)
  "Propertize blockquotes from START to END."
  (gemtext-syntax-propertize-markup-on-single-line start end
                                                   gemtext-regexp-blockquote
                                                   (list 'gemtext-blockquote)))

(defun gemtext-syntax-propertize-links (start end)
  "Propertize links from START to END."
  (gemtext-syntax-propertize-markup-on-single-line start end
                                                   gemtext-regexp-link
                                                   (list 'gemtext-link)))

(defun gemtext-syntax-propertize-markup-on-single-line (start end regexp properties)
  "Propertize a line with markup from START to END.
The line follows REGEXP.*
The added properties are PROPERTIES."
  (save-excursion
    (goto-char start)
    (while (and (re-search-forward regexp end t)
                (not (gemtext-pre-text-at-pos (match-beginning 0))))
      (dolist (prop properties)
        (put-text-property (match-beginning 0) (match-end 0)
                           prop
                           (match-data t))))))

(defun gemtext-pre-text-at-pos (pos)
  "Return match data list if there is a preformatted text at POS.
Uses text properties at the beginning of the line position.
Return nil otherwise."
  (let ((bol (save-excursion
               (goto-char pos)
               (line-beginning-position))))
    (get-text-property bol 'gemtext-pre-text)))

(defun gemtext-syntax-propertize-extend-region (start end)
  "Extend START to END region to include an entire block of text.
This helps improve syntax analysis for block constructs.
Returns a cons (NEW-START . NEW-END) or nil if no adjustment should be made.
Function is called repeatedly until it returns nil.
For details, see `syntax-propertize-extend-region-functions'."
  (save-match-data
    (save-excursion
      (let* ((new-start (progn (goto-char start)
                               (skip-chars-forward "\n")
                               (if (re-search-backward "\n\n" nil t)
                                   (min start (match-end 0))
                                 (point-min))))
             (new-end (progn (goto-char end)
                             (skip-chars-backward "\n")
                             (if (re-search-forward "\n\n" nil t)
                                 (max end (match-beginning 0))
                               (point-max))))
             (code-match (gemtext-pre-text-at-pos new-start))
             (new-start (min (or (and code-match (cl-first code-match))
                                 (point-max))
                             new-start))
             (code-match (and (< end (point-max))
                              (gemtext-pre-text-at-pos end)))
             (new-end (max (or (and code-match (cl-second code-match)) 0)
                           new-end)))
        (unless (and (eq new-start start) (eq new-end end))
          (cons new-start (min new-end (point-max))))))))


;;; Syntax property matchers

(defun gemtext-match-propertized-text (property last)
  "Match text with PROPERTY from point to LAST.
Restore match data previously stored in PROPERTY."
  (let ((saved (get-text-property (point) property))
        position)
    ;; If nothing is saved at point, look for text with PROPERTY before LAST
    (unless saved
      (setq position (next-single-property-change (point) property nil last))
      (unless (= position last)
        (setq saved (get-text-property position property))))
    (when saved
      (set-match-data saved)
      ;; Step at least on character beyond point.
      ;; Otherwise, `font-lock-fontify-keywords-region' infloops.
      (goto-char (min (1+ (max (match-end 0)
                               (point)))
                      (point-max))))))

(defun gemtext-match-headings (last)
  "Match headings from point to LAST.
Use data stored in \\='gemtext-heading text property during syntax
propertization."
  (gemtext-match-propertized-text 'gemtext-heading last))

(defun gemtext-match-ulist-items (last)
  "Match unordered list items from point to LAST.
Use data stored in \\='gemtext-ulist text property during syntax
propertization."
  (gemtext-match-propertized-text 'gemtext-ulist last))

(defun gemtext-match-blockquotes (last)
  "Match blockquotes from point to LAST.
Use data stored in \\='gemtext-blockquote text property during syntax
propertization."
  (gemtext-match-propertized-text 'gemtext-blockquote last))

(defun gemtext-match-links (last)
  "Match links from point to LAST.
Use data stored in \\='gemtext-link text property during syntax
propertization."
  (gemtext-match-propertized-text 'gemtext-link last))

(defun gemtext-match-pre-fence-begin (last)
  "Match preformatted text block opening fence from point to LAST.
Use data stored in \\='gemtext-pre-fence-begin text property during syntax
propertization."
  (gemtext-match-propertized-text 'gemtext-pre-fence-begin last))

(defun gemtext-match-pre-fence-end (last)
  "Match preformatted text block closing fence from point to LAST.
Use data stored in \\='gemtext-pre-fence-end text property during syntax
propertization."
  (gemtext-match-propertized-text 'gemtext-pre-fence-end last))

(defun gemtext-match-pre-text (last)
  "Match preformatted text from point to LAST.
Use data stored in \\='gemtext-pre-text text property during syntax
propertization."
  (gemtext-match-propertized-text 'gemtext-pre-text last))


;;; Faces

(defgroup gemtext-faces nil
  "Faces used in Gemtext Mode."
  :group 'gemtext
  :group 'faces)

(defface gemtext-face-markup
  '((t :inherit shadow))
  "Face for Gemtext markup elements.
Should be displayed with this face: >, =>, ```, #, ##, ###."
  :group 'gemtext-faces)

(defface gemtext-face-heading
  '((t :inherit font-lock-function-name-face :weight bold))
  "Face for Gemtext headings."
  :group 'gemtext-faces)

(defface gemtext-face-blockquote-quote
  '((t :inherit font-lock-doc-face))
  "Face for Gemtext blockquotes quotes."
  :group 'gemtext-faces)

(defface gemtext-face-link-url
  '((t :inherit link))
  "Face for Gemtext links URLs."
  :group 'gemtext-faces)

(defface gemtext-face-link-label
  '((t :inherit italic))
  "Face for Gemtext links labels."
  :group 'gemtext-faces)

(defface gemtext-face-highlight-link
  '((t :inherit highlight))
  "Face for Gemtext highlighted links."
  :group 'gemtext-faces)

(defface gemtext-face-pre-alt
  '((t :inherit (italic)))
  "Face for Gemtext preformatted text blocks alternative text."
  :group 'gemtext-faces)

(defface gemtext-face-pre-text
  '((t :inherit (fixed-pitch font-lock-string-face)))
  "Face for Gemtext preformatted text blocks content."
  :group 'gemtext-faces)


;;; Fontification

(defvar gemtext-mode-font-lock-keywords
  `((gemtext-fontify-headings)
    (gemtext-fontify-ulist-items)
    (gemtext-fontify-blockquotes)
    (gemtext-fontify-links)
    (gemtext-fontify-pre-fence-begin)
    (gemtext-fontify-pre-fence-end)
    (gemtext-fontify-pre-text))
  "Syntax highlighting for Gemtext files.")

(defun gemtext-fontify-headings (last)
  "Apply font-lock properties to headings from point to LAST.
Return t if a heading has been fontified, nil otherwise."
  (when (gemtext-match-headings last)
    ;; Face for "#"
    (add-text-properties (match-beginning 1) (match-end 1)
                         `(face gemtext-face-markup))
    ;; Face for the heading content
    (font-lock-append-text-property (match-beginning 2) (match-end 2)
                                    'face 'gemtext-face-heading)
    t))

(defun gemtext-fontify-ulist-items (last)
  "Apply font-lock properties to unordered list items from point to LAST.
Return t if an item has been fontified, nil otherwise."
  (when (gemtext-match-ulist-items last)
    ;; Face for "*"
    (add-text-properties (match-beginning 1) (match-end 1)
                         `(face gemtext-face-markup))
    t))

(defun gemtext-fontify-blockquotes (last)
  "Apply font-lock properties to blockquotes from point to LAST.
Return t if a blockquote has been fontified, nil otherwise."
  (when (gemtext-match-blockquotes last)
    ;; Face for ">"
    (add-text-properties (match-beginning 1) (match-end 1)
                         `(face gemtext-face-markup))
    ;; Face for the quoted content
    (font-lock-append-text-property (match-beginning 2) (match-end 2)
                                    'face 'gemtext-face-blockquote-quote)
    t))

(defun gemtext-fontify-links (last)
  "Apply font-lock properties to links from point to LAST.
Return t if a link has been fontified, nil otherwise."
  (when (gemtext-match-links last)
    ;; Face when mouse is on the line
    (put-text-property (match-beginning 0) (match-end 0)
                       'mouse-face 'gemtext-face-highlight-link)
    (put-text-property (match-beginning 0) (match-end 0)
                       'keymap gemtext-mode-mouse-map)
    (put-text-property (match-beginning 0) (match-end 0)
                       'help-echo "mouse-2: browse URL")
    ;; Face for "=>"
    (font-lock-append-text-property (match-beginning 1) (match-end 1)
                                    'face 'gemtext-face-markup)
    ;; Face for the URL
    (font-lock-append-text-property (match-beginning 2) (match-end 2)
                                    'face 'gemtext-face-link-url)
    ;; Face for the label
    (font-lock-append-text-property (match-beginning 3) (match-end 3)
                                    'face 'gemtext-face-link-label)
    t))

(defun gemtext-fontify-pre-fence-begin (last)
  "Apply font-lock properties to opening fence of pre blocks from point to LAST.
Return t if a fence has been fontified, nil otherwise."
  (when (gemtext-match-pre-fence-begin last)
    ;; Face for "```"
    (add-text-properties (match-beginning 1) (match-end 1)
                         `(face gemtext-face-markup))
    ;; Face for the alt label
    (font-lock-append-text-property (match-beginning 2) (match-end 2)
                                    'face 'gemtext-face-pre-alt)
    t))

(defun gemtext-fontify-pre-fence-end (last)
  "Apply font-lock properties to closing fence of pre blocks from point to LAST.
Return t if a fence has been fontified, nil otherwise."
  (when (gemtext-match-pre-fence-end last)
    ;; Face for "```"
    (add-text-properties (match-beginning 1) (match-end 1)
                         `(face gemtext-face-markup))
    t))

(defun gemtext-fontify-pre-text (last)
  "Apply font-lock properties to preformatted text from point to LAST.
Return t if a text has been fontified, nil otherwise."
  (when (gemtext-match-pre-text last)
    (add-text-properties (match-beginning 0) (match-end 0)
                         `(face gemtext-face-pre-text))
    t))

(defun gemtext-font-lock-extend-region-function (start end _)
  "Used in `jit-lock-after-change-extend-region-functions'.
Delegates to `gemtext-syntax-propertize-extend-region'.
START and END are the previous region to refontify."
  (let ((res (gemtext-syntax-propertize-extend-region start end)))
    (when res
      ;; syntax-propertize-function is not called when character at
      ;; (point-max) is deleted, but font-lock-extend-region-functions
      ;; are called.  Force a syntax property update in that case.
      (when (= end (point-max))
        ;; This function is called in a buffer modification hook.
        ;; `gemtext-syntax-propertize' doesn't save the match data,
        ;; so we have to do it here.
        (save-match-data
          (gemtext-syntax-propertize (car res) (cdr res))))
      (setq jit-lock-start (car res)
            jit-lock-end (cdr res)))))


;;; Unordered lists

(defun gemtext-insert-ulist-item ()
  "Insert a new unordered list item on a new line after the current position."
  (interactive)
  (when (gemtext-pre-block-at-pos-p (point))
    (gemtext-goto-next-pre-block-end)
    (insert "\n"))
  (unless (gemtext-empty-line-p)
    (end-of-line)
    (insert "\n"))
  (beginning-of-line)
  (insert "* ")
  (gemtext-syntax-propertize-ulists (line-beginning-position) (line-end-position)))

(defun gemtext-empty-line-p ()
  "Return t current line is empty or made of spaces, nil otherwise."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "[[:blank:]]*$")))


;;; Preformatted text blocks: editing

(defun gemtext-pre-block-at-pos-p (pos)
  "Return t if POS is in a preformatted block, nil otherwise."
  (let* ((bol (save-excursion
                (goto-char pos)
                (line-beginning-position)))
         (fence-begin-prop (get-text-property bol 'gemtext-pre-fence-begin))
         (text-prop (get-text-property bol 'gemtext-pre-text))
         (fence-end-prop (get-text-property bol 'gemtext-pre-fence-end)))
    ;; TODO Should be replaced by a (if (...) t).
    ;; Refactor of `gemtext-narrow-to-pre-block' is required, because it uses
    ;; the return value of this function.
    (or fence-begin-prop
        text-prop
        fence-end-prop)))

(defun gemtext-insert-pre-block ()
  "Insert a new preformatted text block on a new line after the current position."
  (interactive)
  (let* ((alt-text (read-string "Alternative text (optional: leave blank): ")))
    (when (gemtext-pre-block-at-pos-p (point))
      (gemtext-goto-next-pre-block-end)
      (insert "\n"))
    (unless (gemtext-empty-line-p)
      (end-of-line)
      (insert "\n"))
    (beginning-of-line)
    (let* ((block-end-position (save-excursion
                                 (insert "```")
                                 (if alt-text
                                     (progn (insert " ")
                                            (insert alt-text)))
                                 (insert "\n\n```")
                                 (point))))
      (gemtext-syntax-propertize-pre-blocks (line-beginning-position)
                                            block-end-position))
    (forward-line)))

(defun gemtext-goto-next-pre-block-end ()
  "Move the cursor after the closing fence of the next pre block.
Do not move the cursor if there is no such block."
  (text-property-search-forward 'gemtext-pre-fence-end))

;;; Preformatted text blocks: narrowing

(defun gemtext-narrow-to-pre-block ()
  "Edit the preformatted text as if it was in it's own file.
To use, place the cursor is inside a preformatted block.  Then
call this command.  It will narrow the region to the body of the
current preformatted block.  If the point is not inside a
preformatted block, then the function will give a message
indicating that and then exit.  Upon narrowing the buffer it will
attempt to change the major mode intelligently based on the text
on the line following the three backticks, from which it will
attempt to identify an extension which it will compare to
`auto-mode-alist'.  To exit, call `gemtext-widen-region'."
  (interactive)
  (if (get-text-property (line-beginning-position) 'gemtext-pre-fence-begin)
      (next-line))
  (if-let* ((x (point))
            (be (gemtext-pre-block-at-pos-p x)))
      (let* ((header-line (gemtext-extract-header be))
             (header-data (gemtext-header-data header-line)))
        (if-let ((m (gemtext-get-major-mode header-data))
                 (b (gemtext-get-buffer-name header-data)))
            (progn
              (let ((beg (car be))
                    (end (cadr be)))
                (narrow-to-region beg end)
                (funcall m)
                (local-set-key (kbd "C-c C-c") #'gemtext-widen-region)))
          (user-error "Malformed header!")))
    (user-error "Not inside a pre-block!")))

(defun gemtext-extract-header (block-region)
  "Extract the header from the BLOCK-REGION."
  (save-excursion
    (let ((start (car block-region))
          (end   (cadr block-region)))
      (goto-char start)
      (previous-line 1)
      (beginning-of-line)
      (search-forward "```")
      (buffer-substring-no-properties (point) (line-end-position)))))

(defun gemtext-get-major-mode (header)
  "Extract the major mode from the buffer specification string in HEADER.
Defaults to fundamental mode when HEADER is nil."
  (if header
      (gemtext-expand-major-mode (car header))
    #'fundamental-mode))

(defun gemtext-header-data (header)
  "Test if the HEADER is correctly formatted."
  (if-let* ((sep (string-match "|" header))
            (mode (string-trim (substring header 0 sep)))
            (len  (length header))
            (name (string-trim (substring header (+ sep 1) len))))
      (cons mode name)
    nil))

(defun gemtext-expand-major-mode (string)
  "Expand the major mode STRING to match its corresponding major mode function.
This tries to find the mode two ways: first it looks for a match in `auto-mode-alist'.  If it finds a match, it uses that.  Otherwise, it inspects the list of major modes if there is a match, it returns that function.  Otherwise, it returns `fundamental-mode'."
  (if-let ((match (assoc (concat "." string) auto-mode-alist #'string-match-p)))
      (cdr match)
    (let ((modes (mapcar #'symbol-name (gemtext-list-major-modes))))
      (if (member string modes)
          (intern string)
        #'fundamental-mode))))

(defun gemtext-list-major-modes ()
  "List all currently defined major modes."
  (let (modes)
    (mapatoms
     (lambda (sym)
       (when (and (fboundp sym)
                  (string-match "-mode$" (symbol-name sym)))
         (push sym modes))))
    (nreverse modes)))

(defun gemtext-get-buffer-name (header)
  "Extract the buffer name from the buffer specification string in HEADER."
  (if header
      (gemtext-make-name-unique (cdr header))
    (concat "narrowed pre block-" (gemtext-random-alnum 5))))

(defun gemtext-make-name-unique (title)
  "Generate a unique name for the buffer based on the TITLE given in the pre-block header."
  (generate-new-buffer-name title))

(defun gemtext-random-alnum (size)
  "Generate a random string of given SIZE with only lowercase letter and numbers."
  (if (< size 1)
      ""
    (let* ((alnum "abcdefghijklmnopqrstuvwxyz0123456789")
           (i (% (abs (random)) (length alnum)))
           (random-char (substring alnum i (1+ i))))
      (concat random-char (gemtext-random-alnum (1- size))))))

(defun gemtext-widen-region ()
  "Widen the region and restore `gemtext-mode'."
  (interactive)
  (when (buffer-narrowed-p)
    (local-unset-key (kbd "C-c C-c"))
    (widen)
    (gemtext-mode)))


;;; Folding

(defun gemtext-outline-level ()
  "Return the depth to which a statement is nested in the outline."
  (if (and (match-beginning 0)
           (gemtext-pre-text-at-pos (match-beginning 0)))
      4 ;; 4 is the lowest level possible, because there is 3 heading levels
    (- (match-end 1) (match-beginning 1))))

(defun gemtext-cycle ()
  "Visibility cycling for Gemtext mode."
  (interactive)
  (if (gemtext-on-heading-p)
      (gemtext-heading-cycle)
    (indent-for-tab-command)))

(defun gemtext-on-heading-p ()
  "Return non-nil if point is on a heading line."
  (get-text-property (line-beginning-position) 'gemtext-heading))

(defun gemtext-heading-cycle ()
  "Cycle for headings."
  (let ((step (outline-cycle)))
    (when (or (string= step "Hide all")
              (string= step "Only headings"))
      (gemtext-outline-fix-visibility))))

(defun gemtext-outline-fix-visibility ()
  "Hide any false positive headings that should not be shown.
There might be lines starting with `#` in preformatted text blocks
that might match `outline-regexp'."
  (save-excursion
    (goto-char (point-min))
    ;; Hide any false positives in preformatted text blocks
    (unless (outline-on-heading-p)
      (outline-next-visible-heading 1))
    (while (not (eobp))
      (when (gemtext-pre-text-at-pos (point))
        (outline-flag-region (1- (line-beginning-position)) (line-end-position) t))
      (outline-next-visible-heading 1))))


;;; URLs

(defun gemtext-follow-link-at-point (&optional event)
  "Follow the link at point or EVENT."
  (interactive (list last-command-event))
  (if event
      (posn-set-point (event-start event)))
  (gemtext-browse-url (gemtext-link-url)))

(defun gemtext-link-url ()
  "Return the URL part of the link at point."
  (if (gemtext-on-link-p)
      (let ((link-content (buffer-substring (line-beginning-position) (line-end-position))))
        (string-match gemtext-regexp-link link-content)
        (message (match-string 2 link-content)))
    (user-error "Point is not at a link")))

(defun gemtext-browse-url (url)
  "Open URL."
  (let* ((struct (url-generic-parse-url url))
         (full (url-fullness struct)))
    (if full
        (browse-url url)
      (find-file url))))

(defun gemtext-on-link-p ()
  "Return non-nil if point is on a link."
  (if (get-text-property (point) 'gemtext-link)
      t))


;;; Keymap

(defvar gemtext-mode-map
  (let ((map (make-keymap)))
    ;; Folding
    (define-key map (kbd "TAB") 'gemtext-cycle)
    ;; Lists editing
    (define-key map (kbd "M-RET") 'gemtext-insert-ulist-item)
    ;; Preformatted text blocks editing
    (define-key map (kbd "C-c C-p") 'gemtext-insert-pre-block)
    (define-key map (kbd "C-c C-c") #'gemtext-narrow-to-pre-block)
    ;; ---
    map)
  "Keymap for `gemtext-mode'.")

(defvar gemtext-mode-mouse-map
  (let ((map (make-sparse-keymap)))
    (define-key map [follow-link] 'mouse-face)
    (define-key map [mouse-2] #'gemtext-follow-link-at-point)
    map)
  "Keymap for following links with mouse.")


;;; Yank Media

(defun gemtext-yank-media-handler (mimetype data)
  "Save DATA of mime-type MIMETYPE and insert a Gemtext link at point.
Meant to be used as a media handler."
  (let* ((assets-root (concat default-directory "assets/"))
         (asset-file (read-file-name (format "Save %s asset to file: " mimetype) assets-root))
         (hint (read-string "Description: " nil)))
    (when (and (not (file-directory-p assets-root))
               (yes-or-no-p "An asset directory does not yet exist under this folder.  Create it?"))
      (make-directory assets-root))
    (when (file-directory-p asset-file)
      (user-error "%s is a directory"))
    (when (and (file-exists-p asset-file)
               (not (yes-or-no-p (format "%s already exists.  Overwrite?" asset-file))))
      (user-error "Overwrite aborted!"))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert data)
      (write-region (point-min) (point-max) asset-file))
    (unless (gemtext-empty-line-p)
      (end-of-line)
      (insert "\n"))
    (insert (format "=> %s %s\n" (file-relative-name asset-file) hint))))


;;; Mode definition

;;;###autoload
(define-derived-mode gemtext-mode text-mode "Gemtext"
  "Major mode for Gemtext-formatted text."
  ;; Syntax analysis
  (add-hook 'syntax-propertize-extend-region-functions
            #'gemtext-syntax-propertize-extend-region nil t)
  (add-hook 'jit-lock-after-change-extend-region-functions
            #'gemtext-font-lock-extend-region-function t t)
  (setq-local syntax-propertize-function #'gemtext-syntax-propertize)
  (syntax-propertize (point-max)) ;; Propertize before hooks run, etc.

  ;; Font lock
  (setq font-lock-defaults '(;; Keywords
                             gemtext-mode-font-lock-keywords
                             ;; Keywords only
                             nil
                             ;; Case-fold
                             nil
                             ;; Syntax-alist
                             nil
                             ;; Rest
                             (font-lock-multiline . t)
                             (font-lock-extra-managed-props . (help-echo mouse-face keymap))))

  ;; Outline mode
  (outline-minor-mode)
  (setq-local outline-regexp gemtext-regexp-heading
              outline-level #'gemtext-outline-level)

  ;; Yank media handler
  (when (fboundp 'yank-media-handler)
    (yank-media-handler ".*/.*" #'gemtext-yank-media-handler))

  ;; Hook
  (run-hooks 'gemtext-mode-hook))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.gmi\\'" . gemtext-mode))

(provide 'gemtext-mode)

;; Local Variables:
;; coding: utf-8
;; End:

;;; gemtext-mode.el ends here
