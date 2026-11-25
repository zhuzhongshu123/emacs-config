;;; benchmark_tui_doc.el -*- lexical-binding: t; -*-
(require 'cl-lib)
(require 'json)
(let* ((frame (cl-find-if (lambda (f) (>= (display-color-cells f) 16777216)) (frame-list)))
       (file (or (getenv "BENCH_INPUT")
                 (expand-file-name "benchmark-input.md" user-emacs-directory)))
       (preview (generate-new-buffer " *tui-doc-benchmark*"))
       (sidebar (generate-new-buffer " *tui-doc-benchmark-toc*"))
       (process-fn (symbol-function 'process-file))
       (read-fn (symbol-function 'my-tui-ink-read-document))
       (insert-fn (symbol-function 'my-tui-ink-insert-document))
       (started (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
       samples process-ms read-ms style-ms counts)
  (unwind-protect
      (with-selected-frame frame
        (cl-letf (((symbol-function 'process-file)
                   (lambda (&rest args)
                     (let ((start (float-time)))
                       (prog1 (apply process-fn args)
                         (setq process-ms (+ process-ms (* 1000 (- (float-time) start))))))))
                  ((symbol-function 'my-tui-ink-read-document)
                   (lambda (&rest args)
                     (let ((start (float-time)))
                       (prog1 (apply read-fn args)
                         (setq read-ms (+ read-ms (* 1000 (- (float-time) start))))))))
                  ((symbol-function 'my-tui-ink-insert-document)
                   (lambda (&rest args)
                     (let ((start (float-time)))
                       (prog1 (apply insert-fn args)
                         (setq style-ms (+ style-ms (* 1000 (- (float-time) start)))))))))
          (dotimes (i 4)
            (setq process-ms 0.0 read-ms 0.0 style-ms 0.0)
            (let ((start (float-time)) (gc-start gcs-done) (gc-time gc-elapsed))
              (my-tui-ink-render file preview 160)
              (with-current-buffer preview
                (setq-local my-tui-ink-sidebar-buffer sidebar)
                (my-tui-ink-sidebar-update)
                (my-tui-ink-sidebar-sync)
                (setq counts (list :headings (length my-tui-ink-headings)
                                   :code-blocks (length my-tui-ink-code-blocks)
                                   :buffer-chars (buffer-size)
                                   :readonly buffer-read-only
                                   :native-modeline (and mode-line-format t))))
              (push (list :iteration i :total-ms (* 1000 (- (float-time) start))
                          :ink-process-ms process-ms :protocol-read-ms read-ms :style-fontify-ms style-ms
                          :gc-count (- gcs-done gc-start) :gc-ms (* 1000 (- gc-elapsed gc-time))) samples)
              ;; Keep a receipt after every complete render, even if a later
              ;; attempt is interrupted; no user buffer/window is selected.
              (with-temp-file (or (getenv "BENCH_OUTPUT")
                                  (expand-file-name "benchmark-timing.json"
                                                    user-emacs-directory))
                (insert (json-encode (list :started started :ended (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                                          :file file :width 160 :emacs-version emacs-version
                                          :daemon (emacs-pid) :gc-cons-threshold gc-cons-threshold
                                          :warmup 1 :repetitions 3 :counts counts
                                          :samples (vconcat (nreverse (copy-sequence samples))))))))))
        t)
    (kill-buffer preview)
    (when (buffer-live-p sidebar) (kill-buffer sidebar))))
