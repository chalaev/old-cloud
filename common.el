;;; -*- mode: Emacs-Lisp;  lexical-binding: t; -*-

;; some of these functions are published on https://github.com/chalaev/elisp-goodies

;; I try to get rid of loop and other common-lisp stuff here

(unless (functionp 'gensym)
(let ((counter 0))
  (defun gensym(&optional starts-with)
    "for those who miss gensym from Common Lisp"
    (unless starts-with (setf starts-with "gs"))
    (let (sym)
      (while (progn
               (setf sym (make-symbol (concat starts-with (number-to-string counter))))
               (or (special-form-p sym) (functionp sym) (macrop sym) (boundp sym)))
        (incf counter))
      (incf counter)
      sym))))

(defun firstN(lista N)
  "returning first N elments of the list"
  (when (and (< 0 N) (car lista))
    (cons (car lista) (firstN (cdr lista) (1- N)))))

(defvar *all-chars*
  (let ((forbidden-symbols '(?! ?@ ?# ?$ ?% ?& ?* ?( ?) ?+ ?= ?/ 
                      ?{ ?} ?[ ?] ?: ?\; ?< ?>
                      ?_ ?- ?| ?, ?. ?` ?' ?~ ?^ ?\")))
    (append
     (loop for i from ?A to ?Z unless (member i forbidden-symbols) collect i)
     (loop for i from ?a to ?z unless (member i forbidden-symbols) collect i)
     (loop for i from ?0 to ?9 unless (member i forbidden-symbols) collect i))))

(defun time< (t1 t2)
  (and
    (time-less-p (time-add t1 1) t2)
    (not (time-less-p (time-add t2 1) t1))))

(defun safe-mkdir (dirname)
  (if (file-exists-p dirname)
      (if (file-directory-p dirname)
          (progn (message "not creating already existing directory %s" dirname) :exists)
        (message "file exists with the same name as working directory %s" dirname) :file)
    (condition-case err
        (progn (make-directory dirname) t)
      (file-already-exists (message "Strange, may be the file already exists (but this was checked!). %s" (error-message-string err)) nil); when file exists
      (file-error (message "Probably, you have not permission to create this directory: %s" (error-message-string err)) :permission))))

(defun safe-delete-file (FN)
  (let (failed)
  (condition-case err (delete-file FN)
    (file-error
     (clog :info "cannot delete file %s; %s" FN (error-message-string err))
     (setf failed t)))
  (not failed)))

(defun rand-str (N)
  (apply #'concat
         (loop repeat N collect (string (nth (random (length *all-chars*)) *all-chars*)))))

(defun new-file-name (cloud-dir)
  (let (new-fname error-exists); экзистенциальная ошибка: какое бы имя я не выдумывал, а такой файл уже существует!
    (loop repeat 10 do (setf new-fname (rand-str 3))
          while (setf error-exists (file-exists-p (concat cloud-dir new-fname))))
    (if error-exists nil new-fname)))

(defun perms-from-str (str); e.g., (perms-from-str "-rw-rw----") => #o660
  (let ((text-mode (reverse (cdr (append str nil)))) (mode 0) (fac 1))
    (loop for c in text-mode for i from 0
          unless (= c ?-) do (incf mode fac)
          do (setf fac (* 2 fac)))
    mode))

(defun begins-with* (str what)
  (let ((ok t))
  (needs ((pattern
	   (case what; [\s-\|$] matches space or EOL
	     (:time "\s*\"\\([^\"]+\\)\"[\s-\|$]")
	     (:integer "\s+\\([[:digit:]]+\\)[\s-\|$]")
	     (:string "\s+\\(\".+\"+\\)[\s-\|$]")
	     (:other "\s+\\([^\s]+\\)[\s-\|$]"))
	   (clog :error "invalid type %s in begins-with" what))
	  (string-match pattern str)
	  (MB (match-begin 1)) (ME (match-end 1))
	  (matched (match-string 1 str)))
	 (case what
	   (:time
	      (let ((PTS (parse-time-string matched)))
		(if (setf ok (car PTS))
		  (cons
			(apply #'encode-time PTS)
			(substring-no-properties str (1+ ME)))
		  (clog :error "can not parse date/time string: %s"))))
	   (:integer (cons
		      (string-to-int matched)
		      (substring-no-properties str ME)))
	   (:string
	    (cons
	     (substring-no-properties matched (1+ MB) (1- ME)); убираем кавычки
	     (substring-no-properties str ME)))
	   (:other
	    (cons (string-trim matched)
		  (substring-no-properties str ME)))))))

(defun begins-with (str what)
  (cond
   ((consp what)
      (let (result (ok t))
	(dotimes (i (cdr what))
	  (needs (ok (BW (begins-with str (car what)) (bad-column "N/A (begins-with)" i)))
		 (push (car BW) result)
		 (setf str (cdr BW))))
	(cons (reverse result) str)))
   ((eql :strings what)
    (let (BW result)
      (while (setf BW (begins-with* str :string))
	(push (car BW) result)
	(setf str (cdr BW)))
      (cons (reverse result) str)))
   (t (begins-with* str what))))

(defun cloud-locate-FN (name)
  "find file by (true) name"
  (find name *file-DB* :key #'plain-name :test #'string=))

(defun cloud-locate-CN (name)
  "find file by (ciper) name"
  (find name *file-DB* :key #'cipher-name :test #'string=))

(defun format-file (DB-rec)
  (format "%S %s %s %s %d %S"
	  (aref DB-rec plain)
	  (aref DB-rec cipher)
	  (aref DB-rec uname)
	  (aref DB-rec gname)
	  (aref DB-rec modes); integer
	  (format-time-string "%04Y-%02m-%02d %H:%M:%S %Z" (aref DB-rec mtime))))

(defun plain-name  (df)(aref df plain))

(defun DBrec-from-file(file-name)
  (when-let ((FA (file-attributes file-name 'string)))
    (let ((DBrec (make-vector (length DB-fields) nil)))
      (destructuring-bind
	  (uid gid acess-time mod-time status-time size ms void inode fsNum)
	  (cddr FA)
	(aset DBrec-from-file uname "unused")
	(aset DBrec-from-file gname gid)
	(aset DBrec-from-file mtime mod-time); list of 4 integers
	(aset DBrec-from-file modes (perms-from-str ms))
	(aset DBrec-from-file plain file-name))
      DBrec)))

;; grab-parameter is no more used as of 2020-09-18
;; (defun grab-parameter (str parname); (grab-parameter "contentsName=z12"  "contentsName") => "z12"
;;   (when (string-match (concat parname "=\\(\\ca+\\)$") str)
;;       (match-string 1 str)))
