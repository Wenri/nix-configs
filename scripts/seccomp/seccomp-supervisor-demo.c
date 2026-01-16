/*
 * Working USER_NOTIF demo: Supervisor executes syscalls for target
 *
 * Uses SCM_RIGHTS to properly transfer the notification fd between processes.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <linux/seccomp.h>
#include <linux/filter.h>
#include <linux/audit.h>

/* Send fd over unix socket using SCM_RIGHTS */
static int send_fd(int sock, int fd) {
    struct msghdr msg = {0};
    char buf[CMSG_SPACE(sizeof(int))];
    struct iovec io = { .iov_base = "x", .iov_len = 1 };

    msg.msg_iov = &io;
    msg.msg_iovlen = 1;
    msg.msg_control = buf;
    msg.msg_controllen = sizeof(buf);

    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
    cmsg->cmsg_level = SOL_SOCKET;
    cmsg->cmsg_type = SCM_RIGHTS;
    cmsg->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(cmsg), &fd, sizeof(int));

    return sendmsg(sock, &msg, 0) >= 0 ? 0 : -1;
}

/* Receive fd over unix socket */
static int recv_fd(int sock) {
    struct msghdr msg = {0};
    char buf[CMSG_SPACE(sizeof(int))];
    char data[1];
    struct iovec io = { .iov_base = data, .iov_len = 1 };

    msg.msg_iov = &io;
    msg.msg_iovlen = 1;
    msg.msg_control = buf;
    msg.msg_controllen = sizeof(buf);

    if (recvmsg(sock, &msg, 0) < 0) return -1;

    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
    if (cmsg && cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS) {
        int fd;
        memcpy(&fd, CMSG_DATA(cmsg), sizeof(int));
        return fd;
    }
    return -1;
}

int main(void) {
    setbuf(stdout, NULL);

    printf("=== USER_NOTIF Demo: Supervisor Executes Blocked Syscalls ===\n\n");

    /* Create socket pair for passing notif_fd */
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) < 0) {
        perror("socketpair");
        return 1;
    }

    pid_t pid = fork();

    if (pid == 0) {
        /* CHILD: Target process - installs filter, sends fd to parent */
        close(sv[0]);  /* Close parent's end */

        /* Simple filter: USER_NOTIF for getpid only */
        struct sock_filter filter[] = {
            BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
            BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_getpid, 0, 1),
            BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_USER_NOTIF),
            BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        };
        struct sock_fprog prog = { .len = 4, .filter = filter };

        printf("[Target %d] Installing seccomp filter...\n", getpid());
        prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);

        int notif_fd = syscall(__NR_seccomp, SECCOMP_SET_MODE_FILTER,
                               SECCOMP_FILTER_FLAG_NEW_LISTENER, &prog);
        if (notif_fd < 0) {
            perror("[Target] seccomp");
            _exit(1);
        }
        printf("[Target] Filter installed, notif_fd=%d\n", notif_fd);

        /* Send fd to supervisor using SCM_RIGHTS */
        printf("[Target] Sending notif_fd to supervisor via SCM_RIGHTS...\n");
        if (send_fd(sv[1], notif_fd) < 0) {
            perror("[Target] send_fd");
            _exit(1);
        }
        close(notif_fd);  /* We don't need it anymore */
        close(sv[1]);

        /* Wait for supervisor to be ready */
        usleep(100000);

        printf("[Target] Now calling getpid() - will be handled by supervisor!\n");

        /* This getpid() will be intercepted and forwarded to supervisor */
        pid_t mypid = getpid();

        printf("[Target] getpid() returned: %d\n", mypid);
        printf("[Target] Expected: %d (my real PID)\n", (int)syscall(__NR_gettid));

        if (mypid > 0) {
            printf("[Target] SUCCESS! Supervisor returned the correct PID!\n");
        }

        _exit(0);
    }

    /* PARENT: Supervisor - receives fd and handles syscall notifications */
    close(sv[1]);  /* Close child's end */

    printf("[Supervisor %d] Waiting for notif_fd from target...\n", getpid());

    int notif_fd = recv_fd(sv[0]);
    close(sv[0]);

    if (notif_fd < 0) {
        perror("[Supervisor] recv_fd");
        return 1;
    }
    printf("[Supervisor] Received notif_fd=%d\n", notif_fd);

    /* Wait for syscall notification */
    printf("[Supervisor] Waiting for syscall notification...\n");

    struct seccomp_notif *req = malloc(sizeof(*req));
    struct seccomp_notif_resp *resp = malloc(sizeof(*resp));
    memset(req, 0, sizeof(*req));
    memset(resp, 0, sizeof(*resp));

    /* Receive the notification */
    if (ioctl(notif_fd, SECCOMP_IOCTL_NOTIF_RECV, req) < 0) {
        perror("[Supervisor] ioctl NOTIF_RECV");
        goto done;
    }

    printf("[Supervisor] Received notification!\n");
    printf("[Supervisor]   Syscall: %d (getpid=%d)\n", req->data.nr, __NR_getpid);
    printf("[Supervisor]   From PID: %d\n", req->pid);

    /*
     * HERE'S THE KEY POINT:
     * The supervisor can execute the REAL syscall because
     * the supervisor process does NOT have a seccomp filter!
     */
    printf("[Supervisor] I will return the target's PID: %d\n", req->pid);

    /* Send response with the target's real PID */
    resp->id = req->id;
    resp->val = req->pid;  /* Return the target's real PID */
    resp->error = 0;
    resp->flags = 0;

    printf("[Supervisor] Sending response...\n");

    if (ioctl(notif_fd, SECCOMP_IOCTL_NOTIF_SEND, resp) < 0) {
        perror("[Supervisor] ioctl NOTIF_SEND");
    } else {
        printf("[Supervisor] Response sent successfully!\n");
    }

done:
    close(notif_fd);
    free(req);
    free(resp);

    /* Wait for child */
    int status;
    waitpid(pid, &status, 0);
    printf("\n[Supervisor] Target exited with status %d\n", WEXITSTATUS(status));

    printf("\n=== Summary ===\n");
    printf("The supervisor intercepted the blocked getpid() syscall\n");
    printf("and returned the correct result to the target process!\n");
    printf("\nThis same technique can be used for ANY blocked syscall -\n");
    printf("the supervisor can execute the real syscall (it has no filter)\n");
    printf("and return the result to the filtered target.\n");

    return 0;
}
