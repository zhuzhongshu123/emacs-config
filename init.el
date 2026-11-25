;;; init.el --- Terminal Emacs configuration -*- lexical-binding: t; -*-

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 01. 启动与包管理
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(add-to-list 'load-path (expand-file-name "modules" user-emacs-directory))

;; Emacs 29+ supplies use-package.  Third-party packages are optional;
;; install them explicitly with M-x my-tui-install-packages.
(require 'cl-lib)
(require 'package)
(package-initialize)
(require 'use-package)
(setq use-package-always-ensure nil)
(setq custom-file (expand-file-name "custom-tui.el" user-emacs-directory))
(load custom-file t t)

(defconst my-tui-packages
  '(helm projectile helm-projectile hydra window-numbering
    smartparens multiple-cursors yasnippet yasnippet-snippets
    duplicate-thing comment-dwim-2 orderless rainbow-delimiters
    markdown-mode yaml-mode rust-mode magit
    cape helpful diff-hl indent-bars avy vundo eat dashboard vterm vterm-toggle
    which-key go-mode helm-ag doom-modeline nerd-icons treesit-fold format-all
    kkp)
  "Optional packages preserving the original config's editing workflow.")

(defun my-tui-install-packages ()
  "Install optional TUI packages, then restart Emacs to activate them.
This is the only TUI entry point that refreshes package archives."
  (interactive)
  (package-refresh-contents)
  (let (failed)
    (dolist (pkg my-tui-packages)
      (unless (package-installed-p pkg)
        (condition-case err
            (package-install pkg)
          (error (push pkg failed)
                 (message "Could not install %s: %s" pkg err)))))
    (if failed
        (user-error "Failed packages: %s; retry my-tui-install-packages" failed)
      (message "TUI packages installed. Restart Emacs to activate them."))))
;; TUI 真彩色与共享提亮

(require 'face-remap)

;; This profile deliberately uses terminal colors.  A daemon started from a
;; stripped automation environment may otherwise pass NO_COLOR to every child,
;; causing programs such as Ink to disable their palette inside vterm.
(setenv "NO_COLOR" nil)

(defcustom my-tui-syntax-brightness 0.15
  "Fraction of white mixed into colored syntax text in truecolor TUI frames.
0 restores the theme's original colors. Values around 0.05–0.20 are useful
for mild adjustment; graphical frames and the original theme palette are untouched."
  :type 'number
  :group 'faces)

;; Ink 目录标题 face：与 TUI 共用亮度配置

(defconst my-tui-ink-heading-face-sources
  '((my-tui-ink-heading-1 . outline-1) (my-tui-ink-heading-2 . outline-2)
    (my-tui-ink-heading-3 . outline-3) (my-tui-ink-heading-4 . outline-4)
    (my-tui-ink-heading-5 . outline-5) (my-tui-ink-heading-6 . outline-6)))
(dolist (entry my-tui-ink-heading-face-sources)
  (unless (facep (car entry)) (make-face (car entry)))
  (set-face-attribute (car entry) nil :inherit (cdr entry)))

(defconst my-tui-brightened-syntax-faces
  '(font-lock-builtin-face font-lock-constant-face font-lock-function-name-face
    font-lock-keyword-face font-lock-string-face font-lock-type-face
    font-lock-variable-name-face font-lock-negation-char-face
    font-lock-preprocessor-face font-lock-preprocessor-char-face
    font-lock-regexp-grouping-backslash font-lock-regexp-grouping-construct
    ansi-color-red ansi-color-green ansi-color-yellow ansi-color-blue
    ansi-color-magenta ansi-color-cyan
    my-tui-ink-heading-1 my-tui-ink-heading-2 my-tui-ink-heading-3
    my-tui-ink-heading-4 my-tui-ink-heading-5 my-tui-ink-heading-6))

(defun my-tui-lighten-rgb (color amount)
  "Mix six-digit RGB COLOR with white by AMOUNT without terminal quantization."
  (unless (and (numberp amount) (<= 0 amount 1))
    (user-error "TUI syntax brightness must be between 0 and 1"))
  (when (and (stringp color) (string-match-p "\\`#[[:xdigit:]]\\{6\\}\\'" color))
    (apply #'format "#%02x%02x%02x"
           (mapcar (lambda (offset)
                     (let ((channel (string-to-number (substring color offset (+ offset 2)) 16)))
                       (round (+ channel (* amount (- 255 channel))))))
                   '(1 3 5)))))

(defun my-tui-original-face-color (face frame)
  "Read FACE's original foreground from enabled theme specs for FRAME.
Reading immutable theme specs avoids accumulating brightness on reapplication."
  (setq face (or (alist-get face my-tui-ink-heading-face-sources) face))
  (cl-loop for theme in custom-enabled-themes
           for setting = (cl-find-if
                          (lambda (setting)
                            (and (eq (car setting) 'theme-face) (eq (cadr setting) face)))
                          (get theme 'theme-settings))
           for attrs = (and setting (face-spec-choose (nth 3 setting) frame))
           for color = (plist-get attrs :foreground)
           when (and (stringp color) (string-match-p "\\`#[[:xdigit:]]\\{6\\}\\'" color))
           return color))

(defun my-tui-apply-syntax-brightness (&optional frame)
  "Apply a frame-local syntax adjustment to truecolor terminal FRAME."
  (let ((frame (or frame (selected-frame))))
    (when (and (frame-live-p frame) (not (display-graphic-p frame))
               (>= (display-color-cells frame) 16777216))
      (dolist (face my-tui-brightened-syntax-faces)
        (when (facep face)
          (when-let* ((base (my-tui-original-face-color face frame))
                      (color (my-tui-lighten-rgb base my-tui-syntax-brightness)))
            (set-face-foreground face color frame)))))))

(defun my-tui-refresh-syntax-brightness (&rest _)
  "Reapply the terminal adjustment after a theme or brightness change."
  (mapc #'my-tui-apply-syntax-brightness (frame-list)))

(defun my-tui-set-syntax-brightness (amount)
  "Set terminal syntax brightening to AMOUNT; 0 restores original colors."
  (interactive (list (read-number "TUI syntax brightness (0=original, 0.15=mild): "
                                  my-tui-syntax-brightness)))
  (unless (and (numberp amount) (<= 0 amount 1))
    (user-error "TUI syntax brightness must be between 0 and 1"))
  (setq my-tui-syntax-brightness amount)
  (my-tui-refresh-syntax-brightness))

(defun my-tui-preview-syntax-colors (&optional amount)
  "Compare original syntax colors with AMOUNT in two read-only buffers.
The comparison uses buffer-local face remapping and does not change the
global brightness.  Press q in either preview to restore the window layout."
  (interactive (list (read-number "Compare original with brightness: " 0.15)))
  (setq amount (or amount 0.15))
  (unless (and (numberp amount) (<= 0 amount 1))
    (user-error "TUI syntax brightness must be between 0 and 1"))
  (let ((frame (selected-frame))
        (layout (current-window-configuration))
        buffers)
    (unless (and (not (display-graphic-p frame))
                 (>= (display-color-cells frame) 16777216))
      (user-error "Open this comparison in a truecolor terminal frame"))
    (dolist (level (list 0 amount))
      (let ((buffer (get-buffer-create
                     (format "*TUI colors: %s*"
                             (if (= level 0) "original" (format "%.0f%%" (* 100 level)))))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (special-mode)
            (setq-local truncate-lines t)
            (setq-local header-line-format
                        (format "Mood-one | white mix %.0f%% | q: return" (* 100 level)))
            (dolist (face my-tui-brightened-syntax-faces)
              (when-let* ((base (my-tui-original-face-color face frame)))
                (face-remap-add-relative
                 face :foreground (my-tui-lighten-rgb base level))))
            (dolist (part
                     '(("# Same sample, different syntax colors\n\n" . font-lock-comment-face)
                       ("from " . font-lock-keyword-face)
                       ("helper " . font-lock-type-face)
                       ("import " . font-lock-keyword-face)
                       ("Model\n\n" . font-lock-type-face)
                       ("class " . font-lock-keyword-face)
                       ("Reader" . font-lock-type-face)
                       (":\n    " . default)
                       ("def " . font-lock-keyword-face)
                       ("greet" . font-lock-function-name-face)
                       ("(self, " . default)
                       ("name" . font-lock-variable-name-face)
                       ("): \n        " . default)
                       ("message" . font-lock-variable-name-face)
                       (" = " . default)
                       ("\"Hello, world\"\n        " . font-lock-string-face)
                       ("if " . font-lock-keyword-face)
                       ("name" . font-lock-variable-name-face)
                       (":\n            " . default)
                       ("print" . font-lock-builtin-face)
                       ("(message)\n        " . default)
                       ("return " . font-lock-keyword-face)
                       ("None\n\n" . font-lock-constant-face)))
              (insert (propertize (car part) 'face (cdr part))))
            (dolist (face '(font-lock-keyword-face font-lock-variable-name-face
                           font-lock-function-name-face font-lock-string-face
                           font-lock-type-face font-lock-builtin-face
                           font-lock-constant-face font-lock-comment-face))
              (insert (propertize (format "%s\n" face) 'face face)))
            (goto-char (point-min)))
          (local-set-key (kbd "q")
                         (lambda () (interactive) (set-window-configuration layout))))
        (push buffer buffers)))
    (setq buffers (nreverse buffers))
    (delete-other-windows)
    (let* ((left (selected-window))
           (right (split-window-right)))
      (set-window-buffer left (car buffers))
      (set-window-buffer right (cadr buffers))
      (select-window left))
    buffers))

(add-hook 'after-make-frame-functions #'my-tui-apply-syntax-brightness)
(add-hook 'enable-theme-functions #'my-tui-refresh-syntax-brightness)
(my-tui-refresh-syntax-brightness)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 03. 基础界面、编辑默认值与历史记录
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(menu-bar-mode -1)
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(setq inhibit-startup-screen t
      ring-bell-function #'ignore
      ;; Emacs 31 can synchronize the terminal's hardware cursor with the
      ;; theme's cursor face (mood-one blue) through OSC 12.
      xterm-update-cursor 'color
      scroll-step 1
      scroll-margin 0
      scroll-conservatively 10000
      make-backup-files nil
      tab-always-indent 'complete
      c-tab-always-indent 'complete
      c-default-style "stroustrup")
(setq-default tab-width 4 fill-column 120 word-wrap t indent-tabs-mode nil)
(set-default-coding-systems 'utf-8)
(prefer-coding-system 'utf-8)
(show-paren-mode 1)
(column-number-mode 1)
(line-number-mode 1)
(fset 'yes-or-no-p 'y-or-n-p)
(add-hook 'prog-mode-hook #'display-line-numbers-mode)
(add-hook 'text-mode-hook #'visual-line-mode)
(let ((state-dir (expand-file-name ".cache/" user-emacs-directory)))
  (make-directory state-dir t)
  (setq savehist-file (expand-file-name "history" state-dir)
        save-place-file (expand-file-name "places" state-dir)
        recentf-save-file (expand-file-name "recentf" state-dir)))
(savehist-mode 1)
(save-place-mode 1)
(require 'recentf)
(setq recentf-max-saved-items 100
      recentf-exclude '("/elpa/" "/eln-cache/" "^/[^/:]+:"))
(recentf-mode 1)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 04. 内置补全、搜索与基础快捷键
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Completion and project navigation work offline even before package setup.
(setq completion-styles '(basic substring partial-completion)
      completion-cycle-threshold 3)
(require 'icomplete)
(icomplete-mode 1)
(require 'project)
(require 'xref)
(setq eldoc-echo-area-use-multiline-p nil
      eldoc-echo-area-display-truncation-message nil
      eldoc-echo-area-prefer-doc-buffer t
      eldoc-idle-delay 0.4)
(defun my-tui-buffer-list ()
  "Switch buffers using completion."
  (interactive)
  (if (fboundp 'helm-buffers-list) (helm-buffers-list) (switch-to-buffer nil)))

(defun my-tui-meta-bracket ()
  "Switch buffers with Meta-[ while preserving terminal CSI key sequences.
CSI sequences for arrows and modified keys start with the same ESC [ bytes.
Replay that prefix through Emacs's key decoder with ordinary bindings removed,
then distinguish a standalone Meta-[ from a complete terminal key sequence."
  (interactive)
  (if (display-graphic-p)
      (my-tui-buffer-list)
    (let ((read-key-delay 0.1))
      (setq unread-command-events (append '(27 91) unread-command-events))
      (let ((event (read-key nil t)))
        (if (or (eq event 27) (equal event (aref (kbd "M-[") 0)))
            (progn
              ;; read-key can return ESC and leave our synthetic [ unread.
              (when (and (eq event 27) (eq (car unread-command-events) 91))
                (setq unread-command-events (cdr unread-command-events)))
              (my-tui-buffer-list))
          (setq unread-command-events (cons event unread-command-events)))))))

(defun my-tui-project-search ()
  "Search the project with ripgrep/Helm when installed, otherwise project grep."
  (interactive)
  (cond ((and (executable-find "ag") (require 'helm-ag nil t))
         (helm-do-ag (if-let* ((project (project-current)))
                         (project-root project)
                       default-directory)))
        ((and (featurep 'helm-projectile)
              (or (executable-find "rg") (executable-find "ag")))
         (helm-projectile-ag))
        (t (call-interactively #'project-find-regexp))))

(defun my-tui-shell ()
  "Open an Eshell in the current buffer's directory."
  (interactive)
  (let ((dir default-directory))
    (eshell t)
    (eshell/cd dir)
    (eshell-reset)))

;; Core key bindings, including alternatives to C-RET, C-S-c and C-/.
(global-set-key (kbd "C-c b") #'my-tui-buffer-list)
(global-set-key (kbd "M-[") #'my-tui-meta-bracket)
(global-set-key (kbd "C-s") #'occur)
(global-set-key (kbd "C-r") #'my-tui-project-search)
(global-set-key (kbd "C-c C-j") #'imenu)
(global-set-key (kbd "C-c C-o") #'my-tui-terminal-toggle)
(global-set-key (kbd "C-c SPC") #'set-mark-command)
(global-set-key (kbd "C-<return>") #'set-mark-command)
(global-set-key (kbd "C-c ;") #'comment-dwim)
(global-set-key (kbd "C-x C-a C-a") #'revert-buffer)
(global-set-key (kbd "C-\\") #'delete-whitespace-rectangle)
(global-set-key (kbd "M->") #'xref-go-back)
(global-set-key (kbd "C-c C-d") #'eldoc-doc-buffer)
(global-set-key (kbd "<f10>") #'my-tui-format-buffer)
(define-key global-map (kbd "C-c C-p") project-prefix-map)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 05. Helm、项目导航与编辑包
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Keep the original Meta-[ binding as well as the C-c b alternative.
(when (require 'helm nil t)
  ;; Helm remains the selector for files and commands, not code completion.
  (setq helm-mode-handle-completion-in-region nil)
  (remove-function completion-in-region-function #'helm--completion-in-region)
  (helm-mode 1)
  (icomplete-mode -1)
  (setq helm-ff-DEL-up-one-level-maybe t
        helm-follow-mode-persistent t
        helm-buffer-max-length 50)
  (global-set-key (kbd "C-x C-f") #'helm-find-files)
  (global-set-key (kbd "C-s") #'helm-occur)
  (global-set-key (kbd "M-x") #'helm-M-x)
  (global-set-key (kbd "M-y") #'helm-show-kill-ring)
  (global-set-key (kbd "C-c C-j") #'helm-imenu))
(when (require 'projectile nil t)
  (projectile-mode 1)
  (when (require 'helm-projectile nil t)
    (setq projectile-completion-system 'helm
          helm-projectile-ask-to-install-helm-rg nil)
    (helm-projectile-on)))
(when (require 'window-numbering nil t) (window-numbering-mode 1))
(when (locate-library "magit")
  (autoload 'magit-status "magit" nil t)
  (global-set-key (kbd "C-x g") #'magit-status))
(when (require 'orderless nil t)
  (setq completion-styles '(orderless basic)
        completion-category-overrides '((file (styles basic partial-completion)))))
(when (require 'smartparens-config nil t)
  (smartparens-global-mode 1)
  (show-smartparens-global-mode 1)
  (dolist (pair '(("（" "）") ("“" "”") ("【" "】")))
    (sp-pair (car pair) (cadr pair)))
  (dolist (binding '(("C-c C-f" . sp-forward-sexp)
                     ("C-c C-b" . sp-backward-sexp)
                     ("C-c C-n" . sp-next-sexp)
                     ("C-c C-k" . sp-kill-sexp)
                     ("C-c C-w" . sp-copy-sexp)
                     ("C-c C-a" . sp-beginning-of-sexp)
                     ("C-c C-e" . sp-end-of-sexp)))
    (define-key sp-keymap (kbd (car binding)) (cdr binding))))
(when (require 'yasnippet nil t)
  (add-to-list 'yas-snippet-dirs (expand-file-name "snippets" user-emacs-directory))
  (yas-global-mode 1)
  (define-key yas-minor-mode-map (kbd "TAB") nil)
  (global-set-key (kbd "C-c y") #'yas-expand)
  (require 'yasnippet-snippets nil t))
(when (require 'multiple-cursors nil t)
  (global-set-key (kbd "C-c m") #'mc/edit-lines)
  (global-set-key (kbd "C-c n") #'mc/mark-next-like-this)
  (global-set-key (kbd "C-c p") #'mc/mark-previous-like-this))
(when (require 'duplicate-thing nil t)
  (global-set-key (kbd "C-o") #'duplicate-thing))
(when (require 'comment-dwim-2 nil t)
  (global-set-key (kbd "C-c ;") #'comment-dwim-2))
(when (require 'rainbow-delimiters nil t)
  (add-hook 'prog-mode-hook #'rainbow-delimiters-mode))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 06. Markdown / Ink 阅读
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Ink：后端选项与 buffer 状态

(require 'ansi-color)

(require 'ansi-osc)

(defcustom my-tui-ink-program "ink"
  "Executable used to render Markdown into a terminal-styled buffer."
  :type 'string
  :group 'applications)

(defcustom my-tui-ink-theme "terminal"
  "Ink theme used by Emacs previews, or nil to let Ink choose automatically.
This setting is independent of Ink's user-level config file."
  :type '(choice (const :tag "Automatic" nil) string)
  :group 'applications)

(defvar-local my-tui-ink-source-file nil
  "Markdown source rendered in the current Ink preview buffer.")

(defconst my-tui-ink-buffer-faces
  '(("light" :background "#ffffff" :foreground "#24292f"))
  "Default Emacs buffer faces needed to complete an Ink plain-output theme.
Ink plain output colors individual elements but leaves the host's default
background untouched, so light previews need a matching buffer-local base.")

(defcustom my-tui-ink-native-program "ink-emacs"
  "Ink executable with the emacs-sexp output extension."
  :type 'string :group 'applications)

(defcustom my-tui-ink-format 'auto
  "Preview backend: auto prefers S-expression and falls back to stock Ink."
  :type '(choice (const auto) (const emacs-sexp) (const ansi))
  :group 'applications)

(defvar-local my-tui-ink-headings nil)

(defvar-local my-tui-ink-code-blocks nil)

(defvar-local my-tui-ink-width nil)

(defvar-local my-tui-ink-backend nil)

(defcustom my-tui-ink-sidebar-width 28
  "Preferred width of the Markdown contents sidebar, in columns."
  :type 'integer :group 'applications)

(defvar-local my-tui-ink-sidebar-buffer nil)

(defvar-local my-tui-ink-sidebar-visible t)

(defvar-local my-tui-ink-sidebar-owner nil)

(defvar-local my-tui-ink-sidebar-highlight nil)

(defvar my-tui-ink-syncing-windows nil)


;; Ink：预览与目录 major mode、截断显示

(defun my-tui-ink-use-ellipsis ()
  "Use an ellipsis for clipped text in Ink buffers instead of a dollar sign."
  (setq-local buffer-display-table (if buffer-display-table
                                      (copy-sequence buffer-display-table)
                                    (make-display-table)))
  (set-display-table-slot buffer-display-table 'truncation (vector ?…)))

(define-derived-mode my-tui-ink-preview-mode special-mode "Ink"
  "Read-only mode for Markdown rendered by ink-md."
  ;; Ink has already wrapped paragraphs and code. A second Emacs wrap can
  ;; turn a full-width code box into two screen rows per source line.
  (setq-local truncate-lines t)
  (my-tui-ink-use-ellipsis)
  (add-hook 'post-command-hook #'my-tui-ink-sidebar-sync nil t)
  (add-hook 'kill-buffer-hook #'my-tui-ink-sidebar-cleanup nil t))

(define-derived-mode my-tui-ink-sidebar-mode special-mode "Ink Contents"
  "Contents sidebar for an Ink preview."
  (setq-local truncate-lines t mode-line-format nil
              header-line-format " Contents")
  (my-tui-ink-use-ellipsis))


;; Ink：S-expression 协议校验、主题映射与代码高亮

(defun my-tui-ink-read-document (raw)
  "Read and validate one protocol-v1 S-expression from RAW."
  (with-current-buffer raw
    (goto-char (point-min))
    (let* ((data (let ((read-circle nil)) (read (current-buffer))))
           (text (plist-get data :text))
           (styles (plist-get data :styles)))
      (skip-chars-forward " \t\r\n")
      (unless (and (eobp) (proper-list-p data)
                   (eq (plist-get data :version) 1)
                   (eq (plist-get data :offset-unit) 'unicode-scalar)
                   (stringp text) (vectorp styles)
                   (integerp (plist-get data :width))
                   (<= 20 (plist-get data :width) 1000)
                   (cl-every (lambda (key) (vectorp (plist-get data key)))
                             '(:runs :headings :code-blocks :footnotes)))
        (error "Invalid Ink S-expression document"))
      (cl-labels ((range-p (start end)
                   (and (integerp start) (integerp end)
                        (<= 0 start end (length text)))))
        ;; Insert the rendered text once.  Comparing many fragments against a
        ;; multimibyte string via `substring' repeatedly scans for character
        ;; offsets; buffer positions give the same Unicode-scalar boundaries
        ;; without that rescan.  Protocol offsets are 0-based, buffer
        ;; positions are 1-based.
        (with-temp-buffer
          (insert text)
        (seq-doseq (style styles)
          (unless (and (proper-list-p style) (zerop (% (length style) 2)))
            (error "Invalid Ink style"))
          (dolist (key '(:fg :bg :link :footnote))
            (unless (or (null (plist-get style key))
                        (stringp (plist-get style key)))
              (error "Invalid Ink style %s" key)))
          (dolist (key '(:bold :italic :underline :strike :dim))
            (unless (memq (plist-get style key) '(nil t))
              (error "Invalid Ink style attribute"))))
        (seq-doseq (run (plist-get data :runs))
          (unless (and (proper-list-p run) (= (length run) 3)
                       (range-p (nth 0 run) (nth 1 run))
                       (integerp (nth 2 run)) (<= 0 (nth 2 run))
                       (< (nth 2 run) (length styles)))
            (error "Invalid Ink style interval")))
        (seq-doseq (heading (plist-get data :headings))
          (unless (and (proper-list-p heading) (= (length heading) 5)
                       (range-p (car heading) (car heading))
                       (integerp (nth 1 heading)) (<= 1 (nth 1 heading) 6)
                       (stringp (nth 2 heading)) (stringp (nth 3 heading))
                       (integerp (nth 4 heading)) (> (nth 4 heading) 0))
            (error "Invalid Ink heading")))
        (seq-doseq (block (plist-get data :code-blocks))
          (unless (and (proper-list-p block) (= (length block) 5)
                       (range-p (nth 0 block) (nth 1 block))
                       (stringp (nth 2 block)) (stringp (nth 3 block))
                       (vectorp (nth 4 block)))
            (error "Invalid Ink code block"))
          (seq-doseq (fragment (nth 4 block))
            (unless (and (proper-list-p fragment) (= (length fragment) 3)
                         (range-p (nth 0 fragment) (nth 1 fragment))
                         (<= (nth 0 block) (nth 0 fragment) (nth 1 fragment) (nth 1 block))
                         (integerp (nth 2 fragment)) (<= 0 (nth 2 fragment))
                         (<= (+ (nth 2 fragment) (- (nth 1 fragment) (nth 0 fragment)))
                             (length (nth 3 block)))
                         (equal (buffer-substring-no-properties
                                 (1+ (nth 0 fragment)) (1+ (nth 1 fragment)))
                                (substring (nth 3 block) (nth 2 fragment)
                                           (+ (nth 2 fragment) (- (nth 1 fragment) (nth 0 fragment))))))
              (error "Invalid Ink code source mapping"))))
        (seq-doseq (note (plist-get data :footnotes))
          (unless (and (proper-list-p note) (= (length note) 2)
                       (cl-every #'stringp note))
            (error "Invalid Ink footnote")))))
      data)))

(defun my-tui-ink-color (value)
  "Resolve Ink VALUE through the current mood-one ANSI foreground palette."
  (when (stringp value)
    (cond
     ((string-match-p "\\`#[[:xdigit:]]\\{6\\}\\'" value) value)
     ((string-prefix-p "ansi:" value)
      (let* ((name (substring value 5))
             (names '["black" "red" "green" "yellow" "blue" "magenta" "cyan" "white"
                      "bright-black" "bright-red" "bright-green" "bright-yellow"
                      "bright-blue" "bright-magenta" "bright-cyan" "bright-white"])
             (index (if (string-match-p "\\`[0-9]+\\'" name)
                        (string-to-number name) (cl-position name names :test #'equal)))
             (faces '[ansi-color-black ansi-color-red ansi-color-green ansi-color-yellow
                      ansi-color-blue ansi-color-magenta ansi-color-cyan ansi-color-white]))
        (when (and index (<= 0 index 15))
          (face-attribute (if (= index 8) 'shadow (aref faces (% index 8)))
                          :foreground nil t)))))))

(defun my-tui-ink-style-face (style)
  "Convert a protocol STYLE to Emacs face attributes."
  (append
   (when-let* ((fg (my-tui-ink-color (plist-get style :fg)))) (list :foreground fg))
   (when-let* ((bg (my-tui-ink-color (plist-get style :bg)))) (list :background bg))
   (when (plist-get style :bold) '(:weight bold))
   (when (plist-get style :italic) '(:slant italic))
   (when (plist-get style :underline) '(:underline t))
   (when (plist-get style :strike) '(:strike-through t))
   (when (plist-get style :dim) '(:inherit shadow))))

(defun my-tui-ink-fontify-code (block)
  "Use an ordinary Emacs major mode to fontify mapped code in BLOCK."
  (let* ((mode (cdr (assoc-string
                    (nth 2 block)
                    '(("python" . python-mode) ("py" . python-mode)
                      ("cpp" . c++-mode) ("c++" . c++-mode) ("c" . c-mode)
                      ("go" . go-mode) ("rust" . rust-mode) ("rs" . rust-mode)
                      ("yaml" . yaml-mode) ("yml" . yaml-mode)
                      ("json" . js-json-mode) ("javascript" . js-mode)
                      ("js" . js-mode) ("typescript" . typescript-mode)
                      ("bash" . sh-mode) ("sh" . sh-mode) ("sql" . sql-mode)
                      ("elisp" . emacs-lisp-mode) ("emacs-lisp" . emacs-lisp-mode)) t)))
         (target (current-buffer)))
    (when (and mode (fboundp mode) (> (length (nth 4 block)) 0))
      (with-temp-buffer
        (insert (nth 3 block))
        ;; A read-only preview must never start LSP, indentation or file hooks.
        (let ((major-mode-remap-alist nil) (enable-local-variables nil))
          (delay-mode-hooks (funcall mode)))
        (font-lock-ensure)
        (seq-doseq (fragment (nth 4 block))
          (let ((pos (1+ (nth 2 fragment)))
                (end (+ 1 (nth 2 fragment) (- (nth 1 fragment) (nth 0 fragment)))))
            (while (< pos end)
              (let* ((next (next-single-property-change pos 'face nil end))
                     (face (get-text-property pos 'face))
                     (start (+ 1 (nth 0 fragment) (- pos 1 (nth 2 fragment)))))
                (with-current-buffer target
                  ;; Nil removes Syntect's classification from unfontified text.
                  (put-text-property start (+ start (- next pos)) 'face face))
                (setq pos next)))))))))

(defun my-tui-ink-insert-document (data)
  "Insert validated structured DATA into the current preview."
  (require 'button)
  (insert (plist-get data :text))
  (setq-local my-tui-ink-headings (plist-get data :headings)
              my-tui-ink-code-blocks (plist-get data :code-blocks))
  (let* ((styles (plist-get data :styles))
         (faces (vconcat (mapcar #'my-tui-ink-style-face styles))))
    (seq-doseq (run (plist-get data :runs))
      (let* ((start (1+ (nth 0 run))) (end (1+ (nth 1 run)))
             (style (aref styles (nth 2 run))) (face (aref faces (nth 2 run))))
        (when face (put-text-property start end 'face face))
        (when-let* ((url (plist-get style :link)))
          (make-text-button start end 'browse-url-data url
                            'action #'my-tui-ink-follow-link 'follow-link t
                            'face face 'help-echo url))
        (when-let* ((note (cl-find (plist-get style :footnote) (plist-get data :footnotes)
                                     :key #'car :test #'equal)))
          (put-text-property start end 'help-echo (cadr note))))))
  (seq-doseq (block my-tui-ink-code-blocks)
    (my-tui-ink-fontify-code block)))


;; Ink：Ink 进程与文档渲染

(defun my-tui-ink-preview-buffer-name (file)
  "Return a stable, unambiguous preview buffer name for FILE."
  (format "*Ink: %s <%s>*"
          (file-name-nondirectory file)
          (substring (secure-hash 'sha1 (file-truename file)) 0 7)))

(defun my-tui-ink-render (file buffer width)
  "Render Markdown FILE into BUFFER at WIDTH columns, preferring native data."
  (let* ((native (and (not (eq my-tui-ink-format 'ansi))
                      (executable-find my-tui-ink-native-program)))
         (program (or native (executable-find my-tui-ink-program)))
         (raw (generate-new-buffer " *ink-output*"))
         (stderr (make-temp-file "ink-stderr-"))
         (default-directory (file-name-directory file))
         (coding-system-for-read 'utf-8-unix))
    (unwind-protect
        (progn
          (unless program (user-error "Ink is unavailable; install ink-md"))
          (when (and (eq my-tui-ink-format 'emacs-sexp) (not native))
            (user-error "Structured Ink executable is unavailable: %s" my-tui-ink-native-program))
          (let* ((arguments
                  (append (if native '("--format" "emacs-sexp")
                            '("--plain" "--no-pager" "--color" "always" "--no-images"))
                          (when my-tui-ink-theme (list "--theme" my-tui-ink-theme))
                          (list "--width" (number-to-string width) file)))
                 (status (apply #'process-file program nil (list raw stderr) nil arguments))
                 (data (and (eq status 0) native (my-tui-ink-read-document raw)))
                 (rendered (and data
                                (with-temp-buffer
                                  (my-tui-ink-preview-mode)
                                  (let ((inhibit-read-only t))
                                    (my-tui-ink-insert-document data))
                                  (buffer-string)))))
            (unless (eq status 0)
              (user-error "Ink failed (%s): %s" status
                          (with-temp-buffer (insert-file-contents stderr)
                                            (string-trim (buffer-string)))))
            (with-current-buffer buffer
              (let ((inhibit-read-only t) (requested-width my-tui-ink-width)
                    (sidebar my-tui-ink-sidebar-buffer)
                    (sidebar-visible my-tui-ink-sidebar-visible))
                (erase-buffer)
                (remove-overlays)
                (my-tui-ink-preview-mode)
                (setq-local my-tui-ink-source-file file
                            my-tui-ink-width requested-width
                            my-tui-ink-sidebar-buffer sidebar
                            my-tui-ink-sidebar-visible sidebar-visible
                            my-tui-ink-backend (if native 'emacs-sexp 'ansi)
                            default-directory (file-name-directory file))
                (when-let* ((face (alist-get my-tui-ink-theme my-tui-ink-buffer-faces
                                              nil nil #'string=)))
                  (face-remap-add-relative 'default face))
                (if data
                    (progn (insert rendered)
                           (setq-local my-tui-ink-headings (plist-get data :headings)
                                       my-tui-ink-code-blocks (plist-get data :code-blocks)))
                  (insert-buffer-substring raw)
                  (ansi-osc-apply-on-region (point-min) (point-max))
                  (ansi-color-apply-on-region (point-min) (point-max)))
                (goto-char (point-min))
                (set-buffer-modified-p nil)))))
      (when (buffer-live-p raw) (kill-buffer raw))
      (delete-file stderr))))


;; Ink：目录 buffer 的创建、更新与当前章节高亮

(defun my-tui-ink-sidebar-hide ()
  "Remove only the sidebar belonging to the current preview."
  (when (buffer-live-p my-tui-ink-sidebar-buffer)
    (dolist (window (get-buffer-window-list my-tui-ink-sidebar-buffer nil t))
      (delete-window window))))

(defun my-tui-ink-sidebar-cleanup ()
  "Dispose of the contents buffer when its preview is killed."
  (my-tui-ink-sidebar-hide)
  (when (buffer-live-p my-tui-ink-sidebar-buffer)
    (kill-buffer my-tui-ink-sidebar-buffer)))

(defun my-tui-ink-sidebar-update ()
  "Rebuild the current preview's sidebar after rendering."
  (when (buffer-live-p my-tui-ink-sidebar-buffer)
    (let* ((owner (current-buffer)) (headings my-tui-ink-headings)
           (window (get-buffer-window my-tui-ink-sidebar-buffer))
           (width (max 4 (1- (if window (window-body-width window)
                               my-tui-ink-sidebar-width)))))
      (with-current-buffer my-tui-ink-sidebar-buffer
        (let ((inhibit-read-only t))
          (erase-buffer)
          (remove-overlays)
          (my-tui-ink-sidebar-mode)
          (setq-local my-tui-ink-sidebar-owner owner
                      my-tui-ink-sidebar-highlight (make-overlay (point-min) (point-min)))
          (overlay-put my-tui-ink-sidebar-highlight 'face 'highlight)
          (cl-loop for h across (or headings []) for index from 0 do
                   (let ((start (point)))
                     (insert (truncate-string-to-width
                              (concat (make-string (+ 2 (* 2 (1- (nth 1 h)))) ?\s)
                                      (replace-regexp-in-string "[\n\r]" " " (nth 2 h)))
                              width nil nil "…") "\n")
                     (put-text-property start (point) 'my-tui-ink-heading-index index)
                     (make-text-button start (1- (point))
                                       'face (intern (format "my-tui-ink-heading-%d" (nth 1 h)))
                                       'follow-link t 'help-echo (nth 2 h)
                                       'action #'my-tui-ink-sidebar-visit)))
          (goto-char (point-min))
          (set-buffer-modified-p nil))))))

(defun my-tui-ink-sidebar-sync ()
  "Highlight the heading containing point without selecting the sidebar."
  (when (and (buffer-live-p my-tui-ink-sidebar-buffer)
             (> (length my-tui-ink-headings) 0))
    (let ((index 0) (offset (1- (point)))
          (sidebar my-tui-ink-sidebar-buffer))
      (cl-loop for h across my-tui-ink-headings for n from 0
               when (<= (car h) offset) do (setq index n))
      (with-current-buffer sidebar
        (when (overlayp my-tui-ink-sidebar-highlight)
          (save-excursion
            (goto-char (point-min))
            (forward-line index)
            (move-overlay my-tui-ink-sidebar-highlight
                          (line-beginning-position) (line-end-position))
            (when-let* ((window (get-buffer-window sidebar)))
              (set-window-point window (point))
              (unless (pos-visible-in-window-p (point) window)
                (set-window-start window (line-beginning-position))))))))))

(defun my-tui-ink-sidebar-show ()
  "Display a contents sidebar on the left while retaining reading focus."
  (unless (> (length my-tui-ink-headings) 0)
    (user-error "No headings; structured Ink preview is required"))
  (unless (buffer-live-p my-tui-ink-sidebar-buffer)
    (setq-local my-tui-ink-sidebar-buffer
                (get-buffer-create (format " *Contents: %s*" (buffer-name)))))
  (my-tui-ink-sidebar-update)
  (display-buffer-in-side-window
   my-tui-ink-sidebar-buffer
   `((side . left) (slot . -1)
     (window-width . ,(min my-tui-ink-sidebar-width
                          (max 16 (/ (frame-width) 3))))
     (window-parameters . ((no-delete-other-windows . t)))))
  (my-tui-ink-sidebar-sync))


;; Ink：窗口生命周期：切换 buffer 时显示或隐藏目录

(defun my-tui-ink-sync-visible-windows (&rest _)
  "Tie the contents sidebar to the active Ink document."
  (unless my-tui-ink-syncing-windows
    (let ((my-tui-ink-syncing-windows t))
      (dolist (frame (frame-list))
        (let* ((selected (frame-selected-window frame))
               (reading-window (if (window-minibuffer-p selected)
                                   (or (minibuffer-selected-window) selected) selected))
               (buffer (window-buffer reading-window))
               (owner (with-current-buffer buffer
                        (if (derived-mode-p 'my-tui-ink-preview-mode)
                            buffer my-tui-ink-sidebar-owner)))
               (document-window
                (and (buffer-live-p owner)
                     (cl-find-if (lambda (w)
                                   (and (eq (window-buffer w) owner)
                                        (not (window-parameter w 'window-side))))
                                 (window-list frame)))))
          ;; A side window belongs to one document, never to arbitrary files
          ;; subsequently displayed in its original reading window.
          (dolist (window (window-list frame))
            (when (window-live-p window)
              (let ((old-owner (buffer-local-value 'my-tui-ink-sidebar-owner
                                                   (window-buffer window))))
                (when (and (buffer-live-p old-owner)
                           (or (not (eq old-owner owner)) (not document-window)))
                  (with-current-buffer old-owner
                    (my-tui-ink-sidebar-hide))))))
          (when document-window
            (with-selected-window document-window
              (when (and my-tui-ink-sidebar-visible
                         (> (length my-tui-ink-headings) 0)
                         (not (and (buffer-live-p my-tui-ink-sidebar-buffer)
                                   (get-buffer-window my-tui-ink-sidebar-buffer frame))))
                (my-tui-ink-sidebar-show)
                (my-tui-ink-refresh)))))))))


;; Ink：阅读命令：打开、刷新、宽度、链接与源码跳转

(defun my-tui-ink-window-width ()
  "Return the available Ink width, reserving the terminal's final column."
  (max 20 (min 1000 (1- (window-body-width)))))

(defun my-tui-ink-effective-width ()
  "Use the requested width as a ceiling within the document window."
  (min (or my-tui-ink-width 1000) (my-tui-ink-window-width)))

(defun my-tui-ink-set-width (width)
  "Rerender the preview at WIDTH columns; retain it on subsequent refreshes."
  (interactive (list (read-number "Ink width (20–1000): "
                                  (or my-tui-ink-width (my-tui-ink-window-width)))))
  (unless (and (integerp width) (<= 20 width 1000))
    (user-error "Ink width must be an integer between 20 and 1000"))
  (let ((old my-tui-ink-width))
    (setq-local my-tui-ink-width width)
    (condition-case err (my-tui-ink-refresh)
      (error (setq-local my-tui-ink-width old) (signal (car err) (cdr err))))))

(defun my-tui-ink-refresh ()
  "Rerender the current Ink preview for the selected window width."
  (interactive)
  (unless (and my-tui-ink-source-file
               (file-readable-p my-tui-ink-source-file))
    (user-error "The Ink source file is no longer readable"))
  (when-let* ((source (find-buffer-visiting my-tui-ink-source-file)))
    (when (buffer-modified-p source)
      (user-error "Save the Markdown source before refreshing its Ink preview")))
  (let ((line (line-number-at-pos))
        (width (my-tui-ink-effective-width)))
    (my-tui-ink-render my-tui-ink-source-file (current-buffer) width)
    (forward-line (1- line))
    (my-tui-ink-sidebar-update)
    (my-tui-ink-sidebar-sync)))

(defun my-tui-markdown-open-in-ink ()
  "Render the current saved Markdown file in a reusable Ink buffer."
  (interactive)
  (unless (and buffer-file-name (file-readable-p buffer-file-name))
    (user-error "The current buffer is not visiting a readable file"))
  (when (buffer-modified-p)
    (user-error "Save the Markdown source before opening its Ink preview"))
  (let* ((file (file-truename buffer-file-name))
         (preview (get-buffer-create (my-tui-ink-preview-buffer-name file)))
         (width (with-current-buffer preview (my-tui-ink-effective-width))))
    (my-tui-ink-render file preview width)
    (pop-to-buffer-same-window preview)
    (when (and my-tui-ink-sidebar-visible (> (length my-tui-ink-headings) 0))
      (my-tui-ink-sidebar-show)
      (my-tui-ink-refresh))))

(defun my-tui-ink-follow-link (button)
  "Follow a document link BUTTON, resolving internal anchors locally."
  (let ((url (button-get button 'browse-url-data)))
    (cond
     ((string-prefix-p "#" url)
      (let ((heading (cl-find (substring url 1) my-tui-ink-headings
                              :key (lambda (h) (nth 3 h)) :test #'equal)))
        (unless heading (user-error "Heading not found: %s" url))
        (goto-char (1+ (car heading)))))
     ((string-match-p "\\`https?://" url) (browse-url url))
     ((not (string-match-p "\\`[[:alpha:]][[:alnum:]+.-]*:" url))
      (let ((file (expand-file-name (car (split-string url "#")) default-directory)))
        (if (file-readable-p file) (find-file file) (user-error "File not found: %s" file))))
     (t (browse-url url)))))

(defun my-tui-ink-view-source ()
  "Return to the Markdown source, at the nearest preceding heading."
  (interactive)
  (let* ((file my-tui-ink-source-file) (offset (1- (point)))
         (headings (cl-loop for h across (or my-tui-ink-headings [])
                            when (<= (car h) offset) collect h))
         (line (nth 4 (car (last headings)))))
    (find-file file)
    (when line (goto-char (point-min)) (forward-line (1- line)))))

(defun my-tui-ink-sidebar-visit (&optional button)
  "Jump to the sidebar heading at point or BUTTON and focus the document."
  (interactive)
  (let* ((index (get-text-property (if button (button-start button)
                                    (line-beginning-position)) 'my-tui-ink-heading-index))
         (owner my-tui-ink-sidebar-owner)
         (window (and (buffer-live-p owner) (get-buffer-window owner))))
    (unless (and (integerp index) window) (user-error "Preview is no longer displayed"))
    (select-window window)
    (goto-char (1+ (car (aref my-tui-ink-headings index))))
    (recenter 2)
    (my-tui-ink-sidebar-sync)))

(defun my-tui-ink-toc ()
  "Toggle the contents sidebar for the current Markdown preview."
  (interactive)
  (let* ((owner (if (derived-mode-p 'my-tui-ink-sidebar-mode)
                    my-tui-ink-sidebar-owner (current-buffer)))
         (window (and (buffer-live-p owner) (get-buffer-window owner))))
    (unless window (user-error "Preview is no longer displayed"))
    (select-window window)
    (if (and (buffer-live-p my-tui-ink-sidebar-buffer)
             (get-buffer-window my-tui-ink-sidebar-buffer))
        (progn (setq-local my-tui-ink-sidebar-visible nil) (my-tui-ink-sidebar-hide))
      (my-tui-ink-sidebar-show)
      (setq-local my-tui-ink-sidebar-visible t))
    (my-tui-ink-refresh)))

(defun my-tui-ink-quit ()
  "Close the preview and its sidebar, preserving other windows."
  (interactive)
  (my-tui-ink-sidebar-hide)
  (quit-window))

(defun my-tui-ink-sidebar-close ()
  "Hide contents and return focus to the document."
  (interactive)
  (my-tui-ink-toc))


;; Ink：快捷键、窗口事件 hook 与 Markdown 入口

(add-hook 'window-buffer-change-functions #'my-tui-ink-sync-visible-windows)

(add-hook 'window-selection-change-functions #'my-tui-ink-sync-visible-windows)

(add-hook 'post-command-hook #'my-tui-ink-sync-visible-windows)

(define-key my-tui-ink-sidebar-mode-map (kbd "RET") #'my-tui-ink-sidebar-visit)

(define-key my-tui-ink-sidebar-mode-map (kbd "t") #'my-tui-ink-toc)

(define-key my-tui-ink-sidebar-mode-map (kbd "q") #'my-tui-ink-sidebar-close)

(define-key my-tui-ink-sidebar-mode-map (kbd "n") #'next-line)

(define-key my-tui-ink-sidebar-mode-map (kbd "p") #'previous-line)

(define-key my-tui-ink-preview-mode-map (kbd "g") #'my-tui-ink-refresh)

(define-key my-tui-ink-preview-mode-map (kbd "q") #'my-tui-ink-quit)

(define-key my-tui-ink-preview-mode-map (kbd "t") #'my-tui-ink-toc)

(define-key my-tui-ink-preview-mode-map (kbd "w") #'my-tui-ink-set-width)

(define-key my-tui-ink-preview-mode-map (kbd "s") #'my-tui-ink-view-source)

(define-key my-tui-ink-preview-mode-map (kbd "TAB") #'forward-button)

(define-key my-tui-ink-preview-mode-map (kbd "<backtab>") #'backward-button)

(when (require 'markdown-mode nil t)
  (define-key markdown-mode-map (kbd "C-c i") #'my-tui-markdown-open-in-ink)
  (add-to-list 'auto-mode-alist '("\\.md\\'" . markdown-mode)))


;; 其他文件类型关联

(when (require 'yaml-mode nil t)
  (add-to-list 'auto-mode-alist '("\\.ya?ml\\'" . yaml-mode)))
(when (require 'rust-mode nil t)
  (add-to-list 'auto-mode-alist '("\\.rs\\'" . rust-mode)))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 07. 阅读窗口与临时窗口管理
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun my-toggle-follow-view ()
  "Toggle a two-column Follow mode reading view in the selected frame.
Enabling the view replaces the current layout with two side-by-side windows
showing the current buffer.  Disabling it keeps the selected window's buffer
and point, turns off Follow mode in the original buffer, and returns to one
window."
  (interactive)
  (let* ((frame (selected-frame))
         (follow-buffer
          (frame-parameter frame 'my-follow-view-buffer)))
    (if follow-buffer
        (progn
          (when (buffer-live-p follow-buffer)
            (with-current-buffer follow-buffer
              (when follow-mode
                (follow-mode -1))))
          (set-frame-parameter frame 'my-follow-view-buffer nil)
          (delete-other-windows))
      (let ((buffer (current-buffer)))
        (delete-other-windows)
        (split-window-right)
        (balance-windows)
        (condition-case error
            (progn
              (follow-mode 1)
              (set-frame-parameter
               frame 'my-follow-view-buffer buffer))
          (error
           (delete-other-windows)
           (signal (car error) (cdr error))))))))

(define-key global-map (kbd "C-c f") #'my-toggle-follow-view)

;; Popwin close annoying windows
;; --- 增强版极简 Popwin (支持正则匹配) ---
(defvar my-minimal-popwin-buffers
  '("*Help*" "*Completions*" "*compilation*" "*grep*" "*Occur*" "*Apropos*" "*Messages*"
    help-mode compilation-mode grep-mode occur-mode)
  "精确匹配的缓冲区名称（字符串）或主要模式（符号）。")

(defvar my-minimal-popwin-regexps
  '("^\\*lsp-bridge-")
  "正则表达式列表。匹配到的缓冲区窗口将在按 C-g 时关闭。")

(defun my-minimal-popwin-close-annoying-windows (&rest _args)
  "自动关闭显示在配置列表或正则匹配中的窗口。"
  (interactive)
  (let ((found-any nil))
    (dolist (win (window-list))
      (let* ((buf (window-buffer win))
             (buf-name (buffer-name buf)))
        (when (and (not (one-window-p)) ; 确保不关闭最后一个窗口
                   (or (member buf-name my-minimal-popwin-buffers) ; 精确名称匹配
                       (cl-some (lambda (rx) (string-match-p rx buf-name)) ; 正则表达式匹配
                                my-minimal-popwin-regexps)
                       (with-current-buffer buf ; Major Mode 匹配
                         (cl-some (lambda (m) (and (symbolp m) (derived-mode-p m)))
                                  my-minimal-popwin-buffers))))
          (delete-window win)
          (setq found-any t))))
    found-any))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 08. Shell 清屏辅助
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Shell clear functions
(defun eshell-clear ()
  "Clear terminal"
  (interactive)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (eshell-send-input)))

(defun clear-shell ()
  "Clear terminal"
  (interactive)
  (let ((comint-buffer-maximum-size 0))
    (comint-truncate-buffer)))

;; Hooks for shell clear. shell-mode already runs comint-mode-hook.
(add-hook 'eshell-mode-hook (lambda ()
                              (local-set-key (kbd "C-l") 'eshell-clear)))
(add-hook 'comint-mode-hook (lambda ()
                              (local-set-key (kbd "C-l") 'clear-shell)))
(add-hook 'term-mode-hook (lambda ()
                            (local-set-key (kbd "C-l") 'clear-shell)))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 09. 语言模式、Tree-sitter 与 LSP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Keep traditional syntax highlighting. Parsers only support indent scopes.
(require 'treesit)
(dolist (source '((python "https://github.com/tree-sitter/tree-sitter-python" "v0.23.6")
                  (cpp "https://github.com/tree-sitter/tree-sitter-cpp" "v0.23.4")
                  (go "https://github.com/tree-sitter/tree-sitter-go" "v0.23.4")
                  (rust "https://github.com/tree-sitter/tree-sitter-rust" "v0.23.2")
                  (yaml "https://github.com/tree-sitter-grammars/tree-sitter-yaml" "v0.7.0")
                  (json "https://github.com/tree-sitter/tree-sitter-json" "v0.24.8")))
  (unless (assoc (car source) treesit-language-source-alist)
    (add-to-list 'treesit-language-source-alist source)))
(when (require 'go-mode nil t)
  (add-to-list 'auto-mode-alist '("\\.go\\'" . go-mode)))
(add-to-list 'auto-mode-alist '("\\.json\\'" . js-json-mode))

(defun my-tui-treesit-structure ()
  "Create a parser for indent-bars without enabling Tree-sitter font lock."
  (let ((language (cond ((derived-mode-p 'python-mode) 'python)
                        ((derived-mode-p 'c++-mode) 'cpp)
                        ((derived-mode-p 'go-mode) 'go)
                        ((derived-mode-p 'rust-mode) 'rust)
                        ((derived-mode-p 'yaml-mode) 'yaml)
                        ((derived-mode-p 'js-json-mode) 'json))))
    (when (and language (treesit-ready-p language t))
      (treesit-parser-create language))))
;; Run before indent-bars so it can discover the parser in traditional modes.
(add-hook 'prog-mode-hook #'my-tui-treesit-structure -90)
(add-hook 'yaml-mode-hook #'my-tui-treesit-structure -90)

;; LSP Bridge is the code completion and language-service client.
(require 'lsp-config)
(global-set-key (kbd "M-.") #'my-tui-lsp-definition)
(global-set-key (kbd "M->") #'my-tui-lsp-back)
(global-set-key (kbd "C-c C-d") #'my-tui-lsp-documentation)

;; Reuse the original complete LSP, Projectile and Toggle menus.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 10. Hydra 操作菜单与快捷键优先级
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun my-hydra-toggle-git-markers ()
  "Toggle the configured Git change indicators."
  (interactive)
  (if (fboundp 'diff-hl-mode) (call-interactively #'diff-hl-mode)
    (user-error "Install the TUI packages to enable diff-hl")))

(defun my-hydra-toggle-window-zoom ()
  "Maximize this terminal editing window, or restore the previous layout."
  (interactive)
  (let* ((frame (selected-frame))
         (saved (frame-parameter frame 'my-hydra-window-configuration)))
    (if saved
        (progn
          (set-window-configuration saved)
          (set-frame-parameter frame 'my-hydra-window-configuration nil))
      (set-frame-parameter frame 'my-hydra-window-configuration
                           (current-window-configuration))
      (delete-other-windows))))

(defun my-hydra-external-format ()
  "Run the configured manual external formatter."
  (interactive)
  (call-interactively #'my-tui-format-all-buffer))

(when (require 'hydra nil t)
  (with-eval-after-load 'lsp-bridge (require 'lsp-bridge-imenu))
  (setq ispell-program-name (or (executable-find "aspell")
                               (executable-find "hunspell") "ispell"))

;; LSP Bridge 菜单
(defhydra hydra-lsp-bridge (:color teal :hint nil)
  "
  ^Navigation^             ^Refactoring^       ^Support^           ^Hierarchy/Project^
  ^──────────^             ^───────────^       ^───────^           ^─────────────────^
  _d_: Definition          _r_: Rename         _h_: Documentation  _I_: Call Hierarchy (In)
  _D_: Def (Other Window)  _a_: Code Action    _p_: Peek           _O_: Call Hierarchy (Out)
  _i_: Implementation      _f_: Format         _e_: Diagnostics    _s_: Workspace Symbols
  _t_: Type Definition     _F_: External fmt  _n_: Next Error     _l_: Imenu
  _u_: References          ^ ^                 _m_: Prev Error     _R_: Restart LSP
  _b_: Return              ^ ^                 ^ ^                 ^ ^
  "
  ("d" lsp-bridge-find-def)
  ("D" lsp-bridge-find-def-other-window)
  ("i" lsp-bridge-find-impl)
  ("t" lsp-bridge-find-type-def)
  ("u" lsp-bridge-find-references)
  ("b" lsp-bridge-find-def-return)
  ("r" lsp-bridge-rename)
  ("a" lsp-bridge-code-action)
  ("f" lsp-bridge-code-format)
  ("F" my-hydra-external-format)
  ("h" lsp-bridge-popup-documentation)
  ("p" lsp-bridge-peek)
  ("e" lsp-bridge-diagnostic-list)
  ("n" lsp-bridge-diagnostic-jump-next)
  ("m" lsp-bridge-diagnostic-jump-prev)
  ("I" lsp-bridge-incoming-call-hierarchy)
  ("O" lsp-bridge-outgoing-call-hierarchy)
  ("s" lsp-bridge-workspace-list-symbol-at-point)
  ("l" lsp-bridge-imenu)
  ("R" lsp-bridge-restart-process)
  ("q" nil "Exit" :color blue))

;; Projectile 菜单
(defhydra hydra-projectile (:color teal :hint nil)
  "
  Project: %(if (projectile-project-p) (projectile-project-root) \"Not in project\")

  ^Find^               ^Search/Replace^    ^Buffers^           ^Projects^          ^Cache^
  ^────^               ^──────────────^    ^───────^           ^────────^          ^─────^
  _f_: File            _s_: ag             _b_: Switch         _p_: Switch         _i_: Invalidate
  _r_: Recent Files    _g_: grep           _K_: Kill All       _D_: Root           _z_: Cache Current
  _d_: Directory       _R_: Replace        _S_: Save All       _T_: Test           _x_: Remove Known
  _o_: Other Window    _A_: ag             ^ ^                 ^ ^                 ^ ^
  "
  ("f" helm-projectile-find-file)
  ("r" helm-projectile-recentf)
  ("d" helm-projectile-find-dir)
  ("o" projectile-find-file-other-window)
  ("s" projectile-ag)
  ("g" projectile-grep)
  ("R" projectile-replace)
  ("A" helm-projectile-ag)
  ("b" helm-projectile-switch-to-buffer)
  ("K" projectile-kill-buffers)
  ("S" projectile-save-project-buffers)
  ("p" helm-projectile-switch-project)
  ("D" projectile-dired)
  ("T" projectile-test-project)
  ("i" projectile-invalidate-cache)
  ("z" projectile-cache-current-file)
  ("x" projectile-remove-known-project)
  ("q" nil "Exit" :color blue))

(when (featurep 'helm-projectile)
  (define-key global-map (kbd "C-c C-p") #'hydra-projectile/body))
(define-key global-map (kbd "C-c C-l") #'hydra-lsp-bridge/body)

;; 界面与模式开关菜单
(defhydra hydra-toggle (:color pink :hint nil)
  "
  ^Interface^            ^Buffer^             ^Mode^
  ^---------^            ^------^             ^----^
  _l_: Line Numbers      _t_: Truncate Lines  _r_: Read-Only
  _F_: Maximize/Restore  _w_: Whitespace      _f_: Follow Mode
  _m_: Menu Bar          _W_: Word Wrap       _s_: Flyspell
  ^ ^                    _z_: Resize Window   _g_: Git Markers
      "
  ("l" display-line-numbers-mode)
  ("F" my-hydra-toggle-window-zoom)
  ("m" menu-bar-mode)
  ("t" toggle-truncate-lines)
  ("w" whitespace-mode)
  ("W" visual-line-mode)
  ("z" hydra-zoom/body :exit t)
  ("r" read-only-mode)
  ("f" follow-mode)
  ("s" flyspell-mode)
  ("g" my-hydra-toggle-git-markers)
  ("q" nil "cancel" :color blue))

(defhydra hydra-zoom (:color red :hint nil)
  "Window: _+_ taller  _-_ shorter  _0_ balance  _b_ back  _q_ quit"
  ("+" enlarge-window)
  ("-" shrink-window)
  ("0" balance-windows :color blue)
  ("q" nil "quit" :color blue)
  ("b" hydra-toggle/body "back" :exit t))

(define-key global-map (kbd "C-c t") #'hydra-toggle/body)
;; Refresh maps in existing programming buffers when this file is reloaded.
(when (boundp 'my-tui-programming-shortcuts-map)
  (dolist (key '("C-c C-l" "C-c C-p" "C-c t"))
    (define-key my-tui-programming-shortcuts-map (kbd key)
                (lookup-key global-map (kbd key))))))


;; Programming modes have their own C-c C-p/C-l bindings. Give the configured
;; project/LSP commands precedence there, while leaving Org and shells alone.
(defvar my-tui-programming-shortcuts-map
  (let ((map (make-sparse-keymap)))
    (dolist (key '("C-c C-p" "C-c C-l" "C-c t" "C-c C-d" "C-c C-j" "C-c C-o"
                   "C-<return>"))
      (when-let* ((binding (lookup-key global-map (kbd key))))
        (define-key map (kbd key) binding)))
    map)
  "Project and language shortcuts shared by programming modes.")
(define-minor-mode my-tui-programming-shortcuts-mode
  "Use the configured project and language shortcuts in programming buffers."
  :lighter nil :keymap my-tui-programming-shortcuts-map)
(add-hook 'prog-mode-hook #'my-tui-programming-shortcuts-mode)
(add-hook 'yaml-ts-mode-hook #'my-tui-programming-shortcuts-mode)
(add-hook 'yaml-mode-hook #'my-tui-programming-shortcuts-mode)

(with-eval-after-load 'python
  (define-key python-mode-map (kbd "C-c C-p") nil)
  (when (boundp 'python-ts-mode-map)
    (define-key python-ts-mode-map (kbd "C-c C-p") nil)))

(with-eval-after-load 'org
  ;; Preserve the terminal-wide mark binding; all Org presentation settings
  ;; intentionally remain at their built-in defaults.
  (define-key org-mode-map (kbd "C-<return>") #'set-mark-command))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 11. 编辑、帮助与导航增强
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(when (require 'which-key nil t)
  (setq which-key-idle-delay 0.5)
  (which-key-mode 1))

(defun my-tui-extra-completion-sources ()
  "Add file and buffer-word completion without replacing the LSP source."
  (when (featurep 'cape)
    (add-hook 'completion-at-point-functions #'cape-file nil t)
    (add-hook 'completion-at-point-functions #'cape-dabbrev t t)))

(when (require 'cape nil t)
  (add-hook 'prog-mode-hook #'my-tui-extra-completion-sources)
  (add-hook 'text-mode-hook #'my-tui-extra-completion-sources))

(when (require 'helpful nil t)
  (global-set-key (kbd "C-h f") #'helpful-callable)
  (global-set-key (kbd "C-h v") #'helpful-variable)
  (global-set-key (kbd "C-h k") #'helpful-key)
  (global-set-key (kbd "C-h x") #'helpful-command))

(when (require 'diff-hl nil t)
  (require 'diff-hl-margin)
  (diff-hl-margin-mode 1)
  (global-diff-hl-mode 1)
  (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))

(when (require 'indent-bars nil t)
  (setq indent-bars-prefer-character t
        indent-bars-no-stipple-char ?│
        indent-bars-depth-update-delay 0.1
        indent-bars-highlight-current-depth '(:blend 1.0)
        indent-bars-treesit-support t)
  (require 'indent-bars-ts)
  (add-to-list 'indent-bars-treesit-scope '(python function_definition class_definition))
  (add-to-list 'indent-bars-treesit-scope
               '(cpp function_definition class_specifier namespace_definition))
  (add-to-list 'indent-bars-treesit-scope '(go function_declaration method_declaration type_declaration))
  (add-to-list 'indent-bars-treesit-scope '(rust function_item impl_item struct_item enum_item mod_item))
  (add-to-list 'indent-bars-treesit-scope '(yaml block_mapping block_sequence))
  (add-to-list 'indent-bars-treesit-scope '(json object array))
  (add-hook 'prog-mode-hook #'indent-bars-mode)
  (add-hook 'yaml-mode-hook #'indent-bars-mode)
  (add-hook 'yaml-ts-mode-hook #'indent-bars-mode))

(when (require 'avy nil t)
  (global-set-key (kbd "C-c j") #'avy-goto-char-timer)
  (global-set-key (kbd "C-c J") #'avy-goto-line))

(when (require 'vundo nil t)
  (setq vundo-glyph-alist vundo-ascii-symbols)
  (global-set-key (kbd "C-x u") #'vundo))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 12. 阅读界面、modeline、折叠与 Breadcrumb
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Keep C-g's normal quit behavior, while closing named temporary windows.
(add-to-list 'my-minimal-popwin-buffers 'helpful-mode)
(advice-add 'keyboard-quit :before #'my-minimal-popwin-close-annoying-windows)

(defvar helm-source-buffers-list)

(defun my-helm-buffers-list-with-preview (original &rest arguments)
  "Enable follow previews for ORIGINAL and restore its source afterward."
  (require 'helm-buffers)
  (unless helm-source-buffers-list
    (setq helm-source-buffers-list (helm-make-source "Buffers" 'helm-source-buffers)))
  (let ((follow (helm-get-attr 'follow helm-source-buffers-list)))
    (unwind-protect
        (progn
          (helm-set-attr 'follow 1 helm-source-buffers-list)
          (apply original arguments))
      (helm-set-attr 'follow follow helm-source-buffers-list))))

(with-eval-after-load 'helm
  (advice-add 'helm-buffers-list :around #'my-helm-buffers-list-with-preview))

;; Keep the modeline lightweight while showing file-type Nerd Font icons.
;; The terminal client owns glyph rendering.
(setq doom-modeline-icon t
      doom-modeline-major-mode-icon t
      doom-modeline-major-mode-color-icon t
      doom-modeline-vcs-max-length 50
      doom-modeline-time nil
      doom-modeline-indent-info t
      doom-modeline-env-version nil
      doom-modeline-minor-modes nil
      doom-modeline-enable-word-count nil)

(when (require 'doom-modeline nil t)
  (doom-modeline-mode 1))

(defun my-tui-enable-code-folding ()
  "Enable folding from the existing parser, keeping traditional font lock."
  (when (and (featurep 'treesit-fold) (treesit-parser-list)
             (treesit-fold-usable-mode-p))
    (treesit-fold-mode 1)))

(defun my-tui-fold-braced-body (node offset)
  "Fold NODE's braced body while leaving the declaration header visible."
  (when-let* ((body (treesit-node-child-by-field-name node "body")))
    (treesit-fold-range-seq body offset)))

(when (require 'treesit-fold nil t)
  ;; The package supports traditional modes; builtin JSON mode needs this alias.
  (setf (alist-get 'js-json-mode treesit-fold-range-alist)
        (alist-get 'json-ts-mode treesit-fold-range-alist))
  ;; Also allow folding at declaration names, rather than requiring the
  ;; cursor to be inside the braces supported by the package's default rules.
  (dolist (entry '((c++-mode namespace_definition function_definition class_specifier struct_specifier)
                  (go-mode function_declaration method_declaration)
                  (rust-mode function_item impl_item mod_item)))
    (dolist (node-type (cdr entry))
      (unless (alist-get node-type (alist-get (car entry) treesit-fold-range-alist))
        (push (cons node-type #'my-tui-fold-braced-body)
              (alist-get (car entry) treesit-fold-range-alist)))))
  (setq treesit-fold-line-count-show t
        treesit-fold-line-count-format " ... %d lines ... ")
  (add-hook 'prog-mode-hook #'my-tui-enable-code-folding 95)
  (add-hook 'yaml-mode-hook #'my-tui-enable-code-folding 95)
  (define-key global-map (kbd "C-c C--") #'treesit-fold-toggle)
  (define-key global-map (kbd "C-c -") #'treesit-fold-toggle)
  (define-key global-map (kbd "C-c u") #'treesit-fold-open-all))

(defun my-tui-enable-breadcrumb ()
  "Attach a text breadcrumb once this buffer has an active language server."
  (when (and (bound-and-true-p lsp-bridge-mode) (lsp-bridge-call-file-api-p)
             (not (member '(:eval (lsp-bridge-breadcrumb--header-line)) header-line-format)))
    ;; lsp-bridge-mode is enabled before the asynchronous server has started.
    (setq-local lsp-bridge-breadcrumb-mode nil)
    (lsp-bridge-breadcrumb-mode 1)))

(with-eval-after-load 'lsp-bridge
  (setq lsp-bridge-breadcrumb-show-icon nil)
  (add-hook 'lsp-bridge-diagnostic-update-hook #'my-tui-enable-breadcrumb)
  (add-hook 'lsp-bridge-mode-hook #'my-tui-enable-breadcrumb)
  (define-key global-map (kbd "M-/") #'my-tui-lsp-references))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 13. 终端集成：vterm、Eat 与颜色
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun my-tui-terminal-toggle ()
  "Toggle vterm in the current directory, using Eshell if vterm is absent."
  (interactive)
  (if (and (locate-library "vterm") (require 'vterm-toggle nil t))
      (vterm-toggle-cd)
    (my-tui-shell)))

(when (locate-library "vterm")
  ;; Loading vterm also loads its native module. Defer this until requested,
  ;; so a fresh checkout can start before the module has been built.
  (autoload 'vterm "vterm" nil t)
  (global-set-key (kbd "C-c v") #'vterm))

(defconst my-tui-vterm-ansi-face-map
  '((vterm-color-black . ansi-color-black)
    (vterm-color-red . ansi-color-red)
    (vterm-color-green . ansi-color-green)
    (vterm-color-yellow . ansi-color-yellow)
    (vterm-color-blue . ansi-color-blue)
    (vterm-color-magenta . ansi-color-magenta)
    (vterm-color-cyan . ansi-color-cyan)
    (vterm-color-white . ansi-color-white)
    (vterm-color-bright-black . ansi-color-black)
    (vterm-color-bright-red . ansi-color-red)
    (vterm-color-bright-green . ansi-color-green)
    (vterm-color-bright-yellow . ansi-color-yellow)
    (vterm-color-bright-blue . ansi-color-blue)
    (vterm-color-bright-magenta . ansi-color-magenta)
    (vterm-color-bright-cyan . ansi-color-cyan)
    (vterm-color-bright-white . ansi-color-white))
  "Map vterm's cell palette to the active mood-one ANSI faces.")

(defun my-tui-vterm-use-ansi-palette ()
  "Make vterm inherit the same ANSI palette and brightness as Ink."
  (dolist (entry my-tui-vterm-ansi-face-map)
    (set-face-attribute (car entry) nil
                        :inherit (cdr entry)
                        :foreground 'unspecified
                        :background 'unspecified)))

(with-eval-after-load 'vterm
  (setq vterm-max-scrollback 10000)
  (my-tui-vterm-use-ansi-palette)
  (define-key vterm-mode-map (kbd "C-c C-o") #'my-tui-terminal-toggle)
  (define-key vterm-mode-map (kbd "M-[") #'my-tui-meta-bracket)
  (define-key vterm-mode-map (kbd "C-c b") #'my-tui-buffer-list))

(with-eval-after-load 'vterm-toggle
  (setq vterm-toggle-scope 'project
        vterm-toggle-project-root t
        vterm-toggle-cd-auto-create-buffer t))

(global-set-key (kbd "C-c E") #'my-tui-shell)
(when (locate-library "eat")
  (autoload 'eat "eat" nil t)
  (global-set-key (kbd "C-c e") #'eat)
  (with-eval-after-load 'eshell
    (require 'eat)
    (eat-eshell-mode 1)
    (eat-eshell-visual-command-mode 1)))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 14. Dashboard 启动页
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(when (require 'dashboard nil t)
  (setq dashboard-startup-banner 'ascii
        dashboard-banner-logo-title "Welcome to Emacs!"
        dashboard-center-content nil
        dashboard-show-shortcuts t
        dashboard-set-heading-icons nil
        dashboard-set-file-icons nil
        dashboard-set-navigator t
        dashboard-projects-backend 'projectile
        dashboard-items '((recents . 10) (projects . 8) (bookmarks . 5) (registers . 5))
        dashboard-navigator-buttons
        `(((nil "Config" "Open configuration"
                (lambda (&rest _) (find-file user-init-file)))
           (nil "Projects" "Open project selector"
                (lambda (&rest _) (call-interactively #'projectile-switch-project))))))
  (global-set-key (kbd "C-c h") #'dashboard-open)

  (defun my-tui-dashboard-at-startup ()
    "Show dashboard when startup has not opened an explicit file."
    (unless (or noninteractive (daemonp)
                (cl-some (lambda (buffer)
                           (buffer-local-value 'buffer-file-name buffer))
                         (buffer-list)))
      (dashboard-open)))
  ;; The stock hook skips emacs -nw / --init-directory because it counts all
  ;; command-line arguments. Check visited files after startup instead.
  (add-hook 'emacs-startup-hook #'my-tui-dashboard-at-startup))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 15. 默认只读工作流
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun my-tui-reader-open-file ()
  "Open visited files read-only; C-x C-q enables editing for this buffer."
  (when buffer-file-name (read-only-mode 1)))

(add-hook 'find-file-hook #'my-tui-reader-open-file 90)

(defun my-tui-reader-completion-allowed-p ()
  "Suppress automatic completion while reading a read-only buffer."
  (not buffer-read-only))

(defun my-tui-reader-require-editing (original &rest arguments)
  "Run editing command ORIGINAL only in a writable buffer."
  (when buffer-read-only
    (user-error "Read-only: use C-x C-q or C-c t r to enable editing"))
  (apply original arguments))

(with-eval-after-load 'lsp-bridge
  (add-to-list 'lsp-bridge-completion-popup-predicates
               #'my-tui-reader-completion-allowed-p)
  (advice-add 'lsp-bridge-code-format :around #'my-tui-reader-require-editing)
  (advice-add 'lsp-bridge-rename :around #'my-tui-reader-require-editing))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 16. Daemon 与 emacsclient
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(when (daemonp)
  (require 'server)
  ;; Some terminal queries have no reply over SSH/tmux. The stock 2-second
  ;; timeout can delay a file client by 4 seconds before displaying its buffer.
  (setq xterm-query-timeout 0.2
        server-client-instructions nil
        server-kill-new-buffers nil
        server-stop-automatically nil)
  (let ((directory (expand-file-name ".cache/server/" user-emacs-directory)))
    (make-directory directory t)
    (set-file-modes directory #o700)
    (setq server-socket-dir directory))

  (defun my-tui-client-initial-buffer ()
    "Display Dashboard in terminal clients opened without a filename."
    (if (featurep 'dashboard)
        (progn (dashboard-open) (get-buffer dashboard-buffer-name))
      (get-buffer-create "*scratch*")))
  (setq initial-buffer-choice #'my-tui-client-initial-buffer))

(when (daemonp)
  (defun my-tui-client-file-visited ()
    "Default saved files to reader mode when a client revisits a cached buffer."
    (when (and buffer-file-name (not (buffer-modified-p)))
      (my-tui-reader-open-file)))
  (add-hook 'server-visit-hook #'my-tui-client-file-visited))

;;; Kitty keyboard protocol

;; Emacs 31 does not speak KKP natively; WezTerm already has
;; enable_kitty_keyboard = true, so activate the client side here.
(when (require 'kkp nil t)
  ;; Keep C-g able to interrupt synchronous subprocesses under KKP.
  (setq kkp-restore-legacy-keys-around-subprocesses t)
  (add-hook 'tty-setup-hook #'global-kkp-mode)
  (when (and (not noninteractive) (not (daemonp))
             (eq (framep (selected-frame)) t))
    (global-kkp-mode +1)))

;;; 主题

(let ((theme-dir (expand-file-name "themes/mood-one-theme" user-emacs-directory)))
  (when (file-exists-p (expand-file-name "mood-one-theme.el" theme-dir))
    (add-to-list 'custom-theme-load-path theme-dir)
    (load-theme 'mood-one t)))

(provide 'tui-config)
;;; init.el ends here
