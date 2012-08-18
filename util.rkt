#lang racket

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Convenience macros to define contract and/or provide (similar to
;; define/contract).

(define-syntax define/contract/provide
  (syntax-rules ()
    [(_ (id . args) contract body ...)
     (begin
       (define/contract (id . args) contract body ...)
       (provide/contract [id contract]))]
    [(_ id contract expr)
     (begin
       (define/contract id contract expr)
       (provide/contract [id contract]))] ))

(define-syntax define/provide
  (syntax-rules ()
    [(_ (id . args) body ...)
     (begin
       (define (id . args) body ...)
       (provide id))]
    [(_ id expr)
     (begin
       (define id expr)
       (provide id))] ))

(provide define/contract/provide
         define/provide)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (any/c ... -> string?)  Given any number of Racket identifiers or
;; literals, convert them to a string. Non-literals are printed as
;; "expression = value".  For use with e.g. log-debug which takes a
;; single string? not format or printf style, plus, we want to show
;; the expression = value thing.
(define-syntax tr
  (syntax-rules ()
    [(_ e)
     (if (or (string? (syntax-e #'e))
             (number? (syntax-e #'e)))
         (format "~a" e)
         (format "~s=~a"
                 (syntax->datum #'e)
                 e))]
    [(_ e0 e1 ...)
     (string-append (tr e0)
                    " "
                    (tr e1 ...))]))

(provide tr)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(require xml)
(define/contract/provide (tags xpr tag [direct-child-of #f])
  ((xexpr/c symbol?)
   (symbol?)
   . ->* . (listof xexpr/c))
  ;; Given an x-expression return a list of all the elements starting
  ;; with tag, at any depth. Even if a tag is nested inside the same
  ;; tag, so be careful using this with hierarchical XML.
  (define (do xpr parent)
    (cond
     [(empty? xpr) '()]
     [else
      (define this-xpr (first xpr))
      (cond
       [(and (list? this-xpr)
             (not (empty? this-xpr)))
        (define this-tag (first this-xpr))
        (define found? (and (equal? this-tag tag)
                            (or (not direct-child-of)
                                (equal? direct-child-of parent))))
        (append (if found?
                    (list this-xpr)       ;found one!
                    '())
                (do this-xpr this-tag)    ;down
                (do (rest xpr) parent))]  ;across
       [else
        (do (rest xpr) parent)])]))       ;across
  (do xpr #f))

;; ;; test
;; (define x '(root ()
;;              (a () "a")
;;              (a () (b () "b kid of a"))
;;              (b () "b kid of root")))
;; (tags x 'b)
;; (tags x 'b 'a)

(define/provide (first-tag-value x t [def #f])
  ;; Given a (listof x-expr), return just the first elements with tag
  ;; `t`
  (match (tags x t)
    ['() def]
    [(list (list _ v) ...) (first v)]
    [(list (list _ _ v) ...) (first v)]
    [else def]))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; attribs <-> alist.
;; Former is (list/c symbol? string?), latter is (cons/c symbol? string?).
;; Although alists are standard Scheme/Racket fare, with xexprs we want
;; attribs, so will need to convert between sometimes.
(define/provide (attribs->alist a)
  (define (list->cons l)
    (cons (first l) (second l)))
  (map list->cons a))

(define/provide (alist->attribs a)
  (define (cons->list c)
    (list (car c) (cdr c)))
  (map cons->list a))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Percent-encoding. Racket net/uri-codec does RFC 2396 but we want
;; RFC 3986.

(require net/uri-codec)

(define (percent-encode c)
  (string-upcase (format "%~x" (char->integer c))))

(define (char->pair c)
  (cons c (percent-encode c)))

;; The extra chars that uri-encode misses but 3986 wants
(define chars-to-encode (list #\! #\'#\(#\) #\*))
(define h (for/hash ([c (in-list chars-to-encode)])
              (values c (percent-encode c))))

(define/provide (uri-encode/rfc-3986 s)
  (for/fold ([accum ""])
      ([c (in-string (uri-encode s))])
    (string-append accum (hash-ref h c (make-string 1 c)))))

;; Like Racket alist->form-urlencoded, but:
;; 1. Works on any dict? (not just an association list of cons pairs).
;; 2. Uses RFC 3986 encoding.
(define/contract/provide (dict->form-urlencoded xs)
  (dict? . -> . string?)
  (define (value x)
    (match x
      [(list x) (value x)]
      [(? string? x) x]
      [else (error 'dict->form-urlencoded
                   "values must be (or/c string? (list/c string?))")]))
  (string-join (for/list ([(k v) (in-dict xs)])
                   (format "~a=~a"
                           k
                           (uri-encode/rfc-3986 (value v))))
               "&"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(struct endpoint (host ssl?) #:transparent)
(provide (struct-out endpoint))

(define/contract/provide (endpoint->host:port x)
  (endpoint? . -> . string?)
  (match-define (endpoint host ssl?) x)
  (string-append host (if ssl? ":443" "")))

(define/contract/provide (endpoint->uri x path)
  (endpoint? string? . -> . string?)
  (match-define (endpoint host ssl?) x)
  (string-append (if ssl? "https" "http")
                 "://"
                 host
                 (if ssl? ":443" "")
                 path))