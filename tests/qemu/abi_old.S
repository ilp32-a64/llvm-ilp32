// What LLVM generated for clang_deref/clang_deref9/clang_use_returned before the GNU ILP32 pointer
// extension fix: the pointer is used as received, upper 32 bits included.
	.text
	.p2align 2
	.globl	old_deref
	.type	old_deref, %function
old_deref:
	ldr	w0, [x0]
	ret
	.size	old_deref, .-old_deref

	.p2align 2
	.globl	old_deref9
	.type	old_deref9, %function
old_deref9:
	ldr	x8, [sp]
	ldr	w0, [x8]
	ret
	.size	old_deref9, .-old_deref9

	.p2align 2
	.globl	old_use_returned
	.type	old_use_returned, %function
old_use_returned:
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp
	bl	gcc_give
	ldr	w0, [x0]
	ldp	x29, x30, [sp], #16
	ret
	.size	old_use_returned, .-old_use_returned

	.section .note.GNU-stack,"",%progbits
