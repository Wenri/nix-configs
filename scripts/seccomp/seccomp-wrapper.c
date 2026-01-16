/*
 * seccomp-wrapper: Run static binaries with SECCOMP_RET_ERRNO filter
 *
 * This wrapper installs a seccomp filter that returns ENOSYS for
 * syscalls that are blocked by Android's seccomp policy, then execs
 * the target binary.
 *
 * Usage: seccomp-wrapper <binary> [args...]
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/seccomp.h>
#include <linux/filter.h>
#include <linux/audit.h>

#ifndef SECCOMP_RET_ERRNO
#define SECCOMP_RET_ERRNO 0x00050000U
#endif

#ifndef AUDIT_ARCH_AARCH64
#define AUDIT_ARCH_AARCH64 (EM_AARCH64 | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#endif

// Syscall numbers for aarch64 that Android blocks
#define SYS_clone3         435
#define SYS_set_robust_list 99
#define SYS_rseq           293
#define SYS_faccessat2     439

static int do_seccomp(unsigned int op, unsigned int flags, void *args) {
    return syscall(__NR_seccomp, op, flags, args);
}

/*
 * BPF filter that returns ENOSYS for blocked syscalls
 * This allows programs to fall back to alternative syscalls
 *
 * Filter structure (10 instructions):
 * 0: load arch
 * 1: check arch == aarch64, if not jump to 9 (kill)
 * 2: load syscall number
 * 3: check clone3, if match jump to 8 (errno)
 * 4: check set_robust_list, if match jump to 8 (errno)
 * 5: check rseq, if match jump to 8 (errno)
 * 6: check faccessat2, if match jump to 8 (errno)
 * 7: allow
 * 8: return ENOSYS
 * 9: kill process
 */
static struct sock_filter filter[] = {
    /* [0] Load architecture */
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),

    /* [1] Check architecture is aarch64: if match continue, else jump +7 to [9] */
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_AARCH64, 0, 7),

    /* [2] Load syscall number */
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),

    /* [3] Check clone3: if match jump +4 to [8] (errno) */
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_clone3, 4, 0),

    /* [4] Check set_robust_list: if match jump +3 to [8] (errno) */
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_set_robust_list, 3, 0),

    /* [5] Check rseq: if match jump +2 to [8] (errno) */
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_rseq, 2, 0),

    /* [6] Check faccessat2: if match jump +1 to [8] (errno) */
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_faccessat2, 1, 0),

    /* [7] Allow everything else */
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),

    /* [8] Return ENOSYS for blocked syscalls */
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | ENOSYS),

    /* [9] Kill if wrong architecture (shouldn't happen) */
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
};

static struct sock_fprog prog = {
    .len = sizeof(filter) / sizeof(filter[0]),
    .filter = filter,
};

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <binary> [args...]\n", argv[0]);
        fprintf(stderr, "\nInstalls seccomp filter returning ENOSYS for:\n");
        fprintf(stderr, "  - clone3 (%d)\n", SYS_clone3);
        fprintf(stderr, "  - set_robust_list (%d)\n", SYS_set_robust_list);
        fprintf(stderr, "  - rseq (%d)\n", SYS_rseq);
        fprintf(stderr, "  - faccessat2 (%d)\n", SYS_faccessat2);
        return 1;
    }

    /* Set no_new_privs to allow seccomp without CAP_SYS_ADMIN */
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        perror("prctl(PR_SET_NO_NEW_PRIVS)");
        return 1;
    }

    /* Install seccomp filter */
    if (do_seccomp(SECCOMP_SET_MODE_FILTER, 0, &prog) < 0) {
        perror("seccomp(SECCOMP_SET_MODE_FILTER)");
        return 1;
    }

    /* Execute the target binary */
    execvp(argv[1], &argv[1]);

    /* If we get here, exec failed */
    perror("execvp");
    return 1;
}
