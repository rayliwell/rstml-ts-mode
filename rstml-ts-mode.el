;;; rstml-ts-mode.el --- Rust + html support for tree-sitter.  -*- lexical-binding: t; -*-

;; Copyright (C) 2022-2024 Free Software Foundation, Inc.
;; Copyright (C) 2024 Ryan Halliwell

;; Author: Ryan Halliwell <git@rayliwell.com>
;; Maintainer: Ryan Halliwell <git@rayliwell.com>
;; Created: 22 Mar 2024
;; Package-Requires: ((emacs "29.1"))
;; Keywords: rstml html rust languages tree-sitter
;; URL: https://github.com/rayliwell/tree-sitter-rstml

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A major-mode for editing rstml (rust + html) using tree-sitter.

;;; Code:

(require 'treesit)
(eval-when-compile (require 'rx))
(require 'c-ts-common) ; For comment indent and filling.

(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-induce-sparse-tree "treesit.c")
(declare-function treesit-node-child "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")
(declare-function treesit-node-start "treesit.c")
(declare-function treesit-node-end "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-parent "treesit.c")
(declare-function treesit-query-compile "treesit.c")

(defcustom rstml-ts-mode-indent-offset 4
  "Number of spaces for each indentation step in `rstml-ts-mode'."
  :version "29.1"
  :type 'integer
  :safe 'integerp
  :group 'rstml)

(defvar rstml-ts-mode--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?+   "."      table)
    (modify-syntax-entry ?-   "."      table)
    (modify-syntax-entry ?=   "."      table)
    (modify-syntax-entry ?%   "."      table)
    (modify-syntax-entry ?&   "."      table)
    (modify-syntax-entry ?|   "."      table)
    (modify-syntax-entry ?^   "."      table)
    (modify-syntax-entry ?!   "."      table)
    (modify-syntax-entry ?@   "."      table)
    (modify-syntax-entry ?~   "."      table)
    (modify-syntax-entry ?<   "."      table)
    (modify-syntax-entry ?>   "."      table)
    (modify-syntax-entry ?/   ". 124b" table)
    (modify-syntax-entry ?*   ". 23"   table)
    (modify-syntax-entry ?\n  "> b"    table)
    (modify-syntax-entry ?\^m "> b"    table)
    table)
  "Syntax table for `rstml-ts-mode'.")

(defvar rstml-ts-mode--indent-rules
  `((rust_with_rstml
     ((parent-is "source_file") column-0 0)
     ((node-is ")") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is "}") (and parent parent-bol) 0)
     ((and (parent-is "comment") c-ts-common-looking-at-star)
      c-ts-common-comment-start-after-first-star -1)
     ((parent-is "comment") prev-adaptive-prefix 0)
     ((parent-is "arguments") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "await_expression") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "array_expression") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "binary_expression") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "block") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "declaration_list") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "enum_variant_list") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "field_declaration_list") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "field_expression") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "field_initializer_list") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "let_declaration") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "macro_definition") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "parameters") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "struct_pattern") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "token_tree") parent-bol rstml-ts-mode-indent-offset)
     ((parent-is "use_list") parent-bol rstml-ts-mode-indent-offset)))
  "Tree-sitter indent rules for `rstml-ts-mode'.")

(defvar rstml-ts-mode--builtin-macros
  '("concat_bytes" "concat_idents" "const_format_args"
    "format_args_nl" "log_syntax" "trace_macros" "assert" "assert_eq"
    "assert_ne" "cfg" "column" "compile_error" "concat" "dbg"
    "debug_assert" "debug_assert_eq" "debug_assert_ne" "env" "eprint"
    "eprintln" "file" "format" "format_args" "include" "include_bytes"
    "include_str" "is_x86_feature_detected" "line" "matches"
    "module_path" "option_env" "panic" "print" "println" "stringify"
    "thread_local" "todo" "try" "unimplemented" "unreachable" "vec"
    "write" "writeln")
  "Rust built-in macros for tree-sitter font-locking.")

(defvar rstml-ts-mode--keywords
  '("as" "async" "await" "break" "const" "continue" "dyn" "else"
    "enum" "extern" "fn" "for" "if" "impl" "in" "let" "loop" "match"
    "mod" "move" "pub" "ref" "return" "static" "struct" "trait" "type"
    "union" "unsafe" "use" "where" "while" (crate) (self) (super)
    (mutable_specifier))
  "Rust keywords for tree-sitter font-locking.")

(defvar rstml-ts-mode--operators
  '("!"  "!=" "%" "%=" "&" "&=" "&&" "*" "*=" "+" "+=" "," "-" "-="
    "->" "."  ".."  "..=" "..."  "/" "/=" ":" ";" "<<" "<<=" "<" "<="
    "=" "==" "=>" ">" ">=" ">>" ">>=" "@" "^" "^=" "|" "|=" "||" "?")
  "Rust operators for tree-sitter font-locking.")

(defvar rstml-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'rust_with_rstml
   :feature 'attribute
   '((attribute_item) @font-lock-preprocessor-face
     (inner_attribute_item) @font-lock-preprocessor-face)

   :language 'rust_with_rstml
   :feature 'bracket
   '((["(" ")" "[" "]" "{" "}"]) @font-lock-bracket-face)

   :language 'rust_with_rstml
   :feature 'builtin
   `((macro_invocation
      macro: ((identifier) @font-lock-builtin-face
              (:match ,(rx-to-string
                        `(seq bol
                              (or ,@rstml-ts-mode--builtin-macros)
                              eol))
                      @font-lock-builtin-face)))
     ((identifier) @font-lock-type-face
      (:match "\\`\\(?:Err\\|Ok\\|None\\|Some\\)\\'" @font-lock-type-face)))

   :language 'rust_with_rstml
   :feature 'comment
   '(([(block_comment) (line_comment)]) @rstml-ts-mode--comment-docstring)

   :language 'rust_with_rstml
   :feature 'delimiter
   '((["," "." ";" ":" "::"]) @font-lock-delimiter-face)

   :language 'rust_with_rstml
   :feature 'definition
   '((function_item name: (identifier) @font-lock-function-name-face)
     (macro_definition "macro_rules!" @font-lock-constant-face)
     (macro_definition (identifier) @font-lock-preprocessor-face)
     (field_declaration name: (field_identifier) @font-lock-property-name-face)
     (parameter pattern: (_) @rstml-ts-mode--fontify-pattern)
     (closure_parameters (_) @rstml-ts-mode--fontify-pattern)
     (let_declaration pattern: (_) @rstml-ts-mode--fontify-pattern)
     (for_expression pattern: (_) @rstml-ts-mode--fontify-pattern)
     (let_condition pattern: (_) @rstml-ts-mode--fontify-pattern)
     (match_arm pattern: (_) @rstml-ts-mode--fontify-pattern))

   :language 'rust_with_rstml
   :feature 'assignment
   '((assignment_expression left: (_) @rstml-ts-mode--fontify-pattern)
     (compound_assignment_expr left: (_) @rstml-ts-mode--fontify-pattern))

   :language 'rust_with_rstml
   :feature 'function
   '((call_expression
      function:
      [(identifier) @font-lock-function-call-face
       (field_expression
        field: (field_identifier) @font-lock-function-call-face)
       (scoped_identifier
        name: (identifier) @font-lock-function-call-face)])
     (generic_function
      function: [(identifier) @font-lock-function-call-face
                 (field_expression
                  field: (field_identifier) @font-lock-function-call-face)
                 (scoped_identifier
                  name: (identifier) @font-lock-function-call-face)])
     (macro_invocation macro: (identifier) @font-lock-preprocessor-face))

   :language 'rust_with_rstml
   :feature 'keyword
   `([,@rstml-ts-mode--keywords] @font-lock-keyword-face)

   :language 'rust_with_rstml
   :feature 'number
   '([(float_literal) (integer_literal)] @font-lock-number-face)

   :language 'rust_with_rstml
   :feature 'operator
   `([,@rstml-ts-mode--operators] @font-lock-operator-face)

   :language 'rust_with_rstml
   :feature 'string
   '([(char_literal)
      (raw_string_literal)
      (string_literal)] @font-lock-string-face)

   :language 'rust_with_rstml
   :feature 'type
   `((scoped_use_list path: (identifier) @font-lock-constant-face)
     (scoped_use_list path: (scoped_identifier
                             name: (identifier) @font-lock-constant-face))
     ((use_as_clause alias: (identifier) @font-lock-type-face)
      (:match "\\`[A-Z]" @font-lock-type-face))
     ((use_as_clause path: (identifier) @font-lock-type-face)
      (:match "\\`[A-Z]" @font-lock-type-face))
     ((use_list (identifier) @font-lock-type-face)
      (:match "\\`[A-Z]" @font-lock-type-face))
     (use_wildcard [(identifier) @rstml-ts-mode--fontify-scope
                    (scoped_identifier
                     name: (identifier) @rstml-ts-mode--fontify-scope)])
     (enum_variant name: (identifier) @font-lock-type-face)
     (match_arm
      pattern: (match_pattern (_ type: (identifier) @font-lock-type-face)))
     (match_arm
      pattern: (match_pattern
                (_ type: (scoped_identifier
                          path: (identifier) @font-lock-type-face))))
     (mod_item name: (identifier) @font-lock-constant-face)
     (primitive_type) @font-lock-type-face
     (type_identifier) @font-lock-type-face
     ((scoped_identifier name: (identifier) @rstml-ts-mode--fontify-tail))
     ((scoped_identifier path: (identifier) @font-lock-type-face)
      (:match ,(rx bos
                   (or "u8" "u16" "u32" "u64" "u128" "usize"
                       "i8" "i16" "i32" "i64" "i128" "isize"
                       "char" "str")
                   eos)
              @font-lock-type-face))
     ((scoped_identifier path: (identifier) @rstml-ts-mode--fontify-scope))
     ((scoped_type_identifier path: (identifier) @rstml-ts-mode--fontify-scope))
     (type_identifier) @font-lock-type-face)

   :language 'rust_with_rstml
   :feature 'property
   '((field_identifier) @font-lock-property-use-face
     (shorthand_field_initializer (identifier) @font-lock-property-use-face))

   ;; Must be under type, otherwise some imports can be highlighted as constants.
   :language 'rust_with_rstml
   :feature 'constant
   `((boolean_literal) @font-lock-constant-face
     ((identifier) @font-lock-constant-face
      (:match "\\`[A-Z][0-9A-Z_]*\\'" @font-lock-constant-face)))

   :language 'rust_with_rstml
   :feature 'variable
   '((arguments (identifier) @font-lock-variable-use-face)
     (array_expression (identifier) @font-lock-variable-use-face)
     (assignment_expression right: (identifier) @font-lock-variable-use-face)
     (binary_expression left: (identifier) @font-lock-variable-use-face)
     (binary_expression right: (identifier) @font-lock-variable-use-face)
     (block (identifier) @font-lock-variable-use-face)
     (compound_assignment_expr right: (identifier) @font-lock-variable-use-face)
     (field_expression value: (identifier) @font-lock-variable-use-face)
     (field_initializer value: (identifier) @font-lock-variable-use-face)
     (if_expression condition: (identifier) @font-lock-variable-use-face)
     (let_condition value: (identifier) @font-lock-variable-use-face)
     (let_declaration value: (identifier) @font-lock-variable-use-face)
     (match_arm value: (identifier) @font-lock-variable-use-face)
     (match_expression value: (identifier) @font-lock-variable-use-face)
     (reference_expression value: (identifier) @font-lock-variable-use-face)
     (return_expression (identifier) @font-lock-variable-use-face)
     (tuple_expression (identifier) @font-lock-variable-use-face)
     (unary_expression (identifier) @font-lock-variable-use-face)
     (while_expression condition: (identifier) @font-lock-variable-use-face))

   :language 'rust_with_rstml
   :feature 'escape-sequence
   :override t
   '((escape_sequence) @font-lock-escape-face)

   :language 'rust_with_rstml
   :feature 'error
   :override t
   '((ERROR) @font-lock-warning-face))
  "Tree-sitter font-lock settings for `rstml-ts-mode'.")

