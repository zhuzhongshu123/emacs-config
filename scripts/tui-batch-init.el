;;; tui-batch-init.el --- Load the TUI config for installation jobs -*- lexical-binding: t; -*-

;; --batch does not load the user's init file. Load this explicitly when an
;; installer needs my-tui-packages, archive settings or grammar source pins.
(setq user-emacs-directory
      (file-name-as-directory
       (expand-file-name ".." (file-name-directory load-file-name))))
(load (expand-file-name "early-init.el" user-emacs-directory) nil t)
(load (expand-file-name "init.el" user-emacs-directory) nil t)

;;; tui-batch-init.el ends here
