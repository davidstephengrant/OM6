(in-package :om)


;-------------------------
; PARSER de COOM vers POLY
;--------------------------


(defvar *coom-stream* nil)
(defvar *cur-token* nil)

(defmacro get-token () 
  `(setf *cur-token* 
         (if (stream-eofp *coom-stream*) (error "EOF") ; 'end
             (read *coom-stream*))))

(defmacro cur-token () '*cur-token*)

(defmethod parse ((token (eql '<poly>)))
  (loop until (eq (get-token) '</poly>) 
        do  (cur-token)
        collect (parse (cur-token))))

(defmethod parse ((token (eql '<temperament>)))
  (loop until (eq (get-token) '</temperament>) 
        do  (cur-token)
        collect (parse (cur-token))))

(defmethod parse ((token (eql '<voice>)))
  (build-voice (loop until (eq (get-token) '</voice>)
                     collect (parse (cur-token)))))

(defmethod parse ((token (eql '<measure>)))
  (build-measure (loop until (eq (get-token) '</measure>)
        collect (parse (cur-token)))))

(defmethod parse ((token (eql '<meter>)))
  (build-meter 
   (loop until (eq (get-token) '</meter>)
                     collect (parse (cur-token)))))

(defmethod parse ((token (eql '<TP>)))
  (loop until (eq (get-token) '</TP>)
        collect (parse (cur-token))))

(defmethod parse ((token (eql '<C>)))
  (build-chord 
   (loop until (eq (get-token) '</C>)
         collect (parse (cur-token)))))

(defmethod parse ((token (eql '<d>)))
  (prog1 
    (parse (get-token))
    (get-token)))

(defmethod parse ((token (eql '<n>)))
  (loop until (eq (get-token) '</n>)
         collect (parse (cur-token))))

(defmethod parse ((token (eql '<r>)))
  (build-rest
   (loop until (eq (get-token) '</r>)
         for token = (parse (cur-token))
         collect (if (numberp token) (- token) token))))


(defmethod parse ((token t)) 
  token)




;----------

(defvar *coom-midics* nil)
(defvar *coom-ties* nil)


(defun build-meter (meter) meter)

(defun build-chord (chord) 
  (let ((break nil))
    (when (eq (first chord) '<br>) (setf break t) (pop chord))
    (let ((dur (pop chord)))
      (push (mapcar 'first chord) *coom-midics*)
      (push (mapcan #'(lambda (note) 
                        (if  (memq (second note) '(ts tc)) note nil))
                    chord)
            *coom-ties*)
      (if (null break) dur (float dur)))))

(defun build-rest (rest) 
  (if (eq (first rest) '<br>) (float (second rest)) (first rest)))

(defun build-measure (measure)
  (let* ((nbbeats (first (first measure)))
         (beat-unit (second (first measure))))
         (setf measure (handle-breaks  measure))
         (list (list nbbeats (/ 4096 beat-unit))
               (build-beats (rest measure) beat-unit))))


(defun handle-breaks (measure)
  (let* ((beats (rest measure))
         (newbeats 
          (loop while beats
              with beat
              with group = nil
              with result = nil
              do (setf beat (pop beats))
              do (if (listp beat)
                     (progn
                       (when (not (null group))
                         (push (handle-break-group (reverse group)) result)
                         (setf group nil))
                       (push beat result))
                     (cond
                      ;;; previously here: (push beat group)
                      ;;; => I suspect this would grate an unnecessary level of grouping
                      ;;;; A tester !
                      ((integerp beat) (push beat result))
                      ((float beat) 
                       (when (not (null group))
                         (push (handle-break-group (reverse group)) result))
                       (setf group (list (round beat))))))
              finally
                (return 
                (if group
                  (reverse (cons (handle-break-group (reverse group)) result))
                  (reverse result))))))
    (cons (first measure) newbeats)))

(defun handle-break-group (group)
  (cond 
   ((null (rest group)) (first group))
   (t (let ((sum (loop for b in group sum (abs b))))
        `( 1 ,sum 1 ,sum ,. group)))))

