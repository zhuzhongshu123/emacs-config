;;; lsp-config.el --- Language services and editing integration -*- lexical-binding: t; -*-

(require 'cl-lib)

(defun my-tui-python-server-executable (program)
  "Find PROGRAM without putting the language-server venv on the project PATH."
  (or (executable-find program)
      (let ((file (expand-file-name
                   (concat ".cache/python-tools/bin/" program)
                   user-emacs-directory)))
        (when (file-executable-p file) file))))

(defun my-tui-python-source-roots (root)
  "Find Python package roots directly inside project ROOT.
This covers monorepos such as ByteGraph/graphrag without recursive scanning."
  (cons (directory-file-name (expand-file-name root))
        (cl-loop for dir in (directory-files root t directory-files-no-dot-files-regexp)
                 when (and (file-directory-p dir)
                           (or (file-exists-p (expand-file-name "setup.py" dir))
                               (file-exists-p (expand-file-name "pyproject.toml" dir))))
                 collect (directory-file-name (expand-file-name dir)))))

;; =============================================================================
;; LSP Bridge
;; =============================================================================

(require 'json)
(require 'subr-x)

(defvar my-tui-rust-analyzer-executable-cache 'unset
  "Cached real rust-analyzer executable, bypassing the rustup proxy.")

(defun my-tui-rust-analyzer-executable ()
  "Return a real rust-analyzer binary unaffected by project toolchain overrides."
  (if (not (eq my-tui-rust-analyzer-executable-cache 'unset))
      my-tui-rust-analyzer-executable-cache
    (setq my-tui-rust-analyzer-executable-cache
          (or (when-let* ((rustup (executable-find "rustup"))
                          (path
                           (with-temp-buffer
                             (when (zerop (call-process rustup nil t nil
                                                        "which" "--toolchain" "stable"
                                                        "rust-analyzer"))
                               (string-trim (buffer-string))))))
                (and (file-executable-p path) path))
              (executable-find "rust-analyzer")))))

(defun my-tui-bridge-write-json (name value)
  "Write a generated server configuration NAME containing VALUE."
  (let* ((dir (expand-file-name ".cache/lsp-bridge-servers/" user-emacs-directory))
         (file (expand-file-name (concat name ".json") dir))
         (text (json-encode value)))
    (make-directory dir t)
    (unless (and (file-exists-p file)
                 (equal text (with-temp-buffer
                               (insert-file-contents file) (buffer-string))))
      (with-temp-file file (insert text)))
    file))

(defun my-tui-bridge-python-config (project-path filename &optional multi)
  "Generate project-specific Python configuration; return MULTI routing if asked."
  (when (and (stringp filename) (string-suffix-p ".py" filename))
    (let* ((root (file-name-as-directory
                  (if (and (stringp project-path) (file-directory-p project-path))
                      project-path (file-name-directory filename))))
           (ty (my-tui-python-server-executable "ty"))
           (pyrefly (my-tui-python-server-executable "pyrefly"))
           (ruff (my-tui-python-server-executable "ruff"))
           (name (concat (if ty "ty-" "pyrefly-") (substring (secure-hash 'sha1 root) 0 12)))
           (roots (my-tui-python-source-roots root))
           (python (or (cl-loop for dir in roots
                                for exe = (expand-file-name ".venv/bin/python" dir)
                                when (file-executable-p exe) return exe)
                       (executable-find "python3") (executable-find "python")))
           (environment (list :extra-paths (vconcat roots)))
           single)
      (when python (setq environment (plist-put environment :python python)))
      (when (or ty pyrefly)
        (setq single
              (my-tui-bridge-write-json
               name (list :name name :languageId "python"
                          :command (vector (or ty pyrefly) (if ty "server" "lsp"))
                          :settings (if ty
                                        (list :ty (list :configuration (list :environment environment)
                                                        :inlayHints (list :callArgumentNames :json-false)
                                                        :completions (list :autoImport t)))
                                      (make-hash-table)))))
        (if (and multi ruff)
            (let ((routing (concat name "-ruff")))
              (my-tui-bridge-write-json
               "ruff" (list :name "ruff" :languageId "python"
                            :command (vector ruff "server") :settings (make-hash-table)))
              (my-tui-bridge-write-json
               routing (list :default name :diagnostics (vector name "ruff")
                             :code_action (vector name "ruff")
                             :execute_command (vector name "ruff") :formatting "ruff"))
              routing)
          (unless multi single))))))

(defun my-tui-bridge-rust-config (filename)
  "Generate a Rust server config with an executable immune to rustup overrides."
  (when (and (stringp filename) (string-suffix-p ".rs" filename))
    (when-let* ((executable (my-tui-rust-analyzer-executable))
                (source (expand-file-name "lsp-bridge/langserver/rust-analyzer.json"
                                          user-emacs-directory))
                ((file-readable-p source)))
      (let ((config
             (with-temp-buffer
               (insert-file-contents source)
               (json-parse-buffer :object-type 'plist :array-type 'array
                                  :null-object nil :false-object :json-false))))
        (setq config (plist-put config :name "rust-analyzer-tui")
              config (plist-put config :command (vector executable)))
        (my-tui-bridge-write-json "rust-analyzer-tui" config)))))

(defun my-tui-bridge-project-path (filename)
  "Use the nearest Rust workspace rather than the enclosing Git monorepo."
  (when (and (stringp filename) (string-suffix-p ".rs" filename))
    (when-let* ((root (or (locate-dominating-file filename "Cargo.lock")
                          (locate-dominating-file filename "Cargo.toml"))))
      (directory-file-name (expand-file-name root)))))

(defun my-tui-bridge-single-server (project filename)
  (or (my-tui-bridge-python-config project filename)
      (my-tui-bridge-rust-config filename)))

(defun my-tui-bridge-multi-server (project filename)
  (my-tui-bridge-python-config project filename t))

(defun my-tui-bridge-show-signature (text)
  "Display signature TEXT on one line without resizing the echo area."
  (message "%s" (truncate-string-to-width
                  (replace-regexp-in-string "[\n\r]+" " " text)
                  (max 1 (1- (window-width (minibuffer-window)))))))

(defun my-tui-bridge-frame-adjust (original frame &optional position margin action-menu)
  "Keep FRAME within its terminal parent using character-cell margins."
  (if (and (not (display-graphic-p frame)) (featurep 'tty-child-frames))
      (progn
        ;; Upstream's GUI margin is 50 pixels; TTY coordinates count cells.
        (funcall original frame position (or margin 1) action-menu)
        (let* ((parent (frame-parent frame))
               (xy (frame-position frame))
               (right (max 0 (- (frame-width parent) (frame-width frame))))
               (bottom (max 0 (- (frame-height parent) (frame-height frame)))))
          (set-frame-position frame (max 0 (min (car xy) right))
                              (max 0 (min (cdr xy) bottom)))))
    (funcall original frame position margin action-menu)))

(defun my-tui-bridge-diagnostic-tooltip (original overlay &optional goto-beginning)
  "Display diagnostic OVERLAY in a bounded terminal child frame.
Upstream's diagnostic UI only considers graphical displays. ACM's child
frames also work in Emacs 31 terminals, without resizing the echo area."
  (when (overlay-buffer overlay)
    (if (and (not noninteractive) (not (display-graphic-p))
             (featurep 'tty-child-frames))
        (let* ((max-width (max 1 (- (window-body-width) 4)))
               (max-height (max 1 (min 10 (- (window-body-height) 4))))
               (fill-column (min 72 (max 1 (- max-width 4))))
               (resize (symbol-function 'acm-frame-set-frame-max-size)))
          (cl-letf (((symbol-function 'acm-frame-can-display-p) (lambda () t))
                    ((symbol-function 'acm-frame-set-frame-max-size)
                     (lambda (frame &optional width height)
                       (funcall resize frame (min (or width max-width) max-width)
                                (min (or height max-height) max-height)))))
            (funcall original overlay goto-beginning)))
      (funcall original overlay goto-beginning))))

(defun my-tui-bridge-enable ()
  "Enable ACM and LSP Bridge in supported programming buffers."
  (when (and (featurep 'lsp-bridge)
             (or (derived-mode-p 'emacs-lisp-mode)
                 (and buffer-file-name
                      (cond ((derived-mode-p 'python-mode)
                             (or (my-tui-python-server-executable "ty")
                                 (my-tui-python-server-executable "pyrefly")))
                            ((derived-mode-p 'c-mode 'c++-mode) (executable-find "clangd"))
                            ((derived-mode-p 'go-mode) (executable-find "gopls"))
                            ((derived-mode-p 'rust-mode) (my-tui-rust-analyzer-executable))
                            ((derived-mode-p 'yaml-mode) (executable-find "yaml-language-server"))
                            ((derived-mode-p 'js-json-mode) (executable-find "vscode-json-language-server"))))))
    (lsp-bridge-mode 1)
    (when (bound-and-true-p lsp-bridge-semantic-tokens-mode)
      (lsp-bridge-semantic-tokens-mode -1))))

(let ((source (expand-file-name "lsp-bridge/" user-emacs-directory)))
  (when (and (or (display-graphic-p) (featurep 'tty-child-frames))
             (file-exists-p (expand-file-name "lsp-bridge.el" source))
             (file-executable-p (expand-file-name ".cache/python-tools/bin/python" user-emacs-directory))
             (locate-library "yasnippet") (locate-library "markdown-mode"))
    (add-to-list 'load-path source)
    (require 'yasnippet)
    (setq acm-enable-icon nil acm-enable-tabnine nil
          acm-enable-doc t acm-enable-doc-markdown-render nil
          acm-enable-preview nil
          acm-backend-lsp-candidate-min-length 1
          acm-backend-search-file-words-candidate-min-length 3
          lsp-bridge-python-command
          (expand-file-name ".cache/python-tools/bin/python" user-emacs-directory)
          lsp-bridge-python-lsp-server "ty"
          lsp-bridge-python-multi-lsp-server nil
          lsp-bridge-log-level 'warning
          lsp-bridge-enable-inlay-hint nil
          lsp-bridge-enable-auto-format-code nil
          lsp-bridge-enable-hover-diagnostic t
          lsp-bridge-diagnostic-display-errors-delay 0.4
          lsp-bridge-enable-document-highlight t
          lsp-bridge-signature-show-function #'my-tui-bridge-show-signature
          lsp-bridge-user-langserver-dir
          (expand-file-name ".cache/lsp-bridge-servers/" user-emacs-directory)
          lsp-bridge-user-multiserver-dir lsp-bridge-user-langserver-dir
          lsp-bridge-get-project-path-by-filepath #'my-tui-bridge-project-path
          lsp-bridge-get-single-lang-server-by-project #'my-tui-bridge-single-server
          lsp-bridge-get-multi-lang-server-by-project #'my-tui-bridge-multi-server)
    (require 'lsp-bridge)
    (advice-add 'acm-frame-adjust-frame-pos :around #'my-tui-bridge-frame-adjust)
    (advice-add 'lsp-bridge-diagnostic-show-tooltip :around
                #'my-tui-bridge-diagnostic-tooltip)
    (add-hook 'prog-mode-hook #'my-tui-bridge-enable 90)
    (add-hook 'yaml-mode-hook #'my-tui-bridge-enable 90)))

(unless (featurep 'lsp-bridge)
  (message "LSP Bridge is unavailable; run scripts/install-lsp-bridge.sh and install the TUI packages"))

(defun my-tui-lsp-command (bridge fallback)
  "Run BRIDGE in LSP Bridge buffers and FALLBACK elsewhere."
  (cond ((bound-and-true-p lsp-bridge-mode) (call-interactively bridge))
        (fallback (call-interactively fallback))
        (t (user-error "LSP Bridge is not active in this buffer"))))

(defun my-tui-lsp-definition () (interactive)
       (my-tui-lsp-command #'lsp-bridge-find-def #'xref-find-definitions))
(defun my-tui-lsp-back () (interactive)
       (my-tui-lsp-command #'lsp-bridge-find-def-return #'xref-go-back))
(defun my-tui-lsp-references () (interactive)
       (my-tui-lsp-command #'lsp-bridge-find-references #'xref-find-references))
(defun my-tui-lsp-documentation () (interactive)
       (my-tui-lsp-command #'lsp-bridge-show-documentation #'eldoc-doc-buffer))

;; =============================================================================
;; Editing integration
;; =============================================================================

(defun my-tui-format-all-buffer (&optional choose)
  "Manually format with external tools; CHOOSE selects a different formatter."
  (interactive "P")
  (when buffer-read-only
    (user-error "Read-only: use C-x C-q or C-c t r to enable editing"))
  (unless (require 'format-all nil t)
    (user-error "Install format-all with my-tui-install-packages"))
  (let* ((ruff (my-tui-python-server-executable "ruff"))
         (exec-path (if ruff (cons (file-name-directory ruff) exec-path) exec-path)))
    (format-all-ensure-formatter)
    (format-all-buffer (when choose 'always))))

(defun my-tui-format-all-language (original)
  "Recognize builtin JSON mode without changing its syntax highlighting."
  (if (eq major-mode 'js-json-mode) "JSON" (funcall original)))

(defun my-tui-format-buffer ()
  "Use the active language server, or manually invoke the external formatter."
  (interactive)
  (if (bound-and-true-p lsp-bridge-mode)
      (lsp-bridge-code-format)
    (my-tui-format-all-buffer)))

(with-eval-after-load 'format-all
  (setq format-all-show-errors 'errors)
  (advice-add 'format-all--language-id-buffer :around #'my-tui-format-all-language)
  (setf (alist-get "Python" format-all-default-formatters nil nil #'equal) '(ruff)))

(with-eval-after-load 'python
  (define-key python-mode-map (kbd "M-<right>") #'python-indent-shift-right)
  (define-key python-mode-map (kbd "M-<left>") #'python-indent-shift-left))

(defun my-open-block-c-mode (_id action _context)
  "Expand a newly inserted brace pair into an indented block."
  (when (eq action 'insert)
    (newline)
    (newline)
    (indent-according-to-mode)
    (forward-line -1)
    (indent-according-to-mode)))

(defun my-tui-install-block-pairs (modes)
  "Add block expansion after Smartparens has loaded MODES' defaults."
  (dolist (mode modes)
    (let ((pair (cl-find-if (lambda (pair) (equal (plist-get pair :open) "{"))
                            (cdr (assq mode sp-pairs)))))
      (unless (memq 'my-open-block-c-mode (plist-get pair :post-handlers))
        (sp-local-pair mode "{" nil :post-handlers '(:add my-open-block-c-mode))))))

(when (featurep 'smartparens)
  (sp-local-pair 'minibuffer-inactive-mode "'" nil :actions nil)
  (sp-with-modes '(markdown-mode gfm-mode rst-mode)
    (sp-local-pair "*" "*" :bind "C-*")
    (sp-local-tag "2" "**" "**")
    (sp-local-tag "s" "```scheme" "```")
    (sp-local-tag "<" "<_>" "</_>" :transform 'sp-match-sgml-tags))
  (sp-with-modes '(tex-mode plain-tex-mode latex-mode)
    (sp-local-tag "i" "\"<" "\">"))
  (sp-with-modes '(html-mode sgml-mode) (sp-local-pair "<" ">"))
  (my-tui-install-block-pairs '(c-mode c++-mode go-mode java-mode))
  (with-eval-after-load 'smartparens-c
    (my-tui-install-block-pairs '(c-mode c++-mode java-mode)))
  (with-eval-after-load 'smartparens-go
    (my-tui-install-block-pairs '(go-mode))))

(provide 'lsp-config)
;;; lsp-config.el ends here
