;;; -*- mode: Emacs-Lisp;  lexical-binding: t; -*-

(mapcar #'require '(cl epg dired-aux timezone)) ;(require 'diary-lib)

(dolist (FN '("0" "macros" "common" "other"))
  (let ((full-name (concat default-directory FN ".el")))
    (clog :debug "loading %s" full-name)
    (load full-name)))

(defvar *clouded-hosts* nil "host names participating in file syncronization")
(defvar *pending-actions* nil "actions to be saved in the cloud")
(defvar *important-msgs* nil "these messages will be typically printed at the end of the process")

(defvar cloud-file-hooks nil "when special files (e.g., diary or bookmarks) are renewed one should call, e.g., diary-view-entries or bookmark-load")
(unless (boundp '*emacs-d*) (defvar *emacs-d* "/home/shalaev/.emacs.d/"))
(defvar *local-dir* (concat *emacs-d* "cloud/"))

(defvar *local-config* (concat *local-dir* "config"))

(defvar *contents-name* nil)
(defvar *cloud-dir*  "/mnt/cloud/"); was: "/mnt/lws/" – to be loaded from config files

(defvar *file-DB* nil); ← to be synced with the cloud
(defvar *password* nil); to be read from config or generated
;;(defvar *catalogue* nil); randomly generated name of the catalogue
;;(defvar *encrypted-files* nil "list of the files after they are encrypted")
(defvar DB-fields; индексы различных полей массива
(list 'plain; исходное (незашифрованное) полное имя файла
'cipher; зашифрованное имя файла (base name)
'mtime; modification time
'modes; permissions
'uname; user name (obsolete and unused)
'gname; group name
'write-me))
(let ((i 0)) (dolist (field-name DB-fields) (setf i (1+ (set field-name i)))))
(setf to-cloud 1 from-cloud 2); 0 corresponds to nil in older versions

(defun cloud-context-set-process (context process)
"replaces epg-context-set-process from epg.el"
  (aset context 11 process))
(defun cloud-context-process (context)
"replaces epg-context-process from epg.el"
  (aref context 11))
(defun cloud-wait-for-completion (context)
"replaces epg-wait-for-completion from epg.el"
  (while (eq (process-status (cloud-context-process context)) 'run)
  (sleep-for 0.1)))

(defun launch-encryption (context plain-data cipher-data password)
  (let* ((args (list "--pinentry-mode" "loopback"
                             "--batch" "--yes"
                             "--passphrase" password
                             "-o" (epg-data-file cipher-data)
                             "--symmetric" (epg-data-file plain-data)))
         (buffer (generate-new-buffer " *cloud-crypt*"))
         process)
    (setf process
          (apply #'start-process "cloud" buffer "gpg" args))
    (cloud-context-set-process context process)))
(defun launch-decryption (context plain-data cipher-data password)
  (let* ((args (list "--pinentry-mode" "loopback"
                             "--batch" "--yes"
                             "--passphrase" password
                             "-o" (epg-data-file plain-data)
                             "--decrypt" (epg-data-file cipher-data)))
         (buffer (generate-new-buffer " *cloud-crypt*"))
         process)
    (setf process
          (apply #'start-process "cloud" buffer "gpg" args))
    (cloud-context-set-process context process)))

(defun end-log (fstr &rest args)
  "message + time"
(push
  (apply #'format (cons (concat
     (format-time-string "%H:%M:%S "
(apply 'encode-time (butlast (decode-time (current-time)) 3)))
fstr)
args))
*important-msgs*))

(defun post-decrypt (FN)
  "special treatment for certain files"
  (let ((ext (file-name-extension FN))
        (name (file-name-base FN)))
    (when (string= FN (expand-file-name diary-file))
      (with-current-buffer (find-file-noselect (diary-check-diary-file))
        (clog :debug "diary buffer opened or updated")))
     (when (member FN *emacs-configs*)
(end-log "*configuration changed, consider reloading emacs*")
    (clog :warning "consider reloading configuration file %s" FN)
    ;;   (load-file FN))
)))

(defvar do-not-encrypt '("gpg"))
(defun cloud-encrypt (plain-file cipher-file password)
(let ((cloud-name (concat *cloud-dir* cipher-file ".gpg")))
(if (member (file-name-extension plain-file) do-not-encrypt)
    (progn (copy-file plain-file cloud-name t) t)
  (let (sucess (context (epg-make-context 'OpenPGP)))
    (launch-encryption context 
                       (epg-make-data-from-file plain-file)
                       (epg-make-data-from-file cloud-name)
                       password)
    (cloud-wait-for-completion context)
    (setf sucess (= 0 (process-exit-status (cloud-context-process context))))
    (epg-reset context); closes the buffer (among other things)
    sucess))))
(defun cloud-decrypt (cipher-file plain-file password)
  (let ((cloud-name (clouded cipher-file))
        (dir (file-name-directory plain-file)))
    (unless (file-directory-p dir) (make-directory dir t))
  (if (member (file-name-extension plain-file) do-not-encrypt)
      (progn (copy-file cloud-name plain-file t) t)
    (let (sucess (context (epg-make-context 'OpenPGP)))
      (launch-decryption context
                         (epg-make-data-from-file plain-file)
                         (epg-make-data-from-file cloud-name)
                         password)
      (cloud-wait-for-completion context)
      (when (setf sucess (= 0 (process-exit-status (cloud-context-process context))))
        (post-decrypt plain-file))
      (epg-reset context); closes the buffer (among other things)
      sucess))))

(defun cloud-connected-p()
  (and
   *cloud-dir* *contents-name*
   (file-readable-p *cloud-dir*)))
;;(file-readable-p (concat *cloud-dir* *contents-name* ".gpg")

(defun write-conf()
(with-temp-file *local-config*
  (insert (format "contents-name=%s" *contents-name*)) (newline)
  (insert (format "password=%s" *password*)) (newline)
  (insert (format "cloud-directory=%s" *cloud-dir*)) (newline)))

(defun cloud-init() "initializes cloud directory and generates password -- runs only once"
(interactive)
(when (yes-or-no-p "Is cloud mounted?")
(setf *cloud-dir* (read-string "cloud directory=" *cloud-dir*))
(ifn (member (safe-mkdir *cloud-dir*) '(:exists t))
(clog :error "could not create/acess directory %s" *cloud-dir*)

(if (directory-files *cloud-dir* nil "^.\+.gpg$" t)
    (clog :error "please clean the directory %s before asking me to initialize it" *cloud-dir*)
(clog :info "creating (main) contents file in unused directory %s" *cloud-dir*)
(ifn-set ((*contents-name* (new-file-name *cloud-dir*)))
  (clog :error "could not create DB file in the directory %s" *cloud-dir*)

(setf *password* (rand-str 9))

(ifn (member (safe-mkdir *local-dir*) '(:exists t))
(clog :error "could not create/acess directory %s" *local-dir*)
(write-conf)
(clog :info "use M-x cloud-add in the dired to cloud important files and directories" )))))))

(defun write-fileDB (DBname)
  (with-temp-file DBname
(dolist (hostname *clouded-hosts*) (insert (format "%s " hostname)))
(delete-char -1) (newline)

(dolist (action *pending-actions*)
(insert (format-action action)) (delete-char -1) (newline))

(newline)

(dolist (file-record *file-DB*)
(insert (format-file file-record)) (newline))))

(defun clouded(CN) (concat *cloud-dir* CN ".gpg"))

(defun read-fileDB* (DBname)
  "reads content (text) file into the database *file-DB*"
(clog :debug "read-fileDB (%s)" DBname)
  (find-file DBname) (goto-char (point-min))
(macrolet ((read-line() '(setf str (buffer-substring-no-properties (point) (line-end-position)))))
  (let ((BN (buffer-name)) str)
(needs-set
 ((*clouded-hosts* 
  (split-string (read-line))
  (clog :error "invalid first line in the contents file %s" DBname)))

(unless (member (system-name) *clouded-hosts*) (cloud-host-add))
(forward-line)

(while (< 0 (length (read-line)))
(clog :debug "another action line = %S" str)
(let ((action (make-vector (length action-fields) nil)))

(dolist (column (list
                 '(:string . i-time)
                 '(:int . i-ID)
                 '(:int . i-Nargs)
                 `((:strings . ,(aref action i-Nargs)) . i-args)
                 '(:strings . i-hostnames)))
  (needs ((col-value (begins-with str (car column)) (bad-column "action" (cdr column))))
     (aset action (cdr column) (car col-value))
     (setf str (cdr col-value))))

(let ((AID (format-time-string "%02m/%02d %H:%M:%S" (aref action i-time))))
  (ifn (member (system-name) (aref action i-hostnames))
      (clog :info "this host is unaffected by action %s" AID)
    (if (perform action)
        (clog :debug "sucessfully performed action %s" AID)
      (clog :error " action %s failed, will NOT retry it" AID))

(when (drop (aref action i-hostnames) (system-name))
  (push action *pending-actions*))
(forward-line)))))

(forward-line)
(while (< 10 (length (read-line))) ;(clog :debug "another file line = %s" str)
(let ((CF (make-vector (length DB-fields) nil)))
(ifn (string-match "\"\\(.+\\)\"\s+\\([^\s]+\\)\s+\\([^\s]+\\)\s+\\([^\s]+\\)\s+\\([[:digit:]]+\\)\s+\"\\(.+\\)\"" str)
(clog :error "ignoring invalid file-line %s in the contents file %s" str DBname)

(let* ((FN (match-string 1 str)))
  (aset CF plain FN)
  (aset CF cipher (match-string 2 str))
  (aset CF uname (match-string 3 str))

(aset CF gname (match-string 4 str))
  (aset CF modes (string-to-int (match-string 5 str)))
  (let ((mtime-str (match-string 6 str)))
(ifn (string-match "[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [[:upper:]]\\{3\\}" mtime-str)
(bad-column "file" 6 mtime-str)
(aset CF mtime (parse-time mtime-str))))

(when-let ((LF (cloud-locate-FN FN)))
  (clog :error "read-fileDB duplicate DB record for %s" FN)
  (drop *file-DB* LF))

(if-let ((LF (get-file-properties FN)))

(let ((CN (clouded (aset LF cipher (aref CF cipher)))))
(cond
 ((not (file-exists-p CN))
    (clog :warning "file %s is marked as clouded, but %s is missing" FN CN)
    (aset CF write-me to-cloud)
    (push CF *file-DB*))

((cloud-locate-CN CN)
 (clog :error "read-fileDB: will ignore %s because it is among *different* local files having the same cloud name %s.gpg" FN CN))

((time< (aref LF mtime) (aref CF mtime))
(clog :debug "pizdets 1")
 (aset CF write-me from-cloud) (push CF *file-DB*))
 ((time< (aref CF mtime) (aref LF mtime)) (aset LF write-me to-cloud) (push LF *file-DB*))
 (t (aset LF write-me 0)
(push LF *file-DB*))))

(clog :debug "pizdets 2")
 (aset CF write-me from-cloud)
 (push CF *file-DB*))

(forward-line))))))
(kill-buffer BN))))

(defmacro bad-column (cType N &optional str)
(if str
`(clog :error "invalid %dth column in %s line = %s" ,N ,cType ,str)
`(clog :error "invalid %dth column in %s line" ,N ,cType)))

(defun on-current-buffer-save ()
  "attention: this function might be called many times within a couple of seconds!"
  (let ((plain-file (file-chase-links (buffer-file-name))))
(when (and plain-file (stringp plain-file))
  (let ((file-data (cloud-locate-FN plain-file)))
    (when file-data
      (aset file-data mtime (current-time))
      (aset file-data write-me to-cloud))))))
(add-hook 'after-save-hook 'on-current-buffer-save)

(defun cloud-sync()
(interactive) 
  (let ((ok t))
  (ifn (cloud-connected-p)
      (clog :error "cloud-sync header failed")
    (when (boundp 'clog-flush) (clog-flush))

(dolist (FD *file-DB*)
  (when ok
(unless (file-exists-p (plain-name FD))
(clog :debug "pizdets 3")
 (aset FD write-me from-cloud))
(case= (aref FD write-me)
  (from-cloud
   (when 
  (and

(if (= 0 *log-level*) (yes-or-no-p (format "replace the file %s from the cloud?" (aref FD plain))) t)

(cloud-decrypt (cipher-name FD) (plain-name FD) *password*))
   (clog :debug "cloud/%s.gpg --> %s" (cipher-name FD) (plain-name FD))
   (set-file-modes (plain-name FD) (aref FD modes))
   (set-file-times (plain-name FD) (aref FD mtime))
   (chgrp (aref FD gname) (plain-name FD)); I have to call external program in order to change the group
   (aset FD write-me 0)
   (needs ((hooks (assoc (plain-name FD) cloud-file-hooks)))
(dolist (hook hooks) 
              (funcall (cdr hook) (car hook))))))

(to-cloud
   (when (cloud-encrypt (plain-name FD) (cipher-name FD) *password*)
     (clog :debug "%s (%s) --> cloud:%s.gpg"
       (plain-name FD)
       (format-time-string "%04Y-%02m-%02d %H:%M:%S %Z" (aref FD mtime))
       (cipher-name FD))
     (aset FD write-me 0))))))
  (when ok
(let ((tmp-CCN (concat *local-dir* "CCN")))
   (write-fileDB tmp-CCN)
   (if (setf ok (cloud-encrypt tmp-CCN *contents-name* *password*))
       (safe-delete-file tmp-CCN)
     (clog :error "failed to encrypt content file %s to %s!" tmp-CCN *contents-name*))))

(dolist (msg (reverse *important-msgs*)) (message msg))
ok)))

(unless (boundp 'DRF) (defvar DRF (indirect-function (symbol-function 'dired-rename-file)) "original dired-rename-file function"))
(unless (boundp 'DDF) (defvar DDF (indirect-function (symbol-function 'dired-delete-file)) "original dired-delete-file function"))

(defun cloud-forget-file (local-FN); called *after* the file has already been sucessfully deleted
  (needs ((DB-rec (cloud-locate-FN local-FN) (clog :info "doing nothing since %s is not clouded" local-FN))
          (cloud-FN (concat  *cloud-dir* (aref DB-rec cipher) ".gpg") (clog :error "in DB entry for %s" local-FN)))
   (drop *file-DB* DB-rec)
   (safe-delete-file cloud-FN)))
(defun cloud-forget(args)
(interactive) 
  (dolist (arg args) (cloud-forget-file arg)))

(defvar action-fields '(i-time i-ID i-args i-hostnames i-Nargs))

(let ((i 0)) (dolist (AF action-fields) (setf i (1+ (set AF i)))))
(defvar action-IDs '(i-forget i-delete i-rename i-host-add i-host-forget))
(let ((i 0)) (dolist (AI action-IDs) (setf i (1+ (set AI i)))))
(defun new-action (a-ID &rest args)
  (let ((action (make-vector (length action-fields) nil)))
    (aset action i-time (current-time))
    (aset action i-args args)
    (aset action i-hostnames *clouded-hosts*)
    (push action *pending-actions*)))

(defun perform(action)
  (let ((arguments (aref action i-args)))
    (case= (aref action i-ID)
      (i-host-forget (dolist (arg arguments) (drop *clouded-hosts* arg)))
      (i-host-add (dolist (arg arguments) (push arg *clouded-hosts*)))
      (i-forget (cloud-forget arguments))
      (i-delete (cloud-rm arguments))
      (i-rename (funcall DRF (first arguments) (second arguments) t))
      (otherwise (clog :error "unknown action %d" (aref action i-ID)))))
  (drop *pending-actions* action))

(defun format-action (action)
  (format "%S %d %d " (format-time-string "%04Y-%02m-%02d %H:%M:%S %Z" (aref action i-time))
          (aref action i-ID)
          (length (aref action i-args)))
  (dolist (arg (aref action i-args)) (format "%S " arg))
  (dolist (HN (aref action i-hostnames)) (format "%S " HN)))

(defun add-to-actions(hostname)
  (dolist (action *pending-actions*)
    (unless (member hostname (aref action i-hostnames))
      (aset action i-hostnames (cons hostname (aref action i-hostnames))))))
(defun erase-from-actions(hostname)
  (dolist (action *pending-actions*)
    (when (member hostname (aref action i-hostnames))
      (aset action i-hostnames (remove hostname (aref action i-hostnames))))))

(defun cloud-host-add ()
  "adding THIS host to the cloud sync-system"
(let ((hostname (system-name)))
  (unless (member hostname *clouded-hosts*)
    (push hostname *clouded-hosts*))
  (new-action i-host-add hostname)
  (add-to-actions hostname)))

(defun cloud-host-forget (); to be tested
  "remove host from the cloud sync-system"
  (let ((hostname (system-name)))
    (when (yes-or-no-p (format "Forget the host %s?" hostname))
      (new-action i-host-forget hostname)
      (if (cloud-sync)
          (safe-delete-file *local-config*)
        (clog :error "sync failed, so I will not erase local configuration")))))

(defun cloud-rename-file (old new); called *after* the file has already been sucessfully renamed
  (let ((source (cloud-locate-FN old))
        (target (cloud-locate-FN new)))
    (clog :debug "CRF")
    (cond
     ((and source target); overwriting one cloud file with another one
      (loop for property in (list mtime modes uname gname write-me) do
            (aset target property (aref source property)))
      (clog :debug "CRF case 1")
      (drop *file-DB* source)); удаление из БД
     (source (aset source plain new))
     (target (setf target (get-file-properties new))))))

(defun dired-rename-file (old-FN new-FN ok-if-already-exists)
  (let (failure)
    (clog :debug "DRF")
    (condition-case err
        (funcall DRF old-FN new-FN ok-if-already-exists)
      (file-error
       (clog :debug "DRF error!")
       (message "%s" (error-message-string err))
       (setf failure t)))
    (unless failure
      (clog :debug "launching my cloud rename %s --> %s" old-FN new-FN)
      (cloud-rename-file old-FN new-FN)
      (new-action i-rename old-FN new-FN))))

(defun contained-in(dir-name)
(when (file-directory-p dir-name)
(let (res)
(dolist (DB-rec *file-DB*)
(when(string=(substring-no-properties (aref DB-rec plain) 0 (length dir-name)) dir-name)
(push DB-rec res)))
res)))

(defun dired-delete-file (FN &optional dirP TRASH)
  (let (failure)

(condition-case err (funcall DDF FN dirP TRASH)
        (file-error
         (clog :error "in DDF: %s" (error-message-string err))
         (setf failure t)))
      (unless failure
(clog :debug "will now forget %s" FN)
        (cloud-forget-file FN)
        (when dirP
          (dolist (sub-FN (mapcar #'plain-name (contained-in FN)))
            (cloud-forget-file sub-FN))))))

(defun cloud-start()
  (interactive) (save-some-buffers)
(clog :debug "cloud-start: *local-config* = %s" *local-config*)
(if-let ((conf (read-conf *local-config*)))
    (ifn (and
          (if-let ((CD (cdr (assoc "cloud-directory" conf))))
                  (setf *cloud-dir* CD); "/mnt/lws/cloud/"
                  (setf *cloud-dir* (read-string "cloud directory=" *cloud-dir*))
                  (write-conf) t)
          (clog :debug "cloud-start: *cloud-dir* = %s" *cloud-dir*)
          (setf *contents-name* (cdr (assoc "contents-name" conf)))
          (clog :debug "cloud-start: *contents-name* = %s" *contents-name*)
          (setf *password*  (cdr (assoc "password" conf))))
         (clog :error "cloud-start header failed, consider (re)mounting %s or running (cloud-init)" *cloud-dir*)
         (read-fileDB)
         (cloud-sync))
    (clog :warning "could not read local configuration file")
    (when (yes-or-no-p "(Re)create configuration?")
      (cloud-init))))

(defun read-fileDB()
  (let ((tmp-CCN (concat *local-dir* "CCN")))
(or
(and 
         (cloud-connected-p)
         (cloud-decrypt *contents-name* tmp-CCN *password*)
         (progn (read-fileDB* tmp-CCN) (safe-delete-file tmp-CCN)))
(progn (clog :error "cloud-start header failed") nil))))

(defun read-conf (file-name)
  "reads configuration file"
(clog :debug "read-conf")
  (find-file *local-config*) (goto-char (point-min)); opening config file
  (let (res str (BN (buffer-name)))
    (while (and
            (setf str (buffer-substring-no-properties (point) (line-end-position)))
            (< 0 (length str)))
     (if (string-match "^\\(\\ca+\\)=\\(\\ca+\\)$" str)
         (push (cons (match-string 1 str) (match-string 2 str)) res)
       (clog :debug "garbage string in configuration file: %s" str))
(forward-line))
(kill-buffer BN)
    res))
(cloud-start)

(defun cloud-add (&optional FN)
  (interactive)
  (if (string= major-mode "dired-mode")
      (dired-map-over-marks (add-files (dired-get-filename)) nil)
    (unless
        (add-files (read-string "file to be clouded=" (if FN FN "")))
      (clog :error "could not cloud this file"))))

(unless (boundp '*emacs-configs*)
  (defvar *emacs-configs* nil)); actually supposed to be diefined in ~/.emacs