(defun build-beats (beats beat-unit)
  (mapcar 
   #'(lambda (beat) 
       (if (atom beat)
         (/ (round beat) beat-unit)
         (build-tuplet beat beat-unit)))
   beats))

(defun build-voice (voice)
  (when (find nil voice :key 'cadr)
    ;;; remove empty measures at the end of NAP files
    (om-beep-msg "Warning: Empty measure(s) ignored in score import")
    (setf voice (remove nil voice :key 'cadr)))
  (prog1 
      (make-instance 'voice
                     :tree   (integerize-tree (cons '? (list (or voice '(((4 4) (-1)))))))
                     :chords (reverse *coom-midics*)
                     :ties (reverse *coom-ties*)
                     )
    (setf *coom-midics* nil *coom-ties* nil)))


;; n unit-n pour p unit-p n:p
;; (n unit-n p unit p chord chord <tuplet> silence chord ..)

(defun build-tuplet (tuplet father-unit)
  (let* ((n (pop tuplet))
         (unit-n (pop tuplet))
         (p (pop tuplet))
         (unit-p (pop tuplet))
         (tuplet-extent (* p (/ unit-p father-unit))))
    (declare (ignore n unit-n))
    (list tuplet-extent 
          (build-beats tuplet unit-p))))
         
    
    
(defun integerize-group (group) 
       (let* ((beats (second group))
              (ppcm (reduce  
                     #'(lambda (ppcm beat)
                         (setf beat (if (listp beat) (first beat) (abs beat)))
                         (lcm (denominator beat) ppcm))
                     beats
                     :initial-value 1)))
         (list (first group)
               (mapcar #'(lambda (beat) 
                           (if (listp beat)
                             (integerize-group 
                              (cons (* ppcm (first beat)) (rest beat)))
                             (* ppcm beat)))
                       beats))))


(defun integerize-tree (tree)  
  (list (first tree)  (mapcar 'integerize-group (second tree))))


               
;-----------



(defmethod string2Poly ((string string))
  (if (string-equal (subseq string 0 6) "<POLY>")
      (let ((*coom-stream* (make-string-input-stream string))
            (*coom-midics* nil) (*coom-ties* nil))
        (handler-bind ((error #'(lambda (err)
                                  (om-message-dialog (format nil "An error occurred while reading the score data.~%=> ~A" err))
                                  (om-abort))))
          (get-token)
          (make-instance 'poly :voices (rest (parse '<poly>)))))
    (progn
      (om-message-dialog "Error: no score data found in the system clipboard")
      nil)))
      


;------------------------------
; GENERATEUR de POLY vers COOM
;-------------------------------


(defvar *coom-stream-out* nil)

