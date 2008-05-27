;;;; -*- Mode:Common-Lisp; Package:GBBOPEN; Syntax:common-lisp -*-
;;;; *-* File: /usr/local/gbbopen/source/gbbopen/1d-uniform-storage.lisp *-*
;;;; *-* Edited-By: cork *-*
;;;; *-* Last-Edit: Tue May 27 04:39:45 2008 *-*
;;;; *-* Machine: cyclone.cs.umass.edu *-*

;;;; **************************************************************************
;;;; **************************************************************************
;;;; *
;;;; *                 1d-Uniform-Buckets Space-Instance Storage
;;;; *
;;;; **************************************************************************
;;;; **************************************************************************
;;;
;;; Written by: Dan Corkill
;;;
;;; Copyright (C) 2003-2008, Dan Corkill <corkill@GBBopen.org>
;;; Part of the GBBopen Project (see LICENSE for license information).
;;;
;;; * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
;;;
;;;  04-23-06 Split out from storage.lisp.  (Corkill)
;;;  06-11-07 Converted 1d-uniform-buckets accessors from :prefix to modern
;;;           "-of" format.  (Corkill)
;;;
;;; * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *

(in-package :gbbopen)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (import '(gbbopen-tools::flag-set-p)))

;;; ===========================================================================
;;;  1D uniform-buckets storage (optimization of nD uniform-buckets storage)
;;;
;;;  Still to do: 
;;;    * add support for composite dimensions

(define-class 1d-uniform-buckets (storage)
  ((start)
   (size)
   (end)
   (buckets :type (simple-array t (*))))
  (:generate-initargs nil)
  (:export-class-name t))

;;; ---------------------------------------------------------------------------

(defmethod shared-initialize :after ((storage 1d-uniform-buckets)
                                     slot-names &rest initargs
                                     &key layout)
  (declare (ignore slot-names))
  (unless layout (missing-bucket-option-error storage ':layout initargs))
  (let ((layout (ensure-list-of-lists layout)))
    (check-storage-dimensions/layout-lengths storage layout initargs)
    (destructuring-bind (start end size)
	(car layout)
      (let ((number-of-buckets (ceiling (- end start) size)))
	(setf (start-of storage) start)
	(setf (size-of storage) size)
	;; note that the effective end value can be larger than the specified 
	;; `end' value:
	(setf (end-of storage) (ceiling (- end start) size))
        ;; make the bucket vector, adding three additional buckets in each
        ;; dimension for preceeding and following (out-of-bucket-range)
        ;; instances and for unbound-dimension-value:
	(setf (buckets-of storage)
	      (make-array `(,(+& 3 number-of-buckets))
                          :initial-element nil))))))

;;; ---------------------------------------------------------------------------

(defun print-1d-uniform-buckets-usage-message (buckets dimension-name)
  (format *trace-output* "~&;; - ~s: Using 1D-uniform buckets "
          dimension-name)
  (format *trace-output* "(~s bucket~:p)~&"
          buckets))

;;; ---------------------------------------------------------------------------

(defun do-1d-uniform-buckets-add/remove-action (instance storage verbose
						old-dimension-values
						bucket-action)
  (declare (type function bucket-action))
  (when verbose (print-storage-usage-message storage))
  (let* ((buckets (buckets-of storage))
	 (number-of-buckets (-& (length buckets) 3))
	 (start (start-of storage))
	 (size (size-of storage)))
    (dolist (dimension-name (dimension-names-of storage))
      (multiple-value-bind (dimension-value dimension-type 
                            comparison-type
                            composite-type composite-dimension-name)
          (if old-dimension-values
              ;; This isn't ready yet for composites!
              (cdr (assoc dimension-name old-dimension-values :test #'eq))
              (instance-dimension-value instance dimension-name))
        (declare (ignore dimension-type comparison-type 
                         composite-dimension-name))
        (flet ((do-a-value (dimension-value)
                 (cond
                  ;; scalar value:
                  ((or (numberp dimension-value)
                       (eq dimension-value unbound-value-indicator))
                   (let ((bucket-index (bounded-uniform-bucket-index 
                                        dimension-value 
                                        start size number-of-buckets)))
                     (when verbose
                       (print-1d-uniform-buckets-usage-message 
                        1 dimension-name))
                     (funcall bucket-action instance buckets bucket-index)))
                  ;; interval value:
                  (t (let ((start-index (bounded-uniform-bucket-index 
                                         (interval-start dimension-value)
                                         start size number-of-buckets))
                           (end-index (bounded-uniform-bucket-index 
                                       (interval-end dimension-value)
                                       start size number-of-buckets)))
                       (when verbose
                         (print-1d-uniform-buckets-usage-message
                          (1+& (-& end-index start-index))
                          dimension-name))
                       (loop for bucket-index of-type fixnum 
                           from start-index to end-index do
                             (funcall bucket-action instance 
                                      buckets bucket-index)))))))
          (cond 
           ;; set composite dimension value:
           ((eq composite-type ':set)
            (map nil #'do-a-value dimension-value))
           ;; sequence composite dimension value:
           ((eq composite-type ':sequence)
            (nyi))
           ;; series composite dimension value:
           ((eq composite-type ':series)
            (nyi))
           ;; incomposite or unbound dimension value:
           (t (do-a-value dimension-value))))))))

;;; ---------------------------------------------------------------------------

(defmethod add-instance-to-storage ((instance standard-unit-instance)
				    (storage 1d-uniform-buckets) 
				    verbose)
  (let ((excess-count 0))
    (do-1d-uniform-buckets-add/remove-action 
	instance storage verbose nil
	;; bucket-action:
	#'(lambda (instance buckets bucket-index)
	    (declare (type (simple-array t (*)) buckets))
	    (declare (type fixnum bucket-index))
	    (push instance (svref buckets bucket-index))
	    (incf& excess-count)))
    ;; save the excess count:
    (incf& (excess-locators-of storage) 
           ;; remove the non-excess count for this instance:
	   (1-& excess-count))))

;;; ---------------------------------------------------------------------------

(defmethod remove-instance-from-storage ((instance standard-unit-instance)
					 (storage 1d-uniform-buckets) 
					 old-dimension-values
                                         dimensions-being-changed
					 verbose)
  (declare (ignore dimensions-being-changed))
  (let ((excess-count 0))
    (do-1d-uniform-buckets-add/remove-action 
	instance storage verbose old-dimension-values
	;; bucket-action:
	#'(lambda (instance buckets bucket-index)
	    (declare (type (simple-array t (*)) buckets))
	    (declare (type fixnum bucket-index))
	    (setf (svref buckets bucket-index)
		  (delq instance (svref buckets bucket-index)))
	    (decf& excess-count)))
    ;; save the excess count:
    (decf& (excess-locators-of storage) 
	   ;; add back in the non-excess count for this instance:
	   (1+& excess-count))))
  
;;; ---------------------------------------------------------------------------

(defun determine-1d-uniform-storage-extents (storage 
					     disjunctive-dimensional-extents)
  ;;; Returns two values:
  ;;; 1) a list of disjunctive extents
  ;;; 2) a boolean indicating if a full-map was requested (via 't)
  (let ((extents nil))
    (unless (eq disjunctive-dimensional-extents 't)
      (let ((dimension-names (dimension-names-of storage)))
        (dolist (dimensional-extents disjunctive-dimensional-extents)
          (dolist (dimension-name dimension-names)
            (let ((dimensional-extent 
                   (assoc dimension-name dimensional-extents :test #'eq)))
              (when dimensional-extent
                (destructuring-bind (extent-dimension-name
                                     dimension-type . new-extents)
                    dimensional-extent
                  (declare (ignore extent-dimension-name dimension-type))
                  (dolist (new-extent new-extents)
                    (setf extents
                          (merge-ordered-extent new-extent extents)))))))
          ;; sort by increasing interval starts:
          (setf extents (sort extents #'< :key #'car)))))
    (or extents 
        (values (list infinite-extent) 't))))
  
;;; ---------------------------------------------------------------------------

(defun do-1d-uniform-map-actions (fn storage disjunctive-dimensional-extents 
				  verbose)
  (declare (type function fn))
  (when verbose (print-storage-usage-message storage))
  (multiple-value-bind (disjunctive-storage-extents full-map-p)
      (determine-1d-uniform-storage-extents 
       storage disjunctive-dimensional-extents)
    (let* ((buckets (buckets-of storage))
           (number-of-buckets (-& (length buckets) 3))
	   (start (start-of storage))
	   (size (size-of storage))
	   (bucket-count 0))
      (declare (type (simple-array t (*)) buckets))
      ;; unbound instances req'd:
      (when full-map-p
	(when verbose
	  (print-1d-uniform-buckets-usage-message ':unbound-value '*))
        ;; NEED TO DO SOMETHING TO THE INDEXES TO CAPTURE THE UNBOUND BUCKETS:
        ())
      (dolist (region disjunctive-storage-extents)
        (multiple-value-bind (start-index end-index)
            (bounded-uniform-bucket-interval-indexes
             (first region)
             (second region)
             start size number-of-buckets)
          (when verbose
            (print-1d-uniform-buckets-usage-message
             (max& 1 (-& end-index start-index))
             '*))
          (let ((bucket-index start-index))
            (declare (type fixnum bucket-index))
            (until (>& bucket-index end-index)
              (incf& bucket-count)
              (let ((instances (svref buckets (the fixnum bucket-index))))
                (dolist (instance instances)
                  (funcall fn instance instance)))
              (incf& bucket-index)))))
      ;; record the bucket count:
      (let ((find-stats *find-stats*))
	(when find-stats 
	  (incf (find-stats.bucket-count find-stats) bucket-count))))))

;;; ---------------------------------------------------------------------------

(defmethod map-marked-instances-on-storage (fn (storage 1d-uniform-buckets)
					    disjunctive-dimensional-extents 
					    verbose)
  (do-1d-uniform-map-actions 
      #'(lambda (key instance)
	  (declare (ignore key))
          (when (mbr-instance-mark-set-p instance)
            (funcall (the function fn) instance)))
    storage disjunctive-dimensional-extents verbose))

;;; ---------------------------------------------------------------------------

(defmethod map-all-instances-on-storage (fn (storage 1d-uniform-buckets)
					 disjunctive-dimensional-extents 
					 verbose)
  (do-1d-uniform-map-actions 
      #'(lambda (key instance)
	  (declare (ignore key))
	  (funcall (the function fn) instance))
    storage disjunctive-dimensional-extents verbose))

;;; ===========================================================================
;;;				  End of File
;;; ===========================================================================

