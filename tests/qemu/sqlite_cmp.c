/*
 * Run the GCC-built and the clang-built sqlite3 shell on the same SQL script
 * and compare their output byte for byte.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define SCRIPT "/data/workload.sql"

/* Run prog on SCRIPT; return its stdout (malloc'ed) and set *len; NULL on failure. */
static char *run(const char *prog, size_t *len)
{
	int fd[2];
	pid_t pid;
	char *buf = NULL;
	size_t cap = 0, n = 0;
	ssize_t r;
	int st;

	if (pipe(fd))
		return NULL;
	pid = fork();
	if (pid == 0) {
		dup2(fd[1], 1);
		close(fd[0]);
		close(fd[1]);
		execl(prog, prog, ":memory:", ".read " SCRIPT, (char *)NULL);
		perror(prog);
		_exit(127);
	}
	close(fd[1]);
	for (;;) {
		if (n == cap) {
			cap = cap ? cap * 2 : 65536;
			buf = realloc(buf, cap);
		}
		r = read(fd[0], buf + n, cap - n);
		if (r <= 0)
			break;
		n += r;
	}
	close(fd[0]);
	waitpid(pid, &st, 0);
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) {
		printf("FAIL %s: exit status %#x\n", prog, st);
		free(buf);
		return NULL;
	}
	*len = n;
	return buf;
}

int main(void)
{
	size_t lg = 0, lc = 0;
	char *g = run("/bin/sqlite3-gcc", &lg);
	char *c = run("/bin/sqlite3-clang", &lc);

	if (!g || !c)
		return 1;
	if (lg != lc || memcmp(g, c, lg)) {
		size_t i = 0;

		while (i < lg && i < lc && g[i] == c[i])
			i++;
		printf("FAIL outputs differ at byte %zu (gcc %zu bytes, clang %zu bytes)\n", i, lg, lc);
		printf("gcc:   %.120s\nclang: %.120s\n", g + (i > 40 ? i - 40 : 0),
		       c + (i > 40 ? i - 40 : 0));
		return 1;
	}
	/* Show a little of the output so that the log proves the script ran. */
	printf("ok   identical output, %zu bytes; last lines:\n%s\n", lg,
	       lg > 160 ? g + lg - 160 : g);
	return 0;
}
