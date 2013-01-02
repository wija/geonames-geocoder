#lang racket

;geocoder.rkt

(require db)
(require (planet dherman/memoize:3:1))

;====== GEOCODER ======

(define (geocode str
                 #:short-circuit? [short-circuit? #t]
                 #:level-sought [level-sought 2]
                 #:left-to-right? [left-to-right #f] 
                 #:label? [label? #t]) 
  (let ([r (geocode-cf #:str str
                       #:splitters (map (lambda (p) (lambda (s) (regexp-split p s))) (list #px","  #px"\\p{P}|\\p{Z}"))
                       #:left-to-right? left-to-right   
                       #:coder (lambda (t) (query-geoname (string-trim t)))
                       #:add-result reconcile-query-with-query-set
                       #:done? (lambda (result-list) (and short-circuit? (>= (length (lcd result-list)) (+ 1 level-sought))))
                       #:final lcd)])
    (if label? (label-hierarchy r) r)))

;This defines the control flow for geocode. The difference between the default arguments, below, and those used above may
;cast a bit of light, but I separated it to simplify debugging and changes; it's not of any real use for other purposes. 
;Basically, it tokenizes the string, applies a "coder" (here a geocoder) to each token and, if that coder fails to find a
;for the token, it applies the next available tokenizer (here first by commas, then by spaces, etc.). If at any time the 
;accumulated results will suffice (here, by default, when the "lowest common denominator" of the results provides at least
;country, admin1, and admin2), that is returned directly (using the continuation, k).
(define (geocode-cf  
         #:str str
         #:splitters splitters
         #:left-to-right? [left-to-right? #t]
         #:coder coder
         #:add-result [add-result cons]
         #:done? [done? #f]
         #:final [final (lambda (x) x)])
  (letrec ([h (lambda (tokens splitters result-list k)
                (if (or (empty? tokens) (done? result-list))
                    (k (final result-list))
                    (let ([r (coder (car tokens))])
                      (if (and r (not (empty? r))) ;#f and empty list both represent failure
                          (h (cdr tokens) splitters (add-result r result-list) k)
                          (if (not (empty? splitters))
                              (h (cdr tokens) splitters 
                                 (h (let ([x ((car splitters) (car tokens))]) (if left-to-right? x (reverse x))) 
                                    (cdr splitters) 
                                    result-list 
                                    k) 
                                 k)
                              (h (cdr tokens) splitters result-list k))))))])
    (call/cc (lambda (k) (h (list str) splitters '() k)))))

;====== GEONAMES DATABASE UTILITIES ======
;Note that these will not work on the geonames database as downloaded. Instead, the geonames-setup.txt script must be piped through
;sqlite to create new tables that are structured for efficient lookup.

(define gdb (sqlite3-connect #:database "Database/geonames.db" #:mode 'read-only))
(define (disconnect-from-geonames-database)
  (disconnect gdb))

;Note that a change in the schema of geonamesAll could also break geonames-fields->hierarchy
(define fields '("geonameid" "latitude" "longitude" "feature class" "feature code" "country code" "country geonameid" "admin1 geonameid" "admin2 geonameid" "admin3 geonameid" "admin4 geonameid"))
(define fields-string (string-join (map (lambda (s) (string-append "\"" s "\"")) fields) ", "))

(define query-geoname
  (let ([q-name (prepare gdb (string-append "SELECT " fields-string " FROM geonamesAll WHERE name=$1 COLLATE NOCASE;"))])
    (memo-lambda* (name)
      (query-rows gdb (bind-prepared-statement q-name (list name))))))
   
(define query-geoname-with-feature-code
  (let ([q-name-with-feature-code (prepare gdb (string-append "SELECT " fields-string " FROM geonamesAll WHERE \"feature code\"=$1 AND name=$2 COLLATE NOCASE;"))])
    (memo-lambda* (name feature-code)
      (query-rows gdb (bind-prepared-statement q-name-with-feature-code (list feature-code name))))))

(define geonameid->name
  (let ([q-shortName (prepare gdb "SELECT name FROM canonicalGeonames WHERE geonameid=$1;")])
    (memo-lambda* (geonameid)
                  (query-value gdb (bind-prepared-statement q-shortName (list geonameid))))))

(define geonameid->lat/long
  (let ([q-lat/long (prepare gdb "SELECT latitude, longitude FROM geonamesAll WHERE geonameid=$1;")])
    (memo-lambda* (geonameid)
                  (car (query-rows gdb (bind-prepared-statement q-lat/long (list geonameid)))))))

(define (geonames-fields->hierarchy qr)
  (vector->list (vector-take-right qr 5)))

(define (label-hierarchy h)
  (for/list ([(lbl gid) (in-parallel '(ADM0 ADM1 ADM2 ADM3 ADM4) h)])
    (list lbl gid (geonameid->name gid))))

;====== RECONCILING QUERY RESULTS ======

;Consistency here does not mean identity: If one query resolved to "Nebraska, USA" and another to "Omaha, Nebraska, USA", they
;are consistent. But consistency is stronger than overlap: "Illinois, USA" and "Nebraska, USA" are inconsistent. In other words,
;the criterion is that both hierarchies could refer - at however different levels of precision - to the same real world place. 
(define (hierarchies-consistent? h1 h2)
  (andmap (lambda (p1 p2) (or (sql-null? p1) (sql-null? p2) (= p1 p2))) h1 h2))

;Does one query result (a single location) have a geographical hierarchy consistent with any of the results for another query?
;In other words, the result "Omaha, Nebraska, USA" would be consistent with the set of results that contains both "USA" and
;"Mexico" but is inconsistent with a set of results that contains only "France" and "Mexico". 
(define (query-result-consistent-with-any? q1 q2s)
  (ormap (lambda (q2) (hierarchies-consistent? (geonames-fields->hierarchy q1) q2)) 
         (map geonames-fields->hierarchy q2s)))
  
;Are two sets of query results consistent and, if so, which of the possible geocodings for each term would be valid?
;If a query on the word "Nebraska" returns that it is either a town in Illinois, a town in North Carolina, or the state of 
;Nebraska, and another query on the word "Seward" returns that it is either a town in Alaska or a town in Nebraska, then
;the two sets of query results may be reconciled by dropping all but the state of Nebraska from the first set and all
;but the town in Nebraska from the second set. This returns two values new, reconciled values for the result sets of each query.
;Try, for example: (reconcile-queries (query-geoname "India") (query-geoname "Chennai"))
(define (reconcile-queries qs pqs)
  (let* ([fqs (filter (lambda (q) (query-result-consistent-with-any? q pqs)) qs)]
         [fpqs (filter (lambda (q) (query-result-consistent-with-any? q fqs)) pqs)])
    (values fqs fpqs)))

;Essentially, cons-ing a new query result set onto the list of past query result sets, but reconciling everything in the process. 
;Try, for example: (reconcile-query-with-query-set (query-geoname "Chennai") (list (query-geoname "India") (query-geoname "Chennai")))
(define (reconcile-query-with-query-set nqrs qrsl [acc '()])
  (if (empty? nqrs)
      qrsl ;a query that cannot be geocoded is consistent with anything, not nothing
      (if (empty? qrsl)
          (cons nqrs acc)
          (let-values ([(f-nqrs f-car-qrsl) (reconcile-queries nqrs (car qrsl))])
            (reconcile-query-with-query-set f-nqrs (cdr qrsl) (cons f-car-qrsl acc))))))

;What is the 'lowest common denominator' across the query result sets? If one query result set contains "Alaska, USA" 
;and "Nebraska, USA" and another query result set contains "Town of Seward, Nebraska, USA" and "Town of Seward, Alaska, USA",
;the two sets of query results are consistent. But all one can conclude is that the location being geocoded is in the USA; this
;is the lowest common denominator. Try, for example: 
;(lcd (reconcile-query-with-query-set (query-geoname "Chennai") (list (query-geoname "India") (query-geoname "Chennai"))))
(define (lcd qrs)
  (let ([transpose (lambda (a) 
                     (if (empty? a) a (apply map list a)))])
    (take-until (lambda (e) (false? e))
                (map (lambda (admlvl) 
                       (if (and (not (empty? admlvl))
                                (or (< (length admlvl) 2) 
                                    (apply = admlvl)))
                           (car admlvl)
                           #f))
                     (map (lambda (q)
                            (filter (lambda (e) (not (sql-null? e))) q))
                          (transpose (map geonames-fields->hierarchy (flatten qrs))))))))
  
;====== UTILITIES ======

;(take-until (lambda (e) (false? e)) '(a b #f c)) ==> '(a b)
(define (take-until pred lst)
  (let h [(lst lst) (acc '())]
    (if (or (empty? lst) (pred (car lst)))
        (reverse acc)
        (h (cdr lst) (cons (car lst) acc)))))

(provide geocode query-geoname geonameid->name geonameid->lat/long disconnect-from-geonames-database)
 

