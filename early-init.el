;;; early-init.el --- Terminal Emacs early initialization -*- lexical-binding: t; -*-

(add-to-list 'load-path (expand-file-name "modules" user-emacs-directory))

;; Startup never requires network access or archive refreshes.
(require 'package)
(setq package-enable-at-startup nil
      native-comp-async-report-warnings-errors 'silent
      package-user-dir (expand-file-name "elpa" user-emacs-directory)
      package-archives
      '(("gnu" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/gnu/")
        ("nongnu" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/nongnu/")
        ("melpa" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/melpa/")))

;;; early-init.el ends here