(defmacro coom-open-out-stream () '(setf *coom-stream-out* (make-string-output-stream)))
(defmacro coom-out (&rest body) `(format *coom-stream-out* ,. body))
(defmacro coom-stream-string () '(prog1 (get-output-stream-string *coom-stream-out*)
                                   (setf *coom-stream-out* nil)))
                                   

(defmethod container->coom-string ((self om::poly) index &optional (approx 2))
  (declare (ignore index))
  (let ((voices (om::inside self)))
    (coom-open-out-stream)
    (coom-out "<POLY> ~%")
    (coom-out  "<TEMPERAMENT> ~D </TEMPERAMENT> ~%" approx)
    (loop for staff in voices
          for i = 1 then (+ i 1)
          do (container->coom-string staff i approx))
    (coom-out "</POLY> ~%")
    (coom-stream-string)))



(defmethod container->coom-string ((self om::voice) index &optional (approx 2))
    (declare (ignore index))
    (let ((mesures (om::inside self))) 
    (coom-out "<VOICE> ~%")
    (loop for mes in mesures
          for i = 1 then (+ i 1)
          do (container->coom-string mes i approx))
    (coom-out "</VOICE> ~%")))


;symb-beat-val= For a key signature equivalent to 3//3 will be the half note (blanche)
;real-beat-val= For the same key sign, this will be the halfnote of a triplet (blanche de triolet)
;These refer to the beats in a measure, and for special cases using non-standard key signature


(defmethod container->coom-string ((self om::measure) index &optional (approx 2))
  (declare (ignore index))
  (let* ((tree (om::tree self))
         (real-beat-val (/ 1 (om::fdenominator (first tree))))
         (symb-beat-val (/ 1 (om::find-beat-symbol (om::fdenominator (first tree))))))
    (coom-out "<MEASURE> ~%<METER> ~D ~D </METER> ~%" 
              (fnumerator (first tree)) 
              (/ 4096 (fdenominator (first tree))))
    (loop for obj in (inside self)
          do (let* ((dur-obj-noire (/ (extent obj) (qvalue obj)))
                    (factor (/ (* 1/4 dur-obj-noire) real-beat-val)))
               (container->coom-string obj (* symb-beat-val factor)  approx))))
  (coom-out "</MEASURE> ~%"))


(defmethod container->coom-string ((self chord) durtot &optional (approx 2))
    (coom-out "<C> ~%")
    (when (or (measure-p (parent self))
              (and (zerop (offset self))
                   (zerop (loop for group = self then (parent group)
                                while (not (measure-p (parent group)))
                                for offset = (offset self) then (+ offset (offset group))
                                finally (return offset)))))
      (coom-out "<BR> ~%"))
    (coom-out "<D> ~D </D> ~%" (* 4096 durtot))
    (loop for note in (inside self)
          for coom-tie = (coom-note-tie note)
          do (coom-out "<N> ~D ~D </N> ~% " (approx-m (midic note) approx) coom-tie)
          )
    (coom-out "</C> ~%"))


(defmethod coom-note-tie ((self note))
  (case (tie self)
    (begin "TS")
    (continue "TC")
    (end "TE")
    (t "")))


(defmethod container->coom-string ((self rest) durtot &optional (approx 2))
  (declare (ignore approx))
  (coom-out "<R> ~%")
  (when (or (not (om::group-p (parent self)))  (= (offset self) 0))
    (coom-out "<BR> ~%"))
  (coom-out "<D> ~D </D>~%" (* 4096 durtot))
  (coom-out "</R> ~%"))


(defmethod container->coom-string ((self om::group) durtot &optional (approx 2))
  (let* (
         (num (or (om::get-group-ratio self)  (om::extent self)))
         ;(num (or (my-get-group-ratio self)  (extent self))) ;A VERIFIER extent for groups that are not tuplets
         (denom (find-denom num durtot))
         (num (if (listp denom) (car denom) num))
         (denom (if (listp denom) (second denom) denom))
         (unite (/ durtot denom))
         (inside (inside self))
         (sympli (/ num denom)))

    (cond
     ((not (get-group-ratio self))
      ;(not (my-get-group-ratio self)) 
      (loop for obj in inside
            do (let* ((dur-obj (/ (/ (extent obj) (qvalue obj))  (/ (extent self) (qvalue self)))))
                 (container->coom-string obj (* dur-obj durtot)  approx))))
     ((= sympli 1)
      (loop for obj in inside

            append (let* ((operation (/ (/ (extent obj) (qvalue obj))  (/ (extent self) (qvalue self))))
                      (dur-obj (numerator operation)))
                 (setf dur-obj (* dur-obj (/ num (denominator operation))))
                 (container->coom-string obj (* dur-obj unite)  approx))))

     (t
      (coom-out "<TP> ~D ~D ~D ~D ~%" num (* 4096 unite ) denom (* 4096 unite))
      (loop for obj in inside
            do (let* ((operation (/ (/ (extent obj) (qvalue obj))  (/ (extent self) (qvalue self))))
                      (dur-obj (numerator operation)))
                 (setf dur-obj (* dur-obj (/ num (denominator operation))))
                 (container->coom-string obj (* dur-obj unite)  approx)))
      (coom-out "</TP> ~%")))))




;---------
;interface
;---------
(defvar *coam* :coom)

(defun from-coda ()
  ;(om-get-scrap-flavor-data *coam*)
  (om-get-clipboard))

(defun to-coda (str &optional mode)
   (when str 
     (if (equal mode 'clipboard)
         (om-set-clipboard str)
       (let ((filename (or (and (pathnamep mode) mode)
                           (om-choose-new-file-dialog :directory (def-save-directory) 
                                                      :name (and (stringp mode) mode)
                                                      :prompt "New Export file"
                                                      :types '("OM/Finale/NAP format" "*.om")))))
         (when filename 
           (WITH-OPEN-FILE (out filename :direction :output 
                                :if-does-not-exist :create :if-exists :supersede)
             (format out "~A" str)))
         ))))


(defmethod! finale-export ((self poly) &optional (temperament 2) (mode 'clipboard))
  :icon 353
  :indoc '("a voice or poly"  "approx (2,4,8)")
  :initvals '((make-instance 'voice)  2)
  :doc "Send a voice or a poly object to Finale through the clipboard "
  (to-coda (container->coom-string self 0 temperament) mode)
  
  )


(defmethod! finale-export  ((self voice) &optional (temperament 2) (mode 'clipboard))
  (to-coda  (container->coom-string (make-instance 'poly :voices (list self)) 0 temperament) mode))

(defmethod! finale-import  (&optional path)
  :icon 354
  :doc "Constructs a poly object from the data exported by NAP. "
  (let* ((file (or path (om-choose-file-dialog :types '("OM/NAP format" "*.om")))))
    (when file
      (let ((string (if (probe-file file)
                        (string-from-file file)
                      (progn (om-message-dialog (format nil "Error: file ~s not found." (namestring file))) nil)
                      )))
  (when (and string (stringp string))
    (string2Poly string))
  ))))



(defun string-from-file (pathname)
  (let ((tmpbuffer (om-make-buffer))
        (str nil))
    (om-buffer-insert-file tmpbuffer pathname)
    (setf str (om-buffer-text tmpbuffer))
    (om-kill-buffer tmpbuffer)
    str))
  

;-----
;debug


#|
(defun before&after-bin (den)
  "Find the symbolic value from mesuare denominateur."
  (let ((exp -5))
    (loop while (>= den (expt 2 exp)) do
          (setf exp (+ exp 1)))
    (list (expt 2 (- exp 1)) (expt 2 exp))))
|#


#|
(defmethod my-get-group-ratio ((self group) )
  (let* ((tree (tree self))
         (extent (car tree))
         (addition (loop for item in (second tree) sum (floor (abs (if (listp item) (car item) item))))))
    (cond
     ((= (round (abs addition)) 1) nil)
     ;( (integerp (/ extent addition))  addition)
     ( (or (and (integerp (/ extent addition)) 
                (power-of-two-p (/ extent addition)))
           (and (integerp (/ addition extent)) 
                (power-of-two-p (/ addition extent))))  nil)
     (t addition))))
|#

(defmethod my-get-group-ratio ((self group) )
  (let* ((tree (tree self))
         (extent (car tree))
         (addition (loop for item in (second tree) sum (floor (abs (if (listp item) (car item) item))))))
    (cond
     ((= (round (abs addition)) 1) nil)
     ;( (integerp (/ extent addition))  addition)
     ( (or (and (integerp (/ extent addition)) 
                (power-of-two-p (/ extent addition)))
           (and (integerp (/ addition extent)) 
                (power-of-two-p (/ addition extent))))  nil)
     (t addition))))


(defmethod* Objfromobjs ((Self poly) (Type voice))
  (ObjFromObjs (first (voices self)) type))               
               

#|
(string2Poly
"<POLY> 
<TEMPERAMENT> 2 </TEMPERAMENT> 
<VOICE> 
<Measure> 
<METER> 4 1024 </METER> 
<TP> 3 512 2 512  
<TP> 5 128 4 128  
<C> 
<BR> 
<D> 128 </D>  
<N> 6000  </N> 
<N> 7000  </N> 
<N> 7600  </N> 
</C> 
<C> 
<D> 128 </D>  
<N> 6800  </N> 
</C> 
<C> 
<D> 128 </D>  
<N> 4900  </N> 
<N> 6800  </N> 
<N> 7800  </N> 
</C> 
<C> 
<D> 128 </D>  
<N> 7200  </N> 
</C> 
<C> 
<D> 128 </D>  
<N> 7200  </N> 
</C> 
</TP>   
<C> 
<D> 512 </D>  
<N> 5200  </N> 
<N> 7100  </N> 
<N> 7700  </N> 
<N> 8600  </N> 
</C> 
<C> 
<D> 512 </D>  
<N> 6600  </N> 
</C> 
</TP>   
<TP> 5 256 4 256  
<C> 
<BR> 
<D> 256 </D>  
<N> 6600  </N> 
</C> 
<R> 
<D> 512 </D>  
</R> 
<C> 
<D> 256 </D>  
<N> 6500  </N> 
<N> 7600  </N> 
<N> 8800  </N> 
</C> 
<C> 
<D> 256 </D>  
<N> 6800   TS  </N> 
</C> 
</TP>   
<C> 
<BR> 
<D> 1024 </D>  
<N> 6800   TC  </N> 
</C> 
<C> 
<BR> 
<D> 1024 </D>  
<N> 5000   TS  </N> 
<N> 6800   TE  </N> 
<N> 7600   TS  </N> 
</C> 
</Measure> 
<Measure> 
<METER> 3 1024 </METER> 
<TP> 6 512 4 512  
<C> 
<BR> 
<D> 1024 </D>  
<N> 5000   TE  </N> 
<N> 6800  </N> 
<N> 7600   TE  </N> 
</C> 
<C> 
<D> 1536 </D>  
<N> 7100  </N> 
</C> 
<C> 
<D> 512 </D>  
<N> 6600  </N> 
</C> 
</TP>   
<R> 
<BR> 
<D> 1024 </D>  
</R> 
</Measure> 
<Measure> 
<METER> 7 512 </METER> 
<TP> 3 1024 2 1024  
<C> 
<BR> 
<D> 1024 </D>  
<N> 5900  </N> 
<N> 7000  </N> 
<N> 8300  </N> 
</C> 
<R> 
<D> 1024 </D>  
</R> 
<C> 
<D> 1024 </D>  
<N> 7100   TS  </N> 
</C> 
</TP>   
<C> 
<BR> 
<D> 1536 </D>  
<N> 7100   TE  </N> 
</C> 
</Measure> 
<Measure> 
<METER> 4 1024 </METER> 
<TP> 7 512 6 512  
<R> 
<BR> 
<D> 1536 </D>  
</R> 
<C> 
<D> 1024 </D>  
<N> 7000  </N> 
</C> 
<R> 
<D> 512 </D>  
</R> 
<C> 
<D> 512 </D>  
<N> 5900  </N> 
<N> 7000  </N> 
<N> 7700  </N> 
</C> 
</TP>   
<TP> 5 256 4 256  
<TP> 3 128 2 128  
<C> 
<BR> 
<D> 256 </D>  
<N> 7300  </N> 
</C> 
<C> 
<D> 128 </D>  
<N> 6700  </N> 
</C> 
</TP>   
<C> 
<D> 256 </D>  
<N> 5100  </N> 
<N> 7000  </N> 
<N> 8800  </N> 
</C> 
<C> 
<D> 256 </D>  
<N> 7300  </N> 
</C> 
<TP> 3 256 2 256  
<C> 
<D> 256 </D>  
<N> 6800  </N> 
</C> 
<C> 
<D> 256 </D>  
<N> 5000  </N> 
<N> 5900  </N> 
<N> 7600  </N> 
<N> 8300  </N> 
</C> 
<C> 
<D> 256 </D>  
<N> 7000  </N> 
</C> 
</TP>   
</TP>   
</Measure> 
</VOICE>
</Poly>
")
|#