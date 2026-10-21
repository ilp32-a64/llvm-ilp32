/* clang-compiled side of the GCC <-> clang AArch64 ILP32 pointer passing test. */
#include <stdlib.h>

int *gcc_give(unsigned long long v);

int clang_deref(int *p)
{
	return *p;
}

int clang_deref9(int *p1, int *p2, int *p3, int *p4, int *p5, int *p6, int *p7, int *p8,
		 int *p9)
{
	return *p9;
}

int clang_use_returned(unsigned long long v)
{
	return *gcc_give(v);
}

static int cmp(const void *a, const void *b)
{
	int x = *(const int *)a, y = *(const int *)b;

	return (x > y) - (x < y);
}

/* Sort with a comparator called by GCC-built glibc; -1 if not sorted. */
int clang_sort_sum(int *a, int n)
{
	int sum = 0;

	qsort(a, n, sizeof(*a), cmp);
	for (int i = 0; i < n; i++) {
		if (i && a[i - 1] > a[i])
			return -1;
		sum += a[i];
	}
	return sum;
}