(defun rstml-ts-mode--comment-docstring (node override start end &rest _args)
  "Use the comment or documentation face appropriately for comments."
  (let* ((beg (treesit-node-start node))
         (face (save-excursion
                 (goto-char beg)
                 (if (looking-at "/\\(?:/\\(?:/[^/]\\|!\\)\\|*\\(?:*[^*/]\\|!\\)\\)" t)
                     'font-lock-doc-face
                   'font-lock-comment-face))))
    (treesit-fontify-with-override beg (treesit-node-end node)
                                   face override start end)))

(defun rstml-ts-mode--fontify-scope (node override start end &optional tail-p)
  (let* ((case-fold-search nil)
         (face
          (cond
           ((string-match-p "^[A-Z]" (treesit-node-text node))
            'font-lock-type-face)
           ((and
             tail-p
             (string-match-p
              "\\`\\(?:use_list\\|call_expression\\|use_as_clause\\|use_declaration\\)\\'"
              (treesit-node-type (treesit-node-parent (treesit-node-parent node)))))
            nil)
           (t 'font-lock-constant-face))))
    (when face
      (treesit-fontify-with-override
       (treesit-node-start node) (treesit-node-end node)
       face
       override start end))))

(defun rstml-ts-mode--fontify-tail (node override start end)
  (rstml-ts-mode--fontify-scope node override start end t))

(defalias 'rstml-ts-mode--fontify-pattern
  (and
   (treesit-available-p)
   `(lambda (node override start end &rest _)
      (let ((captures (treesit-query-capture
                       node
                       ,(treesit-query-compile 'rust '((identifier) @id
                                                       (shorthand_field_identifier) @id)))))
        (pcase-dolist (`(_name . ,id) captures)
          (unless (string-match-p "\\`scoped_\\(?:type_\\)?identifier\\'"
                                  (treesit-node-type
                                   (treesit-node-parent id)))
            (treesit-fontify-with-override
             (treesit-node-start id) (treesit-node-end id)
             'font-lock-variable-name-face override start end)))))))

(defun rstml-ts-mode--defun-name (node)
  "Return the defun name of NODE.
Return nil if there is no name or if NODE is not a defun node."
  (pcase (treesit-node-type node)
    ("enum_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))
    ("function_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))
    ("impl_item"
     (let ((trait-node (treesit-node-child-by-field-name node "trait")))
       (concat
        (treesit-node-text trait-node t)
        (when trait-node " for ")
        (treesit-node-text
         (treesit-node-child-by-field-name node "type") t))))
    ("mod_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))
    ("struct_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))
    ("type_item"
     (treesit-node-text
      (treesit-node-child-by-field-name node "name") t))))

(defun rstml-ts-mode--syntax-propertize (beg end)
  "Apply syntax properties to special characters between BEG and END.

Apply syntax properties to various special characters with
contextual meaning between BEG and END.

The apostrophe \\=' should be treated as string when used for char literals.

< and > are usually punctuation, e.g., as greater/less-than.  But
when used for types, they should be considered pairs.

This function checks for < and > in the changed RANGES and apply
appropriate text property to alter the syntax of template
delimiters < and >'s."
  (goto-char beg)
  (while (search-forward "'" end t)
    (when (string-equal "char_literal"
                        (treesit-node-type
                         (treesit-node-at (match-beginning 0))))
      (put-text-property (match-beginning 0) (match-end 0)
                         'syntax-table (string-to-syntax "\""))))
  (goto-char beg)
  (while (re-search-forward (rx (or "<" ">")) end t)
    (pcase (treesit-node-type
            (treesit-node-parent
             (treesit-node-at (match-beginning 0))))
      ((or "type_arguments" "type_parameters")
       (put-text-property (match-beginning 0)
                          (match-end 0)
                          'syntax-table
                          (pcase (char-before)
                            (?< '(4 . ?>))
                            (?> '(5 . ?<))))))))

;;;###autoload
(define-derived-mode rstml-ts-mode prog-mode "Rust with rstml"
  "Major mode for editing Rust, powered by tree-sitter."
  :group 'rstml
  :syntax-table rstml-ts-mode--syntax-table

  (when (treesit-ready-p 'rust_with_rstml)
    (treesit-parser-create 'rust_with_rstml)

    ;; Syntax.
    (setq-local syntax-propertize-function
                #'rstml-ts-mode--syntax-propertize)

    ;; Comments.
    (c-ts-common-comment-setup)

    ;; Font-lock.
    (setq-local treesit-font-lock-settings rstml-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((comment definition)
                  (keyword string)
                  (assignment attribute builtin constant escape-sequence
                              number type)
                  (bracket delimiter error function operator property variable)))

    ;; Imenu.
    (setq-local treesit-simple-imenu-settings
                `(("Module" "\\`mod_item\\'" nil nil)
                  ("Enum" "\\`enum_item\\'" nil nil)
                  ("Impl" "\\`impl_item\\'" nil nil)
                  ("Type" "\\`type_item\\'" nil nil)
                  ("Struct" "\\`struct_item\\'" nil nil)
                  ("Fn" "\\`function_item\\'" nil nil)))

    ;; Indent.
    (setq-local indent-tabs-mode nil
                treesit-simple-indent-rules rstml-ts-mode--indent-rules)

    ;; Electric
    (setq-local electric-indent-chars
                (append "{}():;,#" electric-indent-chars))

    ;; Navigation.
    (setq-local treesit-defun-type-regexp
                (regexp-opt '("enum_item"
                              "function_item"
                              "impl_item"
                              "struct_item")))
    (setq-local treesit-defun-name-function #'rstml-ts-mode--defun-name)

    (treesit-major-mode-setup)))

(provide 'rstml-ts-mode)
;;; rstml-ts-mode.el ends here
