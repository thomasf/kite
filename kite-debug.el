;;; kite-debug.el --- Kite debugger module implementation

;; Copyright (C) 2012 Julian Scheid

;; Author: Julian Scheid <julians37@gmail.com>
;; Keywords: tools
;; Package: kite
;; Compatibility: GNU Emacs 24

;; This file is not part of GNU Emacs.

;; Kite is free software: you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; Kite is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.

;; You should have received a copy of the GNU General Public License
;; along with Kite.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package implements the WebKit debugger buffer, which is used
;; to manage breakpoints.
;;
;; It is part of Kite, a WebKit inspector front-end.


;;; Code:

(require 'kite-global)

(defconst kite--debugger-state-resumed
  (propertize "Resumed" 'face 'success))

(defconst kite--debugger-state-paused
  (propertize "Paused" 'face 'warning))

(defvar kite-debug-mode-map
  (let ((map (make-keymap))
	(ctl-c-b-map (make-keymap))
	(menu-map (make-sparse-keymap)))
    (suppress-keymap map t)
    (kite--define-global-mode-keys map)
    (define-key map "C" 'kite-console)
    (define-key map "p" 'kite-toggle-next-instruction-breakpoint)
    (define-key map "b" 'kite-toggle-exception-breakpoint)
    (define-key map "c" 'kite-debug-continue)
    (define-key map "r" 'kite-debug-reload)
    (define-key map "R" 'kite-repl)
    (define-key map "D" 'kite-dom-inspect)
    (define-key map "N" 'kite-network)
    (define-key map "T" 'kite-timeline)
    (define-key map "M" 'kite-memory)
    (define-key mode-specific-map "b" ctl-c-b-map)
    (define-key ctl-c-b-map "x" 'kite-set-xhr-breakpoint)
    (define-key ctl-c-b-map "d" 'kite-set-dom-event-breakpoint)
    (define-key ctl-c-b-map "i" 'kite-set-instrumentation-breakpoint)
    (define-key ctl-c-b-map "b" 'kite-toggle-exception-breakpoint)
    (define-key ctl-c-b-map "p" 'kite-toggle-next-instruction-breakpoint)
    map)
  "Local keymap for `kite-connection-mode' buffers.")

(define-derived-mode kite-debug-mode special-mode "kite-debug"
  "Toggle kite debug mode."
  :group 'kite
  (setq case-fold-search nil)
  (kite--connect-buffer-insert)
  (run-mode-hooks 'kite-debug-mode-hook))

(defun kite-debug-pause ()
  (interactive)
  (kite-send "Debugger.pause" nil
             (lambda (response) (kite--log "Execution paused."))))

(defun kite-debug-continue ()
  (interactive)
  (kite-send "Debugger.resume" nil
             (lambda (response) (kite--log "Execution resumed."))))

(defun kite-debug-reload ()
  (interactive)
  (with-current-buffer (if (boundp 'kite-connection)
                           kite-connection
                         (current-buffer))
    (kite-send "Page.reload" nil
               (lambda (response) (kite--log "Page reloaded.")))))

(defun kite--insert-favicon-async (favicon-url)
  (let ((favicon-marker (point-marker)))
    (url-retrieve
     favicon-url
     (lambda (status)
       (goto-char 0)
       (when (and (looking-at "HTTP/1\\.. 200")
                  (re-search-forward "\n\n" nil t))
         (ignore-errors
           (let* ((favicon-image
                   (create-image (buffer-substring (point) (buffer-size)) nil t)))
             (save-excursion
               (with-current-buffer buf
                 (goto-char (marker-position favicon-marker))
                 (let ((inhibit-read-only t))
                   (insert-image favicon-image)))))))))))

(defun kite--connect-buffer-insert ()
  (let ((favicon-url (kite-session-page-favicon-url kite-session)))
    (when (and favicon-url
               (not (string= favicon-url "")))
      (kite--insert-favicon-async favicon-url))

    (let* ((inhibit-read-only t)
           (ewoc (ewoc-create
                  (lambda (session)
                    (insert (concat (propertize (concat " " (kite-session-page-title kite-session) "\n\n")
                                                'face 'info-title-1))
                            (propertize "URL: " 'face 'bold)
                            (kite-session-page-url kite-session)
                            "\n"
                            (propertize "Status: " 'face 'bold)
                            (kite-session-debugger-state session)
                            "\n\n"
                            "Press ? for help\n")))))

      (set (make-local-variable 'kite-connection-ewoc) ewoc)

      (ewoc-enter-last ewoc kite-session)

      (goto-char (point-max))
      (setf (kite-session-breakpoint-ewoc kite-session)
            (kite--make-breakpoint-ewoc)))))

(defun kite--connection-buffer (websocket-url)
  (format "*kite %s*" websocket-url))

(defun kite--Debugger-resumed (websocket-url packet)
  (with-current-buffer (kite--connection-buffer websocket-url)
    (setf (kite-session-debugger-state kite-session) kite--debugger-state-resumed)))

(defun kite--Debugger-paused (websocket-url packet)
  (with-current-buffer (kite--connection-buffer websocket-url)
    (setf (kite-session-debugger-state kite-session) kite--debugger-state-paused)
    (ewoc-refresh kite-connection-ewoc)
    (let* ((call-frames (plist-get packet :callFrames))
           (first-call-frame (elt call-frames 0))
           (location (plist-get first-call-frame :location))
           (script-info (gethash (plist-get location :scriptId)
                                 (kite-session-script-infos kite-session))))
      (lexical-let ((line-number (- (plist-get location :lineNumber)))
                    (column-number (plist-get location :columnNumber))
                    (kite-session kite-session))
        (kite-visit-script
         script-info
         line-number
         column-number
         (lambda ()
           (kite-debugging-mode)
           (set (make-local-variable 'kite-session) kite-session))))
      (message "Debugger paused"))))

(defun kite--Debugger-scriptParsed (websocket-url packet)
  (puthash
   (plist-get packet :scriptId)
   (make-kite-script-info
    :url (plist-get packet :url)
    :start-line (plist-get packet :startLine)
    :start-column (plist-get packet :startColumn)
    :end-line (plist-get packet :endLine)
    :end-column (plist-get packet :endColumn)
    :source-map-url (plist-get packet :sourceMapURL))
   (kite-session-script-infos kite-session)))

(add-hook 'kite-Debugger-paused-hooks 'kite--Debugger-paused)
(add-hook 'kite-Debugger-resumed-hooks 'kite--Debugger-resumed)
(add-hook 'kite-Debugger-scriptParsed-hooks 'kite--Debugger-scriptParsed)


;;; Augmented javascript-mode; loading of remote .js files

(defvar kite-debugging-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-ci" 'kite-step-into)
    (define-key map "\C-co" 'kite-step-over)
    (define-key map "\C-cu" 'kite-step-out)
    (define-key map "\C-cp" 'kite-debug-pause)
    map)
  "Local keymap for the `kite-debugging-mode' minor mode")

(define-minor-mode kite-debugging-mode
  "Toggle kite JavaScript debugging in this buffer."
  :group 'kite
  :lighter (:eval (kite--debug-stats-mode-line-indicator))
  :keymap 'kite-debugging-mode-map)

(defun kite-step-into ()
  (interactive)
  (kite-send "Debugger.pause" nil
             (lambda (response)
               (kite--log "Response to Debugger.pause is %s" response)
               (kite-send "Debugger.stepInto" nil
                          (lambda (response)
                            (kite--log "Response to Debugger.stepInto is %s" response))))))

(defun kite-step-over ()
  (interactive)
  (kite-send "Debugger.stepOver"))

(defun kite-step-out ()
  (interactive)
  (kite-send "Debugger.stepOut"))

(defun kite--create-remote-script-buffer (script-info after-load-function)
  (lexical-let* ((url (kite-script-info-url script-info))
                 (url-parts (url-generic-parse-url url))
                 (after-load-function after-load-function)
                 (new-buffer (generate-new-buffer url)))
    (kite-send "Debugger.getScriptSource" (list (cons 'scriptId (plist-get location :scriptId)))
               (lambda (response)
                 (with-current-buffer new-buffer
                   (setq buffer-file-name (url-filename url-parts))
                   (insert (plist-get (plist-get response :result) :scriptSource))
                   (setq buffer-read-only t)
                   (set-buffer-modified-p nil)
                   (normal-mode)
                   (funcall after-load-function))))
    new-buffer))

(defun kite-script-info--source-map (script-info)
  "Return the parsed source map for the given SCRIPT-INFO as a
`kite-source-map' struct, or nil if there is no source map for
the SCRIPT-INFO.  Raise an error if the source map can't be
loaded or parsed."
  (when (kite-script-info-source-map-url script-info)
    (with-current-buffer
        (url-retrieve-synchronously
         (url-expand-file-name
          (kite-script-info-source-map-url script-info)
          (kite-script-info-url script-info)))
      (goto-char 0)
      (if (and (or (looking-at "HTTP/1\\.. 200")
                   (not (looking-at "HTTP/")))
               (re-search-forward "\n\n" nil t))
          (kite--source-map-decode
           (let ((json-array-type 'list)
                 (json-object-type 'plist))
             (json-read)))
        (error "Could not retrieve source map: %s"
               (buffer-substring-no-properties
                (point-min) (point-max)))))))

(defun kite-script-info--source-map-cached (script-info)
  "Return the parsed source map for the given SCRIPT-INFO as a
`kite-source-map' struct, or nil if there is no source map for
the SCRIPT-INFO.  Raise an error if the source map can't be
loaded or parsed.  Uses a cache in the session so that each
source map is loaded and parsed only once."
  (when (kite-script-info-source-map-url script-info)
    (let ((cached-entry
           (gethash (kite-script-info-source-map-url script-info)
                    (kite-session-source-map-cache kite-session))))
      (cond
       ((kite-source-map-p cached-entry)
        cached-entry)
       ((consp cached-entry)
        (signal (car err) (cdr err)))
       (t
        (condition-case err
            (puthash (kite-script-info-source-map-url script-info)
                     (kite-script-info--source-map script-info)
                     (kite-session-source-map-cache kite-session))
          (error
           (puthash (kite-script-info-source-map-url script-info)
                    err
                    (kite-session-source-map-cache kite-session))
           (signal (car err) (cdr err)))))))))

(defun kite-script-info--original-source (script-info line column)
  "Return original URL, line, and column corresponding to the
given SCRIPT-INFO, LINE, and COLUMN.  The original location is
returned as a plist with keys `:url', `:line' and `:column'."
  (let ((source-map
         (condition-case err
             (kite-script-info--source-map-cached script-info)
           (error
            ;; In case of error, display error and fall back to
            ;; generated source
            (message (cdr err))
            nil))))
    (if source-map
        (let ((original-pos
               (kite-source-map-original-position-for
                source-map
                line
                column)))
          (list :url
                (url-expand-file-name
                 (plist-get original-pos :source)
                 (kite-script-info-url script-info))
                :line (plist-get original-pos :line)
                :column (plist-get original-pos :column)))
      (list :url (kite-script-info-url script-info)
            :line line
            :column column))))

(defun kite-visit-script (script-info line column after-load-function)
  "Visit the script described by the given SCRIPT-INFO and, once
loaded, move point to LINE and COLUMN and execute
AFTER-LOAD-FUNCTION with the new buffer current.  If a source map
is available, go to the original location instead."
  (interactive)
  (let* ((original-source (kite-script-info--original-source
                           script-info
                           line
                           column))
         (url (plist-get original-source :url))
         (url-parts (url-generic-parse-url url)))
    (flet ((after-load ()
                       (goto-line (plist-get original-source :line))
                       (beginning-of-line)
                       (forward-char
                        (plist-get original-source :column))
                       (funcall after-load-function)))
      (cond
       ((string= (url-type url-parts) "file")
        (find-file (url-filename url-parts))
        (after-load))
       (t
        (switch-to-buffer (or (get-buffer url)
                              (kite--create-remote-script-buffer
                               script-info (function after-load)))))))))

(defun kite--debug-stats-mode-line-indicator ()
  "Returns a string to be displayed in the mode line"
  (concat " (" (kite-session-debugger-state kite-session) ")"))

(defun kite-session-script-info-for-url (url)
  "Return the script-info entry for the given URL in the session
bound to `kite-session', or nil if not found."
  (let (result)
    (maphash (lambda (key value)
               (when (string= url (kite-script-info-url value))
                 (setq result value)))
             (kite-session-script-infos kite-session))
    result))

(defun kite-visit-stack-frame (stack-frame-plist)
  "Visit the source file corresponding to the stack frame given
by STACK-FRAME-PLIST, which should be a plist with at least the
properties `:url', `:lineNumber' and `:columnNumber'.  The
variable `kite-session' should be bound to the session in which
to visit the source file."
  (message "visiting %s, source infos: %s" stack-frame-plist (kite-session-script-infos kite-session))
  (let ((line-number (plist-get stack-frame-plist :lineNumber))
        (column-number (plist-get stack-frame-plist :columnNumber))
        (script-info (kite-session-script-info-for-url
                      (plist-get stack-frame-plist :url))))
    (if script-info
        (kite-visit-script
         script-info
         line-number
         (- column-number 1)
         (lambda ()
           (set (make-local-variable 'kite-session) kite-session)))
      (error "Source is unavailable"))))

(provide 'kite-debug)

;;; kite-debug.el ends here
