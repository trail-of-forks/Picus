#lang rosette
; this implements the propagation & preserving algorithm with base lemma
(require
    (prefix-in tokamak: "../tokamak.rkt")
    (prefix-in utils: "../utils.rkt")
    (prefix-in config: "../config.rkt")
    (prefix-in r1cs: "../r1cs-grammar.rkt")
)
(provide (rename-out
    [apply-inc apply-inc]
))

(define (apply-inc
    r0 nwires mconstraints input-list output-list
    xlist original-definitions original-cnsts
    xlist0 alternative-definitions alternative-cnsts
    arg-timeout arg-smt
    solver:get-theory solver:solve solver:state-smt-path parser:parse-r1cs optimizer:optimize rint:interpret-r1cs
    )

    ; state variable of whether the current round has unknown/timeout queries
    ; need to reset to #f at each new round
    (define round-has-unknown null)

    (define partial-cmds (r1cs:append-rcmds
        (r1cs:rcmds (list
            (r1cs:rcmt (r1cs:rstr "================================"))
            (r1cs:rcmt (r1cs:rstr "======== original block ========"))
            (r1cs:rcmt (r1cs:rstr "================================"))
        ))
        original-definitions
        original-cnsts
        (r1cs:rcmds (list
            (r1cs:rcmt (r1cs:rstr "==================================="))
            (r1cs:rcmt (r1cs:rstr "======== alternative block ========"))
            (r1cs:rcmt (r1cs:rstr "==================================="))
        ))
        alternative-definitions
        alternative-cnsts
    ))

    ; keep track of index of xlist (not xlist0 since that's incomplete)
    (define known-list (filter
        (lambda (x) (! (null? x)))
        (for/list ([i (range nwires)])
            (if (utils:contains? xlist0 (list-ref xlist i))
                i
                null
            )
        )
    ))
    (define unknown-list (filter
        (lambda (x) (! (null? x)))
        (for/list ([i (range nwires)])
            (if (utils:contains? xlist0 (list-ref xlist i))
                null
                i
            )
        )
    ))
    (printf "# initial knwon-list: ~a\n" known-list)
    (printf "# initial unknown-list: ~a\n" unknown-list)

    ; returns final unknown list, and if it's empty, it means all are known
    ; and thus verified
    (define (inc-solve kl ul)
        (printf "# ==== new round inc-solve ===\n")
        (define tmp-kl (for/list ([i kl]) i))
        (define tmp-ul (list ))
        (define changed? #f)
        (for ([i ul])
            (printf "  # checking: (~a ~a), " (list-ref xlist i) (list-ref xlist0 i))
            (define known-cmds (r1cs:rcmds (for/list ([j tmp-kl])
                (r1cs:rassert (r1cs:req (r1cs:rvar (list-ref xlist j)) (r1cs:rvar (list-ref xlist0 j))))
            )))
            (define final-cmds (r1cs:append-rcmds
                (r1cs:rcmds (list (r1cs:rlogic (r1cs:rstr (solver:get-theory)))))
                partial-cmds
                (r1cs:rcmds (list
                    (r1cs:rcmt (r1cs:rstr "============================="))
                    (r1cs:rcmt (r1cs:rstr "======== known block ========"))
                    (r1cs:rcmt (r1cs:rstr "============================="))
                ))
                known-cmds
                (r1cs:rcmds (list
                    (r1cs:rcmt (r1cs:rstr "============================="))
                    (r1cs:rcmt (r1cs:rstr "======== query block ========"))
                    (r1cs:rcmt (r1cs:rstr "============================="))
                ))
                (r1cs:rcmds (list
                    (r1cs:rassert (r1cs:rneq (r1cs:rvar (list-ref xlist i)) (r1cs:rvar (list-ref xlist0 i))))
                    (r1cs:rsolve )
                ))
            ))
            ; perform optimization
            (define optimized-cmds ((optimizer:optimize) final-cmds))
            (define final-str (string-join ((rint:interpret-r1cs) optimized-cmds) "\n"))
            (define res ((solver:solve) final-str arg-timeout #:output-smt? arg-smt))
            (cond
                [(equal? 'unsat (car res))
                    (printf "verified.\n")
                    (set! tmp-kl (cons i tmp-kl))
                    (set! changed? #t)
                ]
                [(equal? 'sat (car res))
                    (printf "sat.\n")
                    (set! tmp-ul (cons i tmp-ul))
                ]
                [else
                    (printf "skip.\n")
                    (set! round-has-unknown #t)
                    (set! tmp-ul (cons i tmp-ul))
                ]
            )
        )
        ; return
        (if changed?
            (inc-solve (reverse tmp-kl) (reverse tmp-ul))
            tmp-ul
        )
    )

    (set! round-has-unknown #f)
    (define res-ul (inc-solve known-list unknown-list))
    ; return
    (values res-ul round-has-unknown)
)
