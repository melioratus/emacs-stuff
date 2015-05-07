;;| start | end | effort | dependency |
;;|       |     |        |            |
;;
;;| start end | start effort  | start dependency | end effort      | end dependency  | effort dependency       |
;;| use       | calculate end | ERROR            | calculate start | calculate start | calculate start and end |
;;
;;| start end effort | start end dependency | start effort dependency | end effort dependency |
;;| ERROR            | ERROR                | ERROR                   | ERROR                 |
;;
;;| start end effort dependency |
;;| ERROR                       |

(defgroup org-gantt nil "Customization of org-gantt.")

(defcustom org-gantt-default-hours-per-day 8
  "The default hours in a workday. Use :hours-per-day to overwrite this value."
  :type '(integer)
  :group 'org-gantt)

(defconst start-prop :startdate
  "What is used as the start property in the constructed property list")

(defconst end-prop :enddate
  "What is used as the end property in the constructed property list")

(defconst effort-prop :effort
  "What is used as the effort property in the constructed property list")

(defun org-gantt-has-effort (aplist)
  "returns non-nil if an alist or plist contains effort"
(or (plist-get aplist ':effort)
    (assoc "effort" aplist)))

(defun org-gantt-has-startdate (aplist)
  "returns non-nil if an alist or plist contains a startdate"
(or (plist-get aplist ':scheduled)
    (assoc "SCHEDULED" aplist)))

(defun org-gantt-has-enddate (aplist)
  "returns non-nil if an alist or plist contains an enddate"
  (or (plist-get aplist ':deadline)
      (assoc "DEADLINE" aplist)))

(defun org-gantt-identity (x) x)

(defun org-gantt-get-planning-timestamp (element timestamp-type)
  "Get the timestamp from the planning element that belongs to a first-order headline
of the given element. timestamp-type is either ':scheduled or ':deadline"
(org-element-map element '(planning headline)
  (lambda (subelement) (org-element-property timestamp-type subelement))
  nil t 'headline))

(defun org-gantt-get-subheadlines (element)
  (org-element-map element 'headline (lambda (subelement) subelement)
		   nil nil 'headline))

(defun org-gantt-tp-compare (tp1 tp2 key compare-function)
  "Time property compare, works with nil."
  (and (org-element-property key tp1)
       (or (not (org-element-property key tp2))
	   (funcall compare-function (org-element-property key tp1) (org-element-property key tp2)))))

(defun org-gantt-timestamp-smaller (ts1 ts2)
  "Returns true iff timestamp ts1 is before ts2"
  (and ts1
       (or (not ts2)
           ;;I'm sure that's not how it should be done...
           (if (org-gantt-tp-compare ts1 ts2 ':year-start #'=)
               (if (org-gantt-tp-compare ts1 ts2 ':month-start #'=)
                   (if (org-gantt-tp-compare ts1 ts2 ':day-start #'=)
                       (if (org-gantt-tp-compare ts1 ts2 ':hour-start #'=)
                           (if (org-gantt-tp-compare ts1 ts2 ':minute-start #'=)
                               (org-gantt-tp-compare ts1 ts2 ':minute-start #'<))
                         (org-gantt-tp-compare ts1 ts2 ':hour-start #'<))
                     (org-gantt-tp-compare ts1 ts2 ':day-start #'<))
                 (org-gantt-tp-compare ts1 ts2 ':month-start #'<))
             (org-gantt-tp-compare ts1 ts2 ':year-start #'<))


           ;; (org-gantt-tp< ts1 ts2 ':year-start)
           ;; (org-gantt-tp< ts1 ts2 ':month-start)
           ;; (org-gantt-tp< ts1 ts2 ':day-start)
           ;; (org-gantt-tp< ts1 ts2 ':hour-start)
           ;; (org-gantt-tp< ts1 ts2 ':minute-start)
           )))

(defun org-gantt-timestamp-larger (ts1 ts2)
  "Returns true iff not timestamp ts1 is before ts2"
  (not (org-gantt-timestamp-smaller ts1 ts2)))

(defun org-gantt-subheadline-extreme (element comparator time-getter subheadline-getter)
  "Returns the smallest/largest timestamp of the subheadlines
of element according to comparator.
time-getter is the recursive function that needs to be called if
the subheadlines have no timestamp."
  (and
   element
   (let ((subheadlines (funcall subheadline-getter element)))
     (funcall
      time-getter
      (car
       (sort
	subheadlines
	(lambda (hl1 hl2)
	  (funcall comparator
		   (funcall time-getter hl1)
		   (funcall time-getter hl2)))))))))

(defun org-gantt-get-start-time (element)
""
(or
 (org-gantt-get-planning-timestamp element ':scheduled)
 (org-gantt-subheadline-extreme
  (cdr element)
  #'org-gantt-timestamp-smaller
  #'org-gantt-get-start-time
  #'org-gantt-get-subheadlines)))

(defun org-gantt-get-end-time (element)
""
(or
 (org-gantt-get-planning-timestamp element ':deadline)
 (org-gantt-subheadline-extreme
  (cdr element)
  (lambda (ts1 ts2)
    (not (org-gantt-timestamp-smaller ts1 ts2)))
  #'org-gantt-get-end-time
  #'org-gantt-get-subheadlines)))


(defun org-gantt-subheadlines-effort (element effort-getter)
  "Returns the sum of the efforts of the subheadlines
of element according to comparator.
effort-getter is the recursive function that needs to be called if
the subheadlines have no effort."
  (and
   element
   (let ((subheadlines (org-gantt-get-subheadlines element))
         (time-sum (seconds-to-time 0)))
     (dolist (sh subheadlines (if (= 0 (apply '+ time-sum)) nil time-sum))
       (let ((subtime (funcall effort-getter sh)))
         (when subtime
           (setq time-sum
                 (time-add time-sum subtime))))))))


(defun org-gantt-get-effort (element &optional use-subheadlines-effort)
  "Get the effort of the current element.
If use-subheadlines-effort is non-nil and element has no effort,
use sum of the efforts of the subelements."
  (let ((effort-time (org-gantt-effort-to-time (org-element-property :EFFORT element))))
    (or effort-time
        (and use-subheadlines-effort
             (org-gantt-subheadlines-effort (cdr element) #'org-gantt-get-effort)))))

(defun org-gantt-create-gantt-info (element)
  "Creates a gantt-info for element.
A gantt-info is a plist containing :name start-prop end-prop effort-prop :subelements"
  (list ':name (org-element-property ':raw-value element)
	':ordered (org-element-property :ORDERED element)
        start-prop (org-gantt-get-start-time element)
        end-prop (org-gantt-get-end-time element)
        effort-prop (org-gantt-get-effort element)
        ':subelements (org-gantt-crawl-headlines (cdr element))))

;; (defun org-gantt-subpropagate-start-date (element start-date)
;;   "Propagates end date from one subelement to start date of next subelement,
;; if element is ordered."
;;   (let ((subelements (plist-get element :subelements))
;; 	(ordered (plist-get element :ordered)))
;;     (if ordered
;; 	(dolist (se subelements)
;; 	  (let ((end (plist-get se end-prop)))
;; 	    (if end
;; 		))))))

(defun org-gantt-crawl-headlines (data)
  ""
  (let ((gantt-info-list
	 (org-element-map data 'headline #'org-gantt-create-gantt-info nil nil 'headline)))
    gantt-info-list))

(defun org-gantt-timestamp-to-string (timestamp)
  "should be replaced by org-timestamp-format, but that doesn't seem to work."
  (let ((ts (cadr timestamp)))
    (concat
     (number-to-string (plist-get ts ':year-start))
     "-"
     (number-to-string (plist-get ts ':month-start))
     "-"
     (number-to-string (plist-get ts ':day-start))
     )))

(defun org-gantt-get-extreme-date (data time-getter timestamp-comparer)
  "Get the first or last date (depending on timestamp-comparer)
of all the timestamps in data"
  (let ((timestamps
         (org-element-map data 'headline
           (lambda (headline)
             (funcall time-getter headline)))))
    (car (sort timestamps timestamp-comparer))))


(defun org-gantt-timestamp-to-time (timestamp &optional use-end)
  "Converts a timestamp to an emacs time.
If optional use-end is non-nil use the ...-end values of the timestamp."
  (and timestamp
       (if use-end
           (encode-time 0
                        (or (org-element-property :minute-end timestamp) 0)
                        (or (org-element-property :hour-end timestamp) 0)
                        (org-element-property :day-end timestamp)
                        (org-element-property :month-end timestamp)
                        (org-element-property :year-end timestamp))
         (encode-time 0
                      (or (org-element-property :minute-start timestamp) 0)
                      (or (org-element-property :hour-start timestamp) 0)
                      (org-element-property :day-start timestamp)
                      (org-element-property :month-start timestamp)
                      (org-element-property :year-start timestamp)))))

(defun org-gantt-time-to-timestamp (time)
  "Converts an emacs time to an org-mode timestamp."
  (let ((dt (decode-time time)))
    (and time
         (list 'timestamp
               (list :type 'active :raw-value (format-time-string "<%Y-%m-%d %a>" time)
                     :year-start (nth 5 dt) :month-start (nth 4 dt) :day-start (nth 3 dt)
                     :hour-start (nth 2 dt) :minute-start (nth 1 dt)
                     :year-end (nth 5 dt) :month-end (nth 4 dt) :day-end (nth 3 dt)
                     :hour-end (nth 2 dt) :minute-end (nth 1 dt))))))

(defun org-gantt-substring-if (string from to)
  "Returns substring if string, from and to are non-nil and from < to, otherwise nil"
  (and string from to (< from to) (substring string from to)))

(defun org-gantt-string-to-number (string)
  "string-to-number that returns 0 for nil argument"
  (if string (string-to-number string) 0))

(defun org-gantt-strings-to-time
  (hours-per-day days-per-month seconds-string minutes-string &optional hours-string
   days-string weeks-string months-string years-string)
  "Convert the given strings to time"
  (let ((time
         (seconds-to-time
          (+ (org-gantt-string-to-number seconds-string)
             (* 60 (org-gantt-string-to-number minutes-string))
             (* 3600 (org-gantt-string-to-number hours-string))
             (* 3600 hours-per-day (org-gantt-string-to-number days-string))
             (* 3600 hours-per-day days-per-month (org-gantt-string-to-number months-string))
             (* 3600 hours-per-day days-per-month 12 (org-gantt-string-to-number years-string))))))
    (if (= 0 (apply '+ time))
        nil
      time)))

(defun org-gantt-effort-to-time (effort &optional hours-per-day days-per-month)
  "Parses an effort timestring and returns it as emacs time representing a time difference.
Optional hours-per-day makes it possible to convert hour estimates into workdays."
  (and effort
       (let* ((years-string (org-gantt-substring-if effort 0 (string-match "y" effort)))
              (msp (if years-string (match-end 0) 0))
              (months-string (org-gantt-substring-if effort msp (string-match "m" effort)))
              (wsp (if months-string (match-end 0) msp))
              (weeks-string (org-gantt-substring-if effort wsp (string-match "w" effort)))
              (dsp (if weeks-string (match-end 0) wsp))
              (days-string (org-gantt-substring-if effort dsp (string-match "d" effort)))
              (hsp (if days-string (match-end 0) dsp))
              (hours-string (org-gantt-substring-if effort hsp (string-match ":" effort)))
              (minsp (if hours-string (match-end 0) hsp))
              (minutes-string (org-gantt-substring-if effort minsp (length effort)))
              (hpd (or hours-per-day org-gantt-default-hours-per-day))
             (dpm (or days-per-month 30)))
         (org-gantt-strings-to-time hpd dpm "0"
                                    minutes-string hours-string
                                    days-string weeks-string
                                    months-string years-string))))

(defun org-gantt-add-days (timestamp ndays)
  "Return a timestamp ndays advanced from the given timestamp"
  (org-gantt-time-to-timestamp
   (time-add (org-gantt-timestamp-to-time timestamp) (days-to-time ndays))))

(defun org-gantt-get-next-workday-if-day (timestamp)
  "Returns the next workday for the given timestamp, if the timestamp does not contain hour data.
If timestamp contains hour data, return timestamp.
Currently does not consider weekends, etc."
  (org-gantt-add-day-if-day timestamp))

(defun org-gantt-add-day-if-day (timestamp)
  "Return a timestamp added with one day if timestamp does not have hour information,
otherwise return timestamp."
  (if (org-element-property :hour-start timestamp)
      timestamp
    (org-gantt-add-days timestamp 1)))

(defun org-gantt-plist-get plist prop default
  "Same as plist-get, but returns default, if prop is not one of the properties of plist."
  (or (plist-get plist prop)
      default))

(defun org-gantt-propagate-order-timestamps (headline-list &optional is-ordered parent-start)
  "Propagate the timestamps of headlines that are ordered according to their superheadline.
Recursively apply to subheadlines."
  (let ((next-start (or (plist-get (car headline-list) start-prop) parent-start))
        (newlist nil))
    (dolist (headline headline-list newlist)
      (let ((replacement headline))
        (when is-ordered
          (setq replacement
                (plist-put replacement start-prop
                           (or (plist-get replacement start-prop) next-start)))
          (setq next-start (org-gantt-get-next-workday-if-day (plist-get replacement end-prop))))
        (when (plist-get replacement :subelements)
          (setq replacement
                (plist-put replacement :subelements
                           (org-gantt-propagate-order-timestamps
                            (plist-get replacement :subelements)
                            (or is-ordered (plist-get replacement :ordered))
                            (plist-get replacement start-prop)))))
        (setq newlist (append newlist (list replacement)))))))

(defun org-gantt-calculate-ds-from-effort (headline-list)
  "Calculates deadline or schedule from effort.
If a deadline or schedule conflicts with the effort, keep value and warn."
  (let ((newlist nil))
    (dolist (headline headline-list newlist)
      (let ((replacement headline)
            (start (plist-get headline start-prop))
            (end (plist-get headline end-prop))
            (effort (plist-get headline effort-prop)))
        (cond ((and start end effort)
               (warn "Conflicting start, end and effort in Headline '%s'." (plist-get replacement :name)))
              ((and start effort)
               (setq replacement
                     (plist-put replacement end-prop
                                (org-gantt-time-to-timestamp
                                 (time-add (org-gantt-timestamp-to-time start) effort)))))
              ((and effort end)
               (setq replacement
                     (plist-put replacement start-prop
                                (org-gantt-time-to-timestamp
                                 (time-subtract (org-gantt-timestamp-to-time end) effort))))))
        (when (plist-get replacement :subelements)
          (setq replacement
                (plist-put replacement :subelements
                           (org-gantt-calculate-ds-from-effort
                            (plist-get replacement :subelements)))))
        (setq newlist (append newlist (list replacement)))))))

(defun org-gantt-get-subheadline-start (headline)
  ""
  (or (plist-get headline start-prop)
      (plist-get
       (org-gantt-subheadline-extreme
        headline
        #'org-gantt-timestamp-smaller
        #'org-gantt-get-subheadline-start
        (lambda (hl) (org-gantt-propagate-ds-up (plist-get hl :subelements))))
       start-prop)))


(defun org-gantt-get-subheadline-end (headline)
  ""
  (or (plist-get headline end-prop)
      (plist-get
       (org-gantt-subheadline-extreme
        headline
        (lambda (ts1 ts2)
          (not (org-gantt-timestamp-smaller ts1 ts2)))
        #'org-gantt-get-subheadline-end
        (lambda (hl) (org-gantt-propagate-ds-up (plist-get hl :subelements))))
       end-prop)))

(defun org-gantt-propagate-ds-up (headline-list)
  "Prpagates start and end time from subelements."
  (let ((newlist nil))
    (dolist (headline headline-list newlist)
      (let ((replacement headline)
            (start (plist-get headline start-prop))
            (end (plist-get headline end-prop)))
        (setq replacement
              (plist-put replacement start-prop
                         (org-gantt-get-subheadline-start replacement)))
        (setq replacement
              (plist-put replacement end-prop
                         (org-gantt-get-subheadline-end replacement)))
        (setq newlist (append newlist (list replacement)))))))


(defun org-gantt-info-to-pgfgantt (gi &optional prefix ordered linked)
  "Creates a pgfgantt string from gantt-info gi"
  (let ((subelements (plist-get gi ':subelements)))
    (concat
     prefix
     (if subelements
         (if linked "\\ganttlinkedgroup" "\\ganttgroup")
       (if linked "\\ganttlinkedbar" "\\ganttbar"))
     "{" (plist-get gi ':name) "}"
     "{"
     (when (plist-get gi start-prop)
       (org-gantt-timestamp-to-string (plist-get gi start-prop)))
     "}"
     "{"
     (when (plist-get gi end-prop)
       (org-gantt-timestamp-to-string (plist-get gi end-prop)))
     "}"
     "\\\\\n"
     (when subelements
       (org-gantt-info-list-to-pgfgantt
	subelements
	(concat prefix "  ")
        (or ordered (plist-get gi :ordered)))))))

(defun org-gantt-info-list-to-pgfgantt (data &optional prefix ordered)
  "Gets a list of gantt-info-objects.
Returns a pgfgantt string representing that data."
  (concat
   (org-gantt-info-to-pgfgantt (car data) prefix ordered nil)
   (mapconcat (lambda (datum) (org-gantt-info-to-pgfgantt datum prefix ordered ordered)) (cdr data) "")))


(defun org-dblock-write:pgf-gantt-chart (params)
  "The function that is called for updating gantt chart code"
  (let (id idpos id-as-string view-file view-pos)
    (when (setq id (plist-get params :id))
      (setq id-as-string (cond ((numberp id) (number-to-string id))
			       ((symbolp id) (symbol-name id))
			       ((stringp id) id)
			       (t "")))
      (cond ((not id) nil)
	    ((eq id 'global) (setq view-pos (point-min)))
	    ((eq id 'local))
	    ((string-match "^file:\\(.*\\)" id-as-string)
	     (setq view-file (match-string 1 id-as-string)
		   view-pos 1)
	     (unless (file-exists-p view-file)
	       (error "No such file: \"%s\"" id-as-string)))
	    ))
    (with-current-buffer
        (if view-file
            (get-file-buffer view-file)
          (current-buffer))
      (let* ((titlecalendar (plist-get params :titlecalendar))
             (start-date (plist-get params start-prop))
             (end-date (plist-get params end-prop))
             (additional-parameters (plist-get params :parameters))
             (parsed-buffer (org-element-parse-buffer))
             (parsed-data
              (cond ((or (not id) (eq id 'global) view-file) parsed-buffer)
                    ((eq id 'local) (error "Local id handling not yet implemented"))
                    (t (org-element-map parsed-buffer 'headline
                         (lambda (element)
                           (if (equal (org-element-property :ID element) id) element nil))  nil t))))
             (org-gantt-info-list
              (org-gantt-propagate-ds-up
               (org-gantt-propagate-order-timestamps
                (org-gantt-calculate-ds-from-effort
                 (org-gantt-crawl-headlines parsed-data))))))
        (when (not parsed-data)
          (error "Could not find element with :ID: %s" id))
        (insert
         (concat
          "\\begin{ganttchart}[time slot format=isodate"
          (when additional-parameters
            (concat ", " additional-parameters))
          "]{"
          (or start-date
              (org-gantt-timestamp-to-string
               (org-gantt-get-extreme-date parsed-data #'org-gantt-get-start-time #'org-gantt-timestamp-smaller)))
          "}{"
          (or end-date
              (org-gantt-timestamp-to-string
               (org-gantt-get-extreme-date parsed-data #'org-gantt-get-end-time #'org-gantt-timestamp-larger)))
          "}\n"
          "\\gantttitlecalendar{"
          (if titlecalendar
              titlecalendar
            "year, month=name, day")
          "}\\\\\n"
          (org-gantt-info-list-to-pgfgantt org-gantt-info-list)
          "\\end{ganttchart}"))))))
