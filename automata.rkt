#lang racket
(require racket/hash)
(provide (all-defined-out))

(define ACTIONS# 2)
(define ACTIONS (list 'C 'D))
(define (random-action)
  (list-ref ACTIONS (random ACTIONS#)))

(struct automaton (head body) #:transparent)
; body is a hash table of states
(struct state (action dispatch) #:transparent)

(define (make-random-automaton states#)
  (define initial-current (random states#))
  (define to-detach (random states#))
  (define (make-head) (hash 'INITIAL initial-current
                            'CURRENT initial-current
                            'PAYOFF 0))
  (define ids (build-list states# values))
  (define (make-body) (apply hash (flatten (map list ids (make-states)))))
  (define (make-states) (build-list states# make-state))
  (define (make-state _) (state (random-action) (make-transition)))
  (define (make-transition)
    (hash 'C (random states#)
          'D (random states#)))
  (automaton (make-head) (make-body)))

(define (reset a) ; reset
  (match-define (automaton head body) a)
  (define new-head
    (hash-set head 'CURRENT (hash-ref head 'INITIAL)))
  (automaton new-head body))

;; CLASSIC AUTOMATA
(define (cooperates)
  (define head (hash 'INITIAL 0 'CURRENT 0 'PAYOFF 0))
  (define body (hash 0 (state 'C (hash 'C 0 'D 0))))
  (automaton head body))

(define (defects)
  (define head (hash 'INITIAL 0 'CURRENT 0 'PAYOFF 0))
  (define body (hash 0 (state 'D (hash 'C 0 'D 0))))
  (automaton head body))

(define (tit-for-tat)
  (define head (hash 'INITIAL 0 'CURRENT 0 'PAYOFF 0))
  (define body (hash 0 (state 'C (hash 'C 0 'D 1))
                     1 (state 'D (hash 'C 0 'D 1))))
  (automaton head body))

(define (grim-trigger)
  (define head (hash 'INITIAL 0 'CURRENT 0 'PAYOFF 0))
  (define body (hash 0 (state 'C (hash 'C 0 'D 1))
                     1 (state 'D (hash 'C 1 'D 1))))
  (automaton head body))

;;IMMUTABLE MUTATION
(define (mutate-marginally a)
  (match-define (automaton head body) a)
  (define l (hash-count body))
  (define mutate-initial (random l))
  (define mutate-state (random l))
  (match-define (state action dispatch) (hash-ref body mutate-state))
  (define r (random 3))
  (define new-head
    (cond [(zero? r) (hash-set head 'INITIAL mutate-initial)]
          [else head])) ; leave unchanged
  (define new-body
    (cond [(zero? r) body] ; leave unchanged
          [(= r 1)
           (hash-set body mutate-state
                     (state (random-action) dispatch))]
          [(= r 2)
           (hash-set body mutate-state
                     (state action
                            (hash-set dispatch (random-action) (random l))))]))
  (automaton new-head new-body))

(define (add-state a)
  (match-define (automaton head body) a)
  (define l (hash-count body))
  (define (make-transition)
    (hash 'C (random (+ l 1))
          'D (random (+ l 1))))
  (define (make-state) (state (random-action) (make-transition)))
  (define mutate-state (random l))
  (match-define (state action dispatch) (hash-ref body mutate-state))
  (define new-body
    (hash-union
     (hash-set body mutate-state
              (state action
                     (hash-set dispatch (random-action) l)))
     (hash l (make-state))))
  (automaton head new-body))

(define (random-mem l)
  (list-ref l (random (length l))))

;; for detach and add state, use mutable would be much shorter

(define (detach-state a)
  (match-define (automaton head body) a)
  (define l (hash-count body))
  (cond
   [(= l 1) (mutate-marginally a)]
   [else (begin
           (define (random-but n r)
             (random-mem (remq mutate-state (build-list n values))))
           (define mutate-state (random l))
           (define (check-rule rule)
             (match-define (cons opponent-action reaction) rule)
             (if (= mutate-state reaction)
                 (cons opponent-action (random-but l mutate-state))
                 rule))
           (define (check-dispatch rules)
             (apply hash
                    (map check-rule (hash->list rules))))
           (define (check-state a-state)
             (match-define (state action rules) a-state)
             (struct-copy state a-state [dispatch (check-dispatch rules)]))
           (define new-body
             (for/list([i (in-range l)])
               (list i
                     (check-state (hash-ref body i)))))
           (automaton head (apply hash (flatten new-body))))]))

(define (mutate a)
  (define r (random 3))
  (cond [(zero? r) (mutate-marginally a)]
        [(= r 1) (add-state a)]
        [(= r 2) (detach-state a)]))

;; INTERACTION: PAIR-MATCH
(define PAYOFF-TABLE
  (list
   (list (cons 3 3) (cons 0 4))
   (list (cons 4 0) (cons 1 1))))
(define (payoff action1 action2)
  (define (convert action)
    (for/last ([i (in-range ACTIONS#)]
      #:final (equal? action (list-ref ACTIONS i)))
      i))
  (list-ref (list-ref PAYOFF-TABLE (convert action1))
            (convert action2)))

;; continuation probability
(define (interact au1 au2 rounds delta)
  (match-define (automaton head1 body1) au1)
  (match-define (automaton head2 body2) au2)
  (define-values (next1 next2 pay1 pay2 round-results)
    (for/fold ([current1 (hash-ref head1 'CURRENT)]
               [current2 (hash-ref head2 'CURRENT)]
               [payoff1 (hash-ref head1 'PAYOFF)]
               [payoff2 (hash-ref head2 'PAYOFF)]
               [round-results '()])
              ([_ (in-range rounds)])
      #:final (> (random) delta)
      (match-define (state action1 dispatch1) (hash-ref body1 current1))
      (match-define (state action2 dispatch2) (hash-ref body2 current2))
      (match-define (cons pay1 pay2) (payoff action1 action2))
      (define n1 (hash-ref dispatch1 action2))
      (define n2 (hash-ref dispatch2 action1))
      (define round-result (list pay1 pay2))
      (values n1 n2 
              (+ payoff1 pay1)
              (+ payoff2 pay2)
      ;(values n1 n2
      ;        (+ payoff1 (* (expt delta _) pay1))
      ;        (+ payoff2 (* (expt delta _) pay2))
              (cons round-result round-results))))
  (values
   (reverse round-results)
   (automaton (hash-set head1 'PAYOFF pay1) body1)
   (automaton (hash-set head2 'PAYOFF pay2) body2)
          ))


#|
;; EXPORT MATHA CODE OF THE MACHINE
(define (generate-state-code table)
  (define l (vector-length table))
  (define state-numbers (vector-map state-action table))
  (define state-labels
    (vector-map (lambda (x)
                  (cond ([zero? x] "C")
                        ([= 1 x] "D")))
                state-numbers))
  (define state-code
    (apply string-append
           (add-between
            (for/list ([i l])
              (string-append (number->string i) " -> Placed[\"~a\", Center]"))
            ", ")))
  (apply format
         (list* state-code (vector->list state-labels))))

(define (scan-duplicate dispatch)
  (match-define (vector a1 a2) dispatch)
  (if (= a1 a2) (list "\"C,D\"" "\"C,D\"")
      (list "\"C\"" "\"D\"")))

(define (generate-dispatch-code state# dispatch)
  (define l (vector-length dispatch))
  (define ending (scan-duplicate dispatch))
  (remove-duplicates
   (for/list ([i l])
     (string-append
      "Labeled["
      (number->string state#)
      " -> "
      (number->string (vector-ref dispatch i))
      ", "
      (list-ref ending i)
      "] \n"))))

(define (generate-dispatch-codes table)
  (define dispatches (vector-map state-dispatch table))
  (define dispatch-code
    (for/list ([i (vector-length dispatches)])
      (generate-dispatch-code i (vector-ref dispatches i))))
  (apply string-append (add-between (flatten dispatch-code) ", ")))

(define (generate-matha-code au name)
  (match-define (automaton current initial payoff states) au)
  (string-append
   "VertexCircle[{xc_, yc_}, name_, {w_, h_}] := Disk[{xc, yc}, .1];\n"
   name "Graph =\n"
   "   Graph[{-1 -> " (number->string initial) " ,\n"
   (generate-dispatch-codes states)
   "     },\n"
   "   EdgeShapeFunction -> \n"
   "    GraphElementData[\"EdgeShapeFunction\", \"FilledArrow\"],\n"
   "   VertexStyle -> LightGray,\n"
   "   VertexShapeFunction -> VertexCircle,\n"
   "   VertexLabels -> {" (generate-state-code states) "}\n"
   "   ];\n"
   "G = Graphics[{White, Disk[{0, 0}, 0.2]}];\n"
   "Show[" name "Graph, G]\n"
   "(*Export[\"" name ".png\",S]*)\n \n"))

(define (export-matha-code au name)
  (with-output-to-file AUTO-CODE
    (lambda () (printf (generate-matha-code au name)))
    #:exists 'append))

(define (export-matha-codes a-list name)
  (for ([i (length a-list)])
    (export-matha-code (list-ref a-list i)
                       (string-append (symbol->string name)
                                      (number->string i)))))
|#