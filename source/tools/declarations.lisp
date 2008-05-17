;;;; -*- Mode:Common-Lisp; Package:GBBOPEN-TOOLS; Syntax:common-lisp -*-
;;;; *-* File: /usr/local/gbbopen/source/tools/declarations.lisp *-*
;;;; *-* Edited-By: cork *-*
;;;; *-* Last-Edit: Sat May 17 16:59:07 2008 *-*
;;;; *-* Machine: cyclone.cs.umass.edu *-*

;;;; **************************************************************************
;;;; **************************************************************************
;;;; *
;;;; *                      Optimization Declarations
;;;; *
;;;; **************************************************************************
;;;; **************************************************************************
;;;
;;; Written by: Dan Corkill
;;;
;;; Copyright (C) 2002-2008, Dan Corkill <corkill@GBBopen.org>
;;; Part of the GBBopen Project (see LICENSE for license information).
;;;
;;; * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
;;;
;;;  07-18-02 File created.  (Corkill)
;;;  01-18-04 Added NYI error signalling.  (Corkill)
;;;  06-22-04 Added (debug 0) to with-full-optimization.  (Corkill)
;;;  01-26-08 Added make-keys-only-hash-table-if-supported.  (Corkill)
;;;
;;; * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

(in-package :gbbopen-tools)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (export '(*generate-nyi-errors*	; not documented
	    allow-redefinition
            make-keys-only-hash-table-if-supported ; not documented
	    nyi                         ; not documented
	    unbound-value-indicator
	    without-cmu/sbcl-optimization-warnings ; not documented
	    with-full-optimization)))

;;; ---------------------------------------------------------------------------

(defmacro allow-redefinition (&body body)
  `(#+allegro excl:without-redefinition-warnings
    #+lispworks system::without-warning-on-redefinition
    #+clisp handler-case
    #-(or allegro clisp lispworks)
    progn
    (progn ,@body)
    #+clisp (clos:clos-warning ())))

;;; ---------------------------------------------------------------------------

(defmacro with-full-optimization ((&key) &body body)
  ;;  The feature :full-safety disables with-full-optimization optimizations:
  `(locally #+full-safety ()
            #-full-safety (declare (optimize (speed 3) (safety 0) (debug 0)
					     (compilation-speed 0)))
            ,@body))

;;; ---------------------------------------------------------------------------

(defmacro without-cmu/sbcl-optimization-warnings (&body body)
  ;;  Suppress CMUCL and SBCL compilation notes on failed optimizations:
  `(locally 
     ;; Inhibit CMUCL optimization warnings:
     #+cmu (declare (optimize (extensions:inhibit-warnings 3)))
     ;; Eliminate SBCL optimization warnings by lowering the speed setting.
     ;; (It would be better to find a direct way to suppress these.)
     #+sbcl (declare (optimize (speed 1)))
     ,@body))

;;; ---------------------------------------------------------------------------
;;;   NYI wrapper (for use with code that is not yet ready for prime time)

(defvar *generate-nyi-errors* 't)

(defmacro nyi (&body body)
  `(progn
     (when *generate-nyi-errors*
       (error "Not yet implemented."))
     ,@body))

;;; ---------------------------------------------------------------------------

(defconstant unbound-value-indicator
    ;; We use Allegro's keyword symbol (as good as any choice...)
    ':---unbound---)

;;; ---------------------------------------------------------------------------
;;;  Keys-only hash tables

(defun make-keys-only-hash-table-if-supported (&rest args)
  ;; Return a keys only hash table, if supported by the CL implementation;
  ;; otherwise return a regular hash table:
  (declare (dynamic-extent args))
  (apply #'make-hash-table 
         ;; Use Allegro's sans-value hash tables:
         #+allegro :values #+allegro nil
         args))

;;; Add the keys-only-hash-table feature, if supported:
#+allegro
(pushnew ':has-keys-only-hash-tables *features*)

;;; ===========================================================================
;;;				  End of File
;;; ===========================================================================


