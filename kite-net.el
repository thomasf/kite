
(defvar kite-network-mode-map
  (let ((map (make-keymap))
	(menu-map (make-sparse-keymap)))
    (suppress-keymap map t)
    (define-key map "r" 'kite-debug-reload)
    (define-key map (kbd "RET") 'kite-show-network-entry)
    map)
  "Local keymap for `kite-network-mode' buffers.")

(define-derived-mode kite-network-mode special-mode "kite-network"
  "Toggle kite network mode."
  (set (make-local-variable 'kill-buffer-hook) '--kite-kill-network)
  (set (make-local-variable 'kite-min-time) nil)
  (set (make-local-variable 'kite-max-time) nil)
  (set (make-local-variable 'kite-header-width) 0)

  (setq show-trailing-whitespace nil)
  (setq case-fold-search nil)
  (setq line-spacing (max (or line-spacing 0) 2)))

(defun --kite-Network-loadingFinished (websocket-url packet)
  (--kite-log "--kite-Network-loadingFinished"))

(defun --kite-network-barchart-width ()
  (/ (* (frame-pixel-width)
        (- (frame-width) kite-header-width 10))
     (frame-width)))

(defun --ekwd-render-network-entry (request-response)
  (--kite-log "ewoc called with request-response %s" request-response)
  (let ((request-method (cdr (assq 'method (cdr (assq 'request (cdr (assq 'will-be-sent request-response)))))))
        (request-url (cdr (assq 'url (cdr (assq 'request (cdr (assq 'will-be-sent request-response)))))))
        (status-code (cdr (assq 'status (cdr (assq 'response (cdr (assq 'response-received request-response)))))))
        (response-size
         (let ((result 0) (iter request-response))
           (while iter
             (--kite-log "dolist, packet is " (car iter))
             (when (eq 'data-received (car (car iter)))
               (setq result (+ result (cdr (assq 'dataLength (cdr (car iter)))))))
             (setq iter (cdr iter)))
           result))
        (inhibit-read-only t))

    (let ((barchart-width (--kite-network-barchart-width))
          barchart
          times
          (packets request-response))
      (while packets
        (let ((packet (car packets)))
          (cond
           ((eq 'will-be-sent (car packet))
            (setq times (cons (list 'requestStart (cdr (assq 'timestamp (cdr packet)))) times)))
           ((eq 'response-received (car packet))
            (let* ((timing (cdr (assq 'timing (cdr (assq 'response (cdr packet))))))
                   (request-time (cdr (assq 'requestTime timing)))
                   (relative-times '(
                                     sslEnd
                                     sslStart
                                     receiveHeadersEnd
                                     sendEnd
                                     sendStart
                                     connectEnd
                                     connectStart
                                     dnsEnd
                                     dnsStart
                                     proxyEnd
                                     proxyStart
                                     )))
              (while relative-times
                (let ((relative-time (cdr (assq (car relative-times) timing))))
                  (when (and (not (null relative-time))
                             (>= relative-time 0))
                    (setq times (cons (list (car relative-times) (+ request-time (/ relative-time 1000))) times))))
                (setq relative-times (cdr relative-times)))))
           ((eq 'data-received (car packet))
            (setq times (cons (list 'dataReceived (cdr (assq 'timestamp (cdr packet)))) times))))
          (setq packets (cdr packets))))
      (let ((scaled-times
             (cons
              (cons 'pageStart 0)
              (mapcar (lambda (x)
                        (cons (nth 0 x)
                              (round
                               (* barchart-width
                                  (/ (- (nth 1 x) kite-min-time)
                                     (if (eq kite-max-time kite-min-time)
                                         1
                                       (- kite-max-time kite-min-time)))))))
                      (sort times (lambda (x y) (< (nth 1 x) (nth 1 y))))))))
        (setcar (car (last scaled-times)) 'requestFinished)
        (while scaled-times
          (let ((left (cdr (nth 0 scaled-times)))
                (right (cdr (nth 1 scaled-times))))
            (when (and (not (null right))
                       (< left right))
              (setq barchart (concat barchart
                                     (propertize "x"
                                                 'face (intern (concat "bg:kite-" (symbol-name (car (car scaled-times)))))
                                                 'display (cons 'space (list :height (cons 1 'mm) :width (list (- right left)))))))))
          (setq scaled-times (cdr scaled-times))))

      (insert
       (concat
        (--kite-fill-overflow (concat request-method " " request-url) 50)
        "  "
        (--kite-fill-overflow 
         (if status-code
             (number-to-string status-code)
           "---") 3)
        "  "
        (--kite-fill-overflow 
         (if (not (null response-size))
             (file-size-human-readable response-size)
           "") 10)
        "  "
        barchart
        "\n")))))

(defun --kite-frame-inner-width ()
  (if (fboundp 'window-inside-pixel-edges)
      (- (nth 2 (window-inside-pixel-edges))
         (nth 0 (window-inside-pixel-edges)))
    (frame-pixel-width)))

(defun --kite-network-update-header ()
  (let ((header-string (propertize
                        (concat
                         (--kite-fill-overflow "Method+URL" 50)
                         "  "
                         (--kite-fill-overflow "Sta" 3)
                         "  "
                         (--kite-fill-overflow "Size" 10)
                         "  ")
                        'face 'kite-table-head)))

    (setq kite-header-width (string-width header-string))

    (let* ((barchart-width (--kite-network-barchart-width))
           (hpos (/ (* (--kite-frame-inner-width)
                       kite-header-width)
                    (frame-width)))
           (total-time (- kite-max-time kite-min-time))
           (current-tick 0)
           (tick-steps '((1 . ns)
                         (2 . ns)
                         (5 . ns)
                         (10 . ns)
                         (20 . ns)
                         (50 . ns)
                         (100 . ns)
                         (200 . ns)
                         (500 . ns)
                         (1 . ms)
                         (2 . ms)
                         (5 . ms)
                         (10 . ms)
                         (20 . ms)
                         (50 . ms)
                         (100 . ms)
                         (200 . ms)
                         (500 . ms)
                         (1 . s)
                         (2 . s)
                         (5 . s)
                         (10 . s)
                         (15 . s)
                         (30 . s)
                         (1 . m)
                         (2 . m)
                         (5 . m)
                         (10 . m)
                         (15 . m)
                         (30 . m)
                         (1 . h)
                         (2 . h)
                         (5 . h)
                         (12 . h)))
           (units '((ns 1 1000000)
                    (ms 1 1000)
                    (s 1 1)
                    (m 60 1)
                    (h 3600 1)))
           (use-tick-step
            (let ((tick-iter tick-steps)
                  (min-tick-width (* 9 (/ (frame-pixel-width) (frame-width)))))
              (while (and tick-iter
                          (< (/ (* barchart-width (car (car tick-iter)) (nth 1 (assq (cdr (car tick-iter)) units)))
                                (* total-time (nth 2 (assq (cdr (car tick-iter)) units))))
                             min-tick-width))
                (setq tick-iter (cdr tick-iter)))
              (car tick-iter)))
           (tick-step (car use-tick-step))
           (tick-factor-num (nth 1 (assq (cdr use-tick-step) units)))
           (tick-factor-den (nth 2 (assq (cdr use-tick-step) units)))
           (tick-factor-unit (symbol-name (cdr use-tick-step)))
           (header header-string))

      (while (<= (* current-tick tick-factor-num)
                 (* total-time tick-factor-den))
        (setq header (concat header
                             (propertize "x"
                                         'face 'kite-table-head
                                         'display (cons 'space
                                                        (list :align-to
                                                              (list
                                                               (+ hpos (/ (* barchart-width current-tick tick-factor-num)
                                                                          (* total-time tick-factor-den)))))))
                             (propertize "x"
                                         'face 'bg:kite-table-head
                                         'display '(space . (:width (1))))
                             (propertize "x"
                                         'face 'kite-table-head
                                         'display '(space . (:width (3))))
                             (propertize (concat (number-to-string current-tick) tick-factor-unit)
                                         'face 'kite-table-head)))
        (setq current-tick (+ current-tick tick-step)))

      (ewoc-set-hf kite-ewoc
                   (concat header "\n")
                   "\n"))))

(defun kite-network ()
  (interactive)
  (--kite-log "opening network")
  (lexical-let*
      ((kite-connection (current-buffer))
       (buf (get-buffer-create (format "*kite network %s*" (cdr (assq 'webSocketDebuggerUrl kite-tab-alist))))))
    (with-current-buffer buf
      (kite-network-mode)

      (let ((inhibit-read-only t))
        (erase-buffer)
        (set (make-local-variable 'kite-ewoc)
             (ewoc-create (symbol-function '--ekwd-render-network-entry)
                          ""
                          "\nReload the page to show network information\n" t)))

      (set (make-local-variable 'kite-connection) kite-connection)
      (set (make-local-variable 'kite-requests) (make-hash-table :test 'equal)))
    (switch-to-buffer buf)
    (save-excursion
      (with-current-buffer kite-connection
        (--kite-log "sending in buffer %s" (current-buffer))
        (--kite-send "Network.enable" nil
                     (lambda (response) (--kite-log "Network enabled.")))))))

(defun --kite-network-update-min-max-time ()
  (with-current-buffer (format "*kite network %s*" websocket-url)
    (let (min-time)
      (maphash (lambda (key value)
                 (let ((timestamp (cdr (assq 'timestamp (cdr (assq 'will-be-sent (ewoc-data (car value))))))))
                   (if (null min-time)
                       (setq min-time timestamp)
                     (setq min-time (min min-time timestamp))))) kite-requests)
      (let ((max-time min-time)
            (relative-times '(receiveHeadersEnd sendStart sendEnd sslStart sslEnd connectStart connectEnd dnsStart dnsEnd proxyStart proxyEnd)))
        (maphash (lambda (key value)
                   (let ((packets (ewoc-data (car value))))
                     (--kite-log "packet cars: %s" (mapcar (symbol-function 'car) packets))
                     (while packets
                       (--kite-log "packets car: %s" (car packets))
                       (--kite-log "data-received cdr: %s" (cdr (assq 'data-received (car packets))))
                       (let* ((data-timestamp (and (eq 'data-received (car (car packets)))
                                                   (cdr (assq 'timestamp (cdr (car packets))))))
                              (timing (and (eq 'response-received (car (car packets)))
                                           (cdr (assq 'timing (cdr (assq 'response (cdr (car packets))))))))
                              (request-time (cdr (assq 'requestTime timing))))
                         (when data-timestamp
                           (setq max-time (max max-time data-timestamp)))
                         (while relative-times
                           (let ((relative-time (cdr (assq (car relative-times) timing))))
                             (when (and (not (null relative-time))
                                        (not (eq -1 relative-time)))
                               (setq max-time (max max-time (+ request-time (/ relative-time 1000))))))
                           (setq relative-times (cdr relative-times))))
                       (setq packets (cdr packets)))))
                   kite-requests)
        (if (and (eq kite-min-time min-time)
                 (eq kite-max-time max-time))
            nil
          (setq kite-min-time min-time)
          (setq kite-max-time max-time)
          t)))))

(defun --kite-Network-requestWillBeSent (websocket-url packet)
  (with-current-buffer (format "*kite network %s*" websocket-url)
    (let ((inhibit-read-only t))
      (when (string= (cdr (assq 'url (cdr (assq 'request packet))))
                     (cdr (assq 'documentURL packet)))
        (clrhash kite-requests)
        (ewoc-filter kite-ewoc (lambda (x) nil)))
      (goto-char (point-max))
      (let ((ewoc-node (ewoc-enter-last kite-ewoc nil)))
        (puthash (cdr (assq 'requestId packet)) (list ewoc-node) kite-requests)
        (ewoc-set-data ewoc-node
                       (list (cons 'will-be-sent packet))))
      (if (--kite-network-update-min-max-time)
          (progn
            (--kite-network-update-header)
            (ewoc-refresh kite-ewoc))
        (ewoc-invalidate kite-ewoc (car request-data))))))

(defun --kite-Network-responseReceived (websocket-url packet)
  (with-current-buffer (format "*kite network %s*" websocket-url)
    (let ((inhibit-read-only t)
          (request-data (gethash (cdr (assq 'requestId packet)) kite-requests)))
      (ewoc-set-data (car request-data)
                     (cons (cons 'response-received packet)
                           (ewoc-data (car request-data))))
      (if (--kite-network-update-min-max-time)
          (progn
            (--kite-network-update-header)
            (ewoc-refresh kite-ewoc))
        (ewoc-invalidate kite-ewoc (car request-data))))))

(defun --kite-Network-dataReceived (websocket-url packet)
  (with-current-buffer (format "*kite network %s*" websocket-url)
    (let ((inhibit-read-only t)
          (request-data (gethash (cdr (assq 'requestId packet)) kite-requests)))
      (ewoc-set-data (car request-data)
                     (cons (cons 'data-received packet)
                           (ewoc-data (car request-data))))
      (if (--kite-network-update-min-max-time)
          (progn
            (--kite-network-update-header)
            (ewoc-refresh kite-ewoc))
        (ewoc-invalidate kite-ewoc (car request-data))))))

(defun --kite-kill-network ()
  (ignore-errors
    (with-current-buffer kite-connection
      (--kite-send "Network.disable" nil
                   (lambda (response) (--kite-log "Network disabled."))))))

(defun --kite-Page-domContentEventFired (websocket-url packet)
  (let ((network-buffer (get-buffer (format "*kite network %s*" websocket-url))))
    (when network-buffer
      (with-current-buffer network-buffer
        (set (make-local-variable 'kite-dom-content-fired-timestamp) (cdr (assq 'timestamp packet)))
        (when (and (boundp 'kite-max-time)
                   (or (null kite-max-time)
                       (> kite-dom-content-fired-timestamp kite-max-time)))
          (setq kite-max-time kite-dom-content-fired-timestamp)
          (ewoc-refresh kite-ewoc))))))

(provide 'kite-net)