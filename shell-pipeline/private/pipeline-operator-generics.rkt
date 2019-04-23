#lang racket/base

(provide

 define-pipeline-operator/no-kw
 =composite-pipe=
 =pipeline-segment=
 =basic-object-pipe/expression=
 =basic-unix-pipe=

 transform-starter-segment
 transform-joint-segment

 (for-syntax

  pipeline-starter
  pipeline-joint
  not-pipeline-op

  dispatch-pipeline-starter
  dispatch-pipeline-joint

  core-pipeline-starter
  core-pipeline-joint
  pipeline-starter-macro
  pipeline-joint-macro


  ))

(require
 "basic-unix-pipe-helper-funcs.rkt"
 "mostly-structs.rkt"
 (for-syntax
  racket/base
  syntax/parse
  syntax-generic2
  ))

(begin-for-syntax
  (define-syntax-generic core-pipeline-starter)
  (define-syntax-generic core-pipeline-joint)
  (define-syntax-generic pipeline-starter-macro)
  (define-syntax-generic pipeline-joint-macro)

  #|
  ?? Does <syntax-generic>? return #t for an identifier bound to it or to an application form using it?

  (my-generic? #'id)
  (my-generic? #'(id arg ...))

  Both, apparently!  The predicate is supposed to match on the same
  things that the Racket macro expander matches on when detecting macro
  uses.  So it matches the form for identifier macros as well as for
  head-of-list macros.
  |#

  ;; For splitting macro to delimit pipeline segments
  (define-syntax-class pipeline-starter
    (pattern op:id #:when (or (core-pipeline-starter? #'(op))
                              (pipeline-starter-macro? #'(op)))))
  (define-syntax-class pipeline-joint
    (pattern op:id #:when (or (core-pipeline-joint? #'(op))
                              (pipeline-joint-macro? #'(op)))))
  (define-syntax-class not-pipeline-op
    (pattern (~and (~not x:pipeline-joint)
                   (~not x:pipeline-starter))))




  (define (pipeline-starter->core stx)
    (cond
      [(core-pipeline-starter? stx) stx]
      [(pipeline-starter-macro? stx)
       (pipeline-starter->core
        (apply-as-transformer pipeline-starter-macro 'expression #f stx))]
      [else (error 'pipeline-starter->core "not a pipeline starter ~a\n" stx)]))
  (define (pipeline-joint->core stx)
    (cond
      [(core-pipeline-joint? stx) stx]
      [(pipeline-joint-macro? stx)
       (pipeline-joint->core
        (apply-as-transformer pipeline-joint-macro 'expression #f stx))]
      [else (error 'pipeline-joint->core "not a pipeline joint ~a\n" stx)]))

  (define (dispatch-pipeline-starter stx)
    (define core-stx (pipeline-starter->core stx))
    (apply-as-transformer core-pipeline-starter 'expression #f core-stx))
  (define (dispatch-pipeline-joint stx)
    (define core-stx (pipeline-joint->core stx))
    (apply-as-transformer core-pipeline-joint 'expression #f core-stx))
  )

;; basic definition form, wrapped by the better one in "pipeline-operators.rkt"
(define-syntax define-pipeline-operator/no-kw
  (syntax-parser [(_ name as-starter as-joint outside-of-rash)
                  #'(define-syntax name
                      (generics
                       [pipeline-starter-macro as-starter]
                       [pipeline-joint-macro as-joint]
                       ;; TODO - how to do this with syntax-generics?  It was in the paper, but I don't see it in the library.
                       ;[racket-macro outside-of-rash]
                       ))]))

(define-syntax (transform-starter-segment stx)
  (syntax-parse stx [(_ arg ...) (dispatch-pipeline-starter #'(arg ...))]))
(define-syntax (transform-joint-segment stx)
  (syntax-parse stx [(_ arg ...) (dispatch-pipeline-joint #'(arg ...))]))

(define-syntax =composite-pipe=
  (generics
   [core-pipeline-starter
    (syntax-parser
      [(_ (start-op:pipeline-starter start-arg:not-pipeline-op ...)
          (join-op:pipeline-joint join-arg:not-pipeline-op ...) ...)
       #'(composite-pipeline-member-spec
          (list (transform-starter-segment start-op start-arg ...)
                (transform-joint-segment join-op join-arg ...) ...))])]
   [core-pipeline-joint
    (syntax-parser
      [(_ (op:pipeline-joint arg:not-pipeline-op ...) ...+)
       #'(composite-pipeline-member-spec
          (list (transform-joint-segment op arg ...) ...))])]))

;; For first-class segments or as an escape to construct specs with the function API.
(define-syntax =pipeline-segment=
  (let ([op (syntax-parser
              [(_ segment ...)
               #'(composite-pipeline-member-spec (list segment ...))])])
    (generics
     [core-pipeline-starter op]
     [core-pipeline-joint op])))

;; Pipe for just a single expression that isn't considered pre-wrapped in parens.
(define-syntax =basic-object-pipe/expression=
  (generics
   [core-pipeline-starter
    (syntax-parser
      [(_ e) #'(object-pipeline-member-spec (λ () e))])]
   [core-pipeline-joint
    (syntax-parser
      [(_ e)
       #'(object-pipeline-member-spec
          (λ (prev-ret)
            (syntax-parameterize ([current-pipeline-argument
                                   (make-rename-transformer #'prev-ret)])
              e)))])]))


(define-syntax =basic-unix-pipe=
  (generics
   [core-pipeline-starter basic-unix-pipe-transformer]
   [core-pipeline-joint basic-unix-pipe-transformer]))

#;(define-syntax =bind=
  (generics
   [core-pipeline-starter
    (syntax-parser [(~and stx (_ arg1 arg ...))
                    (raise-syntax-error '=bind=
                                        "Can't be used as a pipeline starter"
                                        #'stx
                                        #'arg1)])]
   [core-pipeline-joint
    (λ (stx)
      ;; TODO - this should call the `bind!` function.  To do that I need a defenition context made with make-def-ctx (which should have a longer name).  I also need a fresh scope probably.  So maybe I need to thread these things through the splitter function?  And this needs different handling for the first-class-pipeline-spec generator case vs the run-pipeline case (the first-class case should allow bindings to be seen later in the pipeline, but nowhere else).  And I need special handling when I'm in an expression context vs a definition context -- in a definition context I should collect all the bindings and re-bind them outside, maybe with a define-values form that is just assigned to the inner version of the variables.
      aoeu)]))
