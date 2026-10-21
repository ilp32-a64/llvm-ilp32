/*
 * GCC-compiled side of the GCC <-> clang AArch64 ILP32 pointer passing test.
 *
 * AAPCS64 and GCC leave the upper 32 bits of a pointer passed or returned in an
 * X register (or an 8-byte stack slot) unspecified; the receiver has to clear
 * them. This program creates such pointers on purpose and hands them to
 * clang-compiled code (abi_clang.c). As a control, the same calls are made to
 * old_* (abi_old.S), which uses the registers as received the way LLVM did
 * before the fix: those must crash, otherwise the test did not create garbage
 * and is inconclusive.
 */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

int clang_deref(int *p);
int clang_deref9(int *, int *, int *, int *, int *, int *, int *, int *, int *);
int clang_use_returned(unsigned long long v);
int clang_sort_sum(int *a, int n);
int old_deref(int *p);
int old_deref9(int *, int *, int *, int *, int *, int *, int *, int *, int *);
int old_use_returned(unsigned long long v);

static int value = 1234;
static volatile unsigned long long garbage = 0xdead5a5aULL << 32;

/* GCC returns the converted 64-bit value unchanged in x0. */
__attribute__((noinline)) int *gcc_give(unsigned long long v)
{
	return (int *)(uintptr_t)v;
}

static unsigned long long dirty_pointer(int *p)
{
	return garbage | (uint32_t)(uintptr_t)p;
}

/* Leave non-zero bytes where the next call's outgoing stack arguments go. */
__attribute__((noinline)) static void dirty_stack(void)
{
	volatile unsigned char buf[1024];

	for (unsigned i = 0; i < sizeof(buf); i++)
		buf[i] = 0xa5;
}

/*
 * v arrives in x0, where the callee expects its pointer, so GCC passes it on
 * unchanged, upper half included. (With v in another register, GCC's 32-bit
 * "mov w0, wN" would clear the upper half by accident.)
 */
__attribute__((noinline)) static int pass_reg(unsigned long long v, int (*f)(int *))
{
	return f((int *)(uintptr_t)v);
}

__attribute__((noinline)) static int pass_stack(int (*f)(int *, int *, int *, int *, int *, int *,
						      int *, int *, int *))
{
	int *p = &value;

	return f(p, p, p, p, p, p, p, p, p);
}

static int failures;

static void check(const char *what, int got)
{
	int ok = got == value;

	printf("%s %s: got %d, expected %d\n", ok ? "ok  " : "FAIL", what, got, value);
	failures += !ok;
}

/* The pre-fix code must crash, i.e. the garbage was really there. */
static void expect_crash(const char *what, int which)
{
	pid_t pid = fork();
	int st;

	if (pid == 0) {
		int r;

		if (which == 0) {
			r = pass_reg(dirty_pointer(&value), old_deref);
		} else if (which == 1) {
			dirty_stack();
			r = pass_stack(old_deref9);
		} else {
			r = old_use_returned(dirty_pointer(&value));
		}
		_exit(r == value ? 0 : 1);
	}
	waitpid(pid, &st, 0);
	if (WIFSIGNALED(st) && WTERMSIG(st) == SIGSEGV) {
		printf("ok   control %s: pre-fix code got SIGSEGV\n", what);
	} else {
		printf("FAIL control %s: pre-fix code did not crash (status %#x), no garbage created\n",
		       what, st);
		failures++;
	}
}

int main(void)
{
	int a[64], sum = 0;

	printf("pointer in register (garbage %#llx)\n", garbage);
	expect_crash("register", 0);
	check("clang callee, pointer in register",
	      pass_reg(dirty_pointer(&value), clang_deref));

	expect_crash("stack", 1);
	dirty_stack();
	check("clang callee, 9th pointer on the stack", pass_stack(clang_deref9));

	expect_crash("return", 2);
	check("clang caller, pointer returned by GCC",
	      clang_use_returned(dirty_pointer(&value)));

	for (int i = 0; i < 64; i++) {
		a[i] = (i * 37) % 64;
		sum += a[i];
	}
	int got = clang_sort_sum(a, 64);
	printf("%s qsort with a clang comparator: %d (expected %d)\n",
	       got == sum ? "ok  " : "FAIL", got, sum);
	failures += got != sum;

	printf("%s: %d failure(s)\n", failures ? "FAIL" : "PASS", failures);
	return failures != 0;
}
