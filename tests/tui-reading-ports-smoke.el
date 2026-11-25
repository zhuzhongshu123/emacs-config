;;; tui-reading-ports-smoke.el --- Ported reader feature checks -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(setq user-emacs-directory
      (file-name-as-directory
       (expand-file-name ".." (file-name-directory load-file-name))))
(load (expand-file-name "early-init.el" user-emacs-directory) nil t)
(cl-letf (((symbol-function 'package-refresh-contents)
           (lambda (&rest _) (error "Unexpected startup archive refresh")))
          ((symbol-function 'package-install)
           (lambda (&rest _) (error "Unexpected startup package install"))))
  (load (expand-file-name "init.el" user-emacs-directory) nil t))

(ert-deftest ports-text-modeline-and-org-defaults ()
  (should doom-modeline-mode)
  (should doom-modeline-icon)
  (should doom-modeline-major-mode-icon)
  (should doom-modeline-major-mode-color-icon)
  (should (= doom-modeline-vcs-max-length 50))
  (should-not doom-modeline-time)
  (should-not display-time-mode)
  (should doom-modeline-indent-info)
  (should (featurep 'nerd-icons))
  (should-not (string-empty-p (nerd-icons-icon-for-file "example.py")))
  (dolist (entry '(("example.py" . #xE73C)
                   ("Main.java" . #xE738)
                   ("lib.rs" . #xE7A8)))
    (should (= (aref (substring-no-properties (nerd-icons-icon-for-file (car entry))) 0)
               (cdr entry))))
  (should-not doom-modeline-env-version)
  (should-not (featurep 'eglot))
  (should-not (featurep 'corfu))
  (with-temp-buffer
    (org-mode)
    (should-not (bound-and-true-p org-modern-mode))
    (should-not face-remapping-alist)
    (should-not line-spacing)
    (should (eq (key-binding (kbd "TAB")) #'org-cycle))
    (should (eq (key-binding (kbd "C-<return>")) #'set-mark-command))))

(ert-deftest ports-vterm-inherits-mood-one-ansi-palette ()
  (when (locate-library "vterm")
    (require 'vterm)
    (dolist (entry my-tui-vterm-ansi-face-map)
      (should (eq (face-attribute (car entry) :inherit nil 'default)
                  (cdr entry))))))

(ert-deftest ports-follow-view-is-read-only-and-reversible ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert (make-string 100 ?x))
      (read-only-mode 1)
      (set-buffer-modified-p nil)
      (my-toggle-follow-view)
      (should (= (length (window-list)) 2))
      (should follow-mode)
      (should (cl-every (lambda (w) (eq (window-buffer w) (current-buffer))) (window-list)))
      (my-toggle-follow-view)
      (should (= (length (window-list)) 1))
      (should-not follow-mode)
      (should buffer-read-only)
      (should-not (buffer-modified-p)))))

(ert-deftest ports-helm-preview-restores-source-on-error ()
  (require 'helm-buffers)
  (let* ((helm-source-buffers-list
          (helm-make-source "Test Buffers" 'helm-source-buffers))
         (original-follow (helm-get-attr 'follow helm-source-buffers-list)))
    (should-error
     (my-helm-buffers-list-with-preview
      (lambda (&rest _)
        (should (= (helm-get-attr 'follow helm-source-buffers-list) 1))
        (error "Simulated preview failure"))))
    (should (equal (helm-get-attr 'follow helm-source-buffers-list)
                   original-follow))))

(ert-deftest ports-ink-preview-keeps-colors-and-links ()
  (let* ((file (make-temp-file
                "tui markdown code " nil ".md"
                (concat "# Example\n\n[Link](https://example.com)\n\n"
                        "```json\n{\"name\": \"demo\", \"enabled\": true}\n```\n")))
         (source (find-file-noselect file))
         (preview-name (my-tui-ink-preview-buffer-name file))
         preview)
    (unwind-protect
        (save-window-excursion
          (switch-to-buffer source)
          (my-tui-markdown-open-in-ink)
          (setq preview (current-buffer))
          (should (derived-mode-p 'my-tui-ink-preview-mode))
          (should buffer-read-only)
          (should (equal my-tui-ink-source-file (file-truename file)))
          ;; Terminal inherits mood-one; Light receives a complete local page
          ;; background rather than leaving isolated white elements on black.
          (should-not (assq 'default face-remapping-alist))
          (should (eq (key-binding (kbd "g")) #'my-tui-ink-refresh))
          (should (eq (key-binding (kbd "q")) #'my-tui-ink-quit))
          (should-not (save-excursion
                        (goto-char (point-min))
                        (search-forward (string 27) nil t)))
          (should (or (text-property-not-all (point-min) (point-max) 'face nil)
                      (cl-some (lambda (overlay) (overlay-get overlay 'face))
                               (overlays-in (point-min) (point-max)))))
          (should
           (cl-loop for position from (point-min) below (point-max)
                    thereis (equal (get-text-property position 'browse-url-data)
                                   "https://example.com")))
          (my-tui-ink-refresh)
          (should (derived-mode-p 'my-tui-ink-preview-mode))
          (let ((my-tui-ink-theme "light"))
            (my-tui-ink-refresh)
            (should (equal (plist-get (cadr (assq 'default face-remapping-alist))
                                      :background)
                           "#ffffff"))
            (should (equal (plist-get (cadr (assq 'default face-remapping-alist))
                                      :foreground)
                           "#24292f"))))
      (when (buffer-live-p source)
        (kill-buffer source))
      (when (buffer-live-p preview) (kill-buffer preview))
      (when (get-buffer preview-name) (kill-buffer preview-name))
      (when (file-exists-p file) (delete-file file)))))

(ert-deftest ports-quit-closes-help-window-without-closing-source ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (delete-other-windows)
      (let ((help (generate-new-buffer " *reader-help*")))
        (unwind-protect
            (progn
              (with-current-buffer help (help-mode))
              (set-window-buffer (split-window-right) help)
              (condition-case nil (keyboard-quit) (quit nil))
              (should (= (length (window-list)) 1))
              (should (eq (window-buffer) (current-buffer))))
          (kill-buffer help))))))

(ert-deftest ports-six-traditional-modes-fold-without-editing ()
  (dolist (entry '((python python-mode "def f():\n    if True:\n        return 1\n" "def")
                   (cpp c++-mode "namespace demo {\n    int f() {\n        return 1;\n    }\n}\n" "namespace")
                   (go go-mode "package demo\nfunc f() int {\n    return 1\n}\n" "func")
                   (rust rust-mode "fn f() -> i32 {\n    return 1;\n}\n" "fn")
                   (yaml yaml-mode "outer:\n  child:\n    key: value\n" "outer")
                   (json js-json-mode "{\n  \"outer\": {\n    \"key\": 1\n  }\n}\n" "{")))
    (should (treesit-ready-p (car entry) t))
    (with-temp-buffer
      (insert (nth 2 entry))
      (funcall (nth 1 entry))
      (should treesit-fold-mode)
      (goto-char (point-min))
      (search-forward (nth 3 entry))
      (backward-char)
      (read-only-mode 1)
      (set-buffer-modified-p nil)
      (treesit-fold-close)
      (ert-info ((format "Fold language: %s" (car entry)))
        (should (cl-some (lambda (o) (eq (overlay-get o 'invisible) 'treesit-fold))
                        (overlays-in (point-min) (point-max)))))
      (treesit-fold-open-all)
      (should-not (cl-some (lambda (o) (eq (overlay-get o 'invisible) 'treesit-fold))
                          (overlays-in (point-min) (point-max))))
      (should (equal (buffer-string) (nth 2 entry)))
      (should-not (buffer-modified-p)))))

(ert-deftest ports-formatting-is-manual-and-requires-editing ()
  (with-temp-buffer
    (insert "x=[1,2,3]\n")
    (python-mode)
    (should-not (bound-and-true-p format-all-mode))
    (should-not (memq 'format-all--buffer-from-hook before-save-hook))
    (read-only-mode 1)
    (should-error (my-tui-format-all-buffer) :type 'user-error)
    (read-only-mode -1)
    (let ((path (getenv "PATH")))
      (my-tui-format-all-buffer)
      (should (equal (getenv "PATH") path)))
    (should (equal (buffer-string) "x = [1, 2, 3]\n"))))

(ert-deftest ports-block-template-survives-lazy-c-mode-loading ()
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (c++-mode)
      (insert "int f()")
      (execute-kbd-macro "{")
      (should (string-match-p "int f(){\n +\n}" (buffer-string))))))

(ert-run-tests-batch-and-exit)
;;; tui-reading-ports-smoke.el ends here
