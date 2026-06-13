; TECM8 shell compatibility include.
;
; New code should include shell-resolver.asm directly when it only needs command
; resolution. Include shell-program.asm only after shell-resolver.asm when the
; prompt/input shell loop is also needed.

        .include "shell-resolver.asm"
        .include "shell-program.asm"
