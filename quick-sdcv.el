;;; quick-sdcv.el --- Offline dictionary using 'sdcv' (StartDict cli dictionary) -*- lexical-binding: t -*-

;; Copyright (C) 2024-2026 James Cherti | https://www.jamescherti.com/contact/
;; Copyright (C) 2008-2020 Andy Stewart

;; Filename: quick-sdcv.el
;; Description: Interface for sdcv (StartDict console version).
;; Package-Requires: ((emacs "25.1"))
;; Maintainer: James Cherti
;; Original Author: Andy Stewart
;; Version: 1.0.4
;; URL: https://github.com/jamescherti/quick-sdcv.el
;; Keywords: docs, startdict, sdcv

;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;; The quick-sdcv package serves as a lightweight Emacs interface for the
;; sdcv command-line interface, which is the console version of the StarDict
;; dictionary application.
;;
;; This package enables Emacs to function as an offline dictionary.
;;
;; This integration allows users to access and utilize sdcv dictionary
;; functionalities directly within the Emacs environment, leveraging the
;; capabilities of sdcv to look up words and translations from various
;; dictionary files formatted for StarDict.
;;
;; Here are the main interactive functions:
;;
;; Below are the commands you can use:
;; - `quick-sdcv-search-at-point': Searches the word around the cursor and
;;   displays the result in a buffer.
;; - `quick-sdcv-search-input': Searches the input word and displays the result
;;   in a buffer.
;;
;; Installation from MELPA:
;; ------------------------
;; (use-package quick-sdcv
;;   :custom
;;   (quick-sdcv-dictionary-prefix-symbol "►")
;;   (quick-sdcv-ellipsis " ▼ "))
;;
;; Usage:
;; ------
;; To retrieve the word under the cursor and display its definition in a buffer:
;;   (quick-sdcv-search-at-point)
;;
;; To prompt the user for a word and display its definition in a buffer:
;;   (quick-sdcv-search-input)
;;
;; Links:
;; ------
;; More information about quick-sdcv (Usage, Frequently Asked Questions, etc.):
;; https://github.com/jamescherti/quick-sdcv.el

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'outline)
(require 'subword)

;;; Customize

(defgroup quick-sdcv nil
  "Interface for sdcv (StartDict console version)."
  :group 'edit)

(defcustom quick-sdcv-unique-buffers nil
  "If non-nil, create a unique buffer for each word lookup.
For instance, if the user searches for the word computer:
- When non-nil, the buffer name will be *sdcv:computer*
- When nil, the buffer name will be *sdcv*
This can be customized with: `quick-sdcv-buffer-name-prefix',
`quick-sdcv-buffer-name-separator', and `quick-sdcv-buffer-name-suffix'"
  :type 'boolean
  :group 'quick-sdcv)

(defcustom quick-sdcv-buffer-name-prefix "*sdcv"
  "The prefix of the sdcv buffer name."
  :type 'string
  :group 'quick-sdcv)

(defcustom quick-sdcv-buffer-name-separator ":"
  "The separator of the sdcv buffer name."
  :type 'string
  :group 'quick-sdcv)

(defcustom quick-sdcv-buffer-name-suffix "*"
  "The suffix of the sdcv buffer name."
  :type 'string
  :group 'quick-sdcv)

(defcustom quick-sdcv-program "sdcv"
  "Path to sdcv."
  :type 'file
  :group 'quick-sdcv)

(defcustom quick-sdcv-dictionary-complete-list nil
  "A list of dictionaries used for translation in quick-sdcv."
  :type '(repeat string)
  :group 'quick-sdcv)

(defcustom quick-sdcv-dictionary-data-dir nil
  "The sdcv data directory where dictionaries are."
  :type '(choice (const :tag "Default" nil) directory)
  :group 'quick-sdcv)

(defcustom quick-sdcv-only-data-dir nil
  "Use only the dictionaries in `quick-sdcv-dictionary-data-dir'.
It prevents sdcv from searching in user and system directories."
  :type 'boolean
  :group 'quick-sdcv)

(defcustom quick-sdcv-exact-search nil
  "Do not fuzzy-search for similar words, only return exact matches."
  :type 'boolean
  :group 'quick-sdcv)

(defcustom quick-sdcv-dictionary-prefix-symbol "►"
  "Symbol character used in sdcv dictionaries that replaces ('-->') visually."
  :group 'quick-sdcv
  :type '(choice (string :tag "Symbol character" :size 1)
                 (const :tag "No symbol" nil)))

(defcustom quick-sdcv-verbose nil
  "If non-nil, `quick-sdcv' will show verbose messages."
  :type 'boolean
  :group 'quick-sdcv)

(defcustom quick-sdcv-hist-size nil
  "Size of the history for SDCV.
If non-nil, this value will be used to set the `SDCV_HISTSIZE` environment
variable."
  :type 'integer
  :group 'quick-sdcv)

(defcustom quick-sdcv-ellipsis nil
  "String used as the ellipsis character in `quick-sdcv-mode'.
When set to nil, the default behavior is not to modify the ellipsis.
To apply the change, you need to execute `quick-sdcv-minor-mode' in the buffer."
  :type '(choice string (const nil))
  :group 'quick-sdcv)

(defcustom quick-sdcv-ignore-pager t
  "Ignore the SDCV_PAGER environment variable when running sdcv.
If set to non-nil, the value of SDCV_PAGER is disregarded and not applied."
  :type 'boolean
  :group 'quick-sdcv)

(defcustom quick-sdcv-fold-on-search nil
  "If non-nil, close all dictionary folds when a search is performed."
  :type 'boolean
  :group 'quick-sdcv)

(defcustom quick-sdcv-window-select t
  "Non-nil means always select sdcv window for viewing.
If nil select sdcv window only if there is no other window on its frame."

  :type 'boolean
  :group 'quick-sdcv
  :package-version '(quick-sdcv . '"1.0.5"))

;;; Variables

(defvar quick-sdcv-current-translate-object nil
  "The search object.")

(defvar quick-sdcv-fail-notify-string nil
  "Search with additional dictionaries if no definition is available.")

(defvar quick-sdcv--symbols-keywords
  `(("^-->.*$"
     (0 (let* ((heading-end (+ (match-beginning 0) 3))
               (symbol
                (if (and quick-sdcv-dictionary-prefix-symbol
                         (> (length quick-sdcv-dictionary-prefix-symbol) 0))
                    (substring quick-sdcv-dictionary-prefix-symbol 0 1)
                  nil)))
          (when (and symbol (not (string= symbol "")))
            (compose-region (- heading-end 3) (- heading-end 1) symbol)
            (compose-region heading-end (- heading-end 1) " ")
            (put-text-property (- heading-end 3) heading-end
                               'face 'font-lock-type-face))
          nil)))))

(defvar quick-sdcv-mode-font-lock-keywords
  '(("^-->\\(.*\\)" . (1 font-lock-type-face)) ; Dictionary name
    ("^=>\\(.*\\)" . (1 font-lock-function-name-face)) ; word
    ("\\(^[0-9] \\|[0-9]+:\\|[0-9]+\\.\\)" . (1 font-lock-constant-face)) ; Serial number
    ("^<<\\([^>]*\\)>>$" . (1 font-lock-comment-face)) ; Type name
    ("^/\\([^>]*\\)/$" . (1 font-lock-string-face)) ; Phonetic symbol
    ("^\\[\\([^]]*\\)\\]$" . (1 font-lock-string-face)))
  "Expressions to highlight in `quick-sdcv-mode'.")

;; Optionally, you might want to define the mode itself here.
(defvar quick-sdcv-mode-map
  (let ((map (make-sparse-keymap)))
    map))

(defun quick-sdcv--outline-level ()
  "Return the depth to which a statement is nested in the outline.."
  1)

(define-derived-mode quick-sdcv-mode nil "sdcv"
  "Major mode to look up word through sdcv.
\\{quick-sdcv-mode-map}"
  (setq font-lock-defaults '(quick-sdcv-mode-font-lock-keywords t))
  (setq buffer-read-only t)

  (set (make-local-variable 'outline-regexp) "^-->")
  (set (make-local-variable 'outline-level)
       #'quick-sdcv--outline-level)

  (when (boundp 'evil-lookup-func)
    (setq-local evil-lookup-func 'quick-sdcv-search-at-point))
  (quick-sdcv--toggle-symbol-fontification t)
  (outline-minor-mode 1)
  (quick-sdcv--update-ellipsis))

;;; Utility Functions

(defun quick-sdcv--update-ellipsis ()
  "Update the buffer's outline ellipsis."
  (when quick-sdcv-ellipsis
    (let* ((display-table (or buffer-display-table (make-display-table)))
           (face-offset (* (face-id 'shadow) (ash 1 22)))
           (value (vconcat (mapcar (lambda (c) (+ face-offset c))
                                   ;; Trim trailing whitespace after the
                                   ;; ellipsis, as it can be misleading when the
                                   ;; line is not truncated. Wrapping may
                                   ;; display only the space after the ellipsis
                                   ;; on the next line, creating the illusion of
                                   ;; a new line. Deleting that apparent "new
                                   ;; line" may delete the entire logical line
                                   ;; containing the ellipsis.
                                   (string-trim-right quick-sdcv-ellipsis)))))
      (set-display-table-slot display-table 'selective-display value)
      (setq buffer-display-table display-table))))

(defun quick-sdcv--get-buffer-name (&optional word)
  "Return the buffer name for WORD."
  (concat quick-sdcv-buffer-name-prefix
          (when (and quick-sdcv-unique-buffers
                     word)
            (concat quick-sdcv-buffer-name-separator
                    word))
          quick-sdcv-buffer-name-suffix))

(defun quick-sdcv--toggle-symbol-fontification (enabled)
  "Toggle fontification of '-->' in the quick-sdcv buffer.
When ENABLED is non-nil, adds font-lock keywords to replace '-->' with a symbol.
When ENABLED is nil: Deconstructs any symbol regions marked by '-->'."
  (if enabled
      (when (and quick-sdcv-dictionary-prefix-symbol
                 (> (length quick-sdcv-dictionary-prefix-symbol) 0))
        (font-lock-add-keywords nil quick-sdcv--symbols-keywords))
    (save-excursion
      (goto-char (point-min))
      (font-lock-remove-keywords nil quick-sdcv--symbols-keywords)
      (while (re-search-forward "^-->" nil t)
        (decompose-region (match-beginning 0) (match-end 0)))))

  ;; Fontify the buffer
  (when (bound-and-true-p font-lock-mode)
    (if (fboundp 'font-lock-flush)
        (font-lock-flush)
      (with-no-warnings
        (font-lock-fontify-buffer)))))

(defun quick-sdcv--call-process (&rest arguments)
  "Call `quick-sdcv-program' with ARGUMENTS. Result is parsed as json."
  (unless (executable-find quick-sdcv-program)
    (error (concat "The program '%s' was not found. Please ensure it is "
                   "installed and that the path is correctly set "
                   "in `quick-sdcv-program`.")
           quick-sdcv-program))
  (with-temp-buffer
    (save-excursion
      (let* ((process-environment
              (if quick-sdcv-ignore-pager
                  (cl-remove-if
                   (lambda (var)
                     (or (string-match "^SDCV_PAGER=" var)))
                   process-environment)
                process-environment)))
        (when quick-sdcv-hist-size
          (setenv "SDCV_HISTSIZE" (number-to-string quick-sdcv-hist-size)))
        (let ((exit-code (apply #'call-process quick-sdcv-program nil t nil
                                (append (list "--non-interactive"
                                              "--json-output"
                                              "--utf8-output")
                                        (when quick-sdcv-exact-search
                                          (list "--exact-search"))
                                        (when quick-sdcv-only-data-dir
                                          (list "--only-data-dir"))
                                        (when quick-sdcv-dictionary-data-dir
                                          (list "--data-dir"
                                                (expand-file-name
                                                 quick-sdcv-dictionary-data-dir)))
                                        arguments))))
          (if (not (zerop exit-code))
              (error "Failed to call %s: exit code %d" quick-sdcv-program
                     exit-code)))))
    (ignore-errors (json-read))))

(defun quick-sdcv--search-with-dictionary (word dictionary-list)
  "Search some WORD with DICTIONARY-LIST.
Argument DICTIONARY-LIST the word that needs to be transformed."
  (let* ((word (or word (quick-sdcv--get-region-or-word)))
         (translate-result (quick-sdcv--translate-result word dictionary-list)))
    (when (and (string= quick-sdcv-fail-notify-string translate-result)
               (setq word (thing-at-point 'word t)))
      (setq translate-result (quick-sdcv--translate-result word dictionary-list)))
    translate-result))

(defun quick-sdcv--search-detail (&optional word)
  "Search WORD in `quick-sdcv-dictionary-complete-list'.
The result will be displayed in a buffer."
  (when word
    (let* ((buffer-name (quick-sdcv--get-buffer-name word))
           (buffer (get-buffer buffer-name))
           (refresh (or (not buffer)
                        ;; When the words share the same buffer, always refresh
                        (not quick-sdcv-unique-buffers)))
           (inhibit-read-only t))
      (unless buffer
        (setq buffer (quick-sdcv--get-buffer word)))

      (let ((text (quick-sdcv--search-with-dictionary
                   word
                   quick-sdcv-dictionary-complete-list)))
        (unless text
          (error "The command %s produced no output" quick-sdcv-program))

        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (when refresh
              (when quick-sdcv-verbose
                (message "[SDCV] Searching..."))
              (erase-buffer)
              (set-buffer-file-coding-system 'utf-8)  ;; Force UTF-8
              (setq quick-sdcv-current-translate-object word)
              (insert text)

              (goto-char (point-min))

              ;; NEW: Collapse all folds if the user setting is enabled
              (when quick-sdcv-fold-on-search
                (unless (bound-and-true-p outline-minor-mode)
                  (outline-minor-mode 1))
                (outline-hide-body))

              (when quick-sdcv-verbose
                (message "[SDCV] Finished searching `%s'."
                         quick-sdcv-current-translate-object)))
            (if quick-sdcv-window-select
                (pop-to-buffer buffer)
              (display-buffer buffer))))))))

(defun quick-sdcv--translate-result (word dictionary-list)
  "Search for WORD in DICTIONARY-LIST. Return filtered string of results."
  (let* ((args (cons word (mapcan (lambda (d) (list "-u" d)) dictionary-list)))
         (result (mapconcat
                  (lambda (result)
                    (let-alist result
                      (format "-->%s\n=>%s\n%s\n\n" .dict .word .definition)))
                  (apply #'quick-sdcv--call-process args)
                  "")))
    (if (string-empty-p result)
        quick-sdcv-fail-notify-string
      result)))

(defun quick-sdcv--get-buffer (&optional word)
  "Get the sdcv buffer of WORD. Create one if there's none."
  (let* ((buffer-name (quick-sdcv--get-buffer-name word))
         (buffer (get-buffer buffer-name)))
    (unless buffer
      (setq buffer (get-buffer-create buffer-name)))
    (when buffer
      (with-current-buffer buffer
        (unless (derived-mode-p 'quick-sdcv-mode)
          (quick-sdcv-mode)))
      buffer)))

(defun quick-sdcv--get-region-or-word ()
  "Return the region or the word under the cursor."
  (if (use-region-p)
      (buffer-substring-no-properties (region-beginning) (region-end))
    (thing-at-point 'word t)))

;;; Interactive Functions

;;;###autoload
(defun quick-sdcv-search-at-point ()
  "Retrieve the word under the cursor and display its definition in a buffer."
  (interactive)
  (quick-sdcv--search-detail (quick-sdcv--get-region-or-word)))

;;;###autoload
(defun quick-sdcv-search-input (&optional word)
  "Prompt the user for a word and display its definition in a buffer.
If WORD is not provided, the function prompts the user to enter a word."
  (interactive)
  (let ((word (or word
                  (let* ((word (quick-sdcv--get-region-or-word))
                         (default (if word (format " (default: %s)" word) "")))
                    (read-string (format "Word%s: " default) nil nil word)))))
    (if (and word
             (not (string= word "")))
        (quick-sdcv--search-detail word)
      (user-error "No word specified. Please provide a word to search for"))))

;;; Provide

(provide 'quick-sdcv)
;;; quick-sdcv.el ends here
