#define _GNU_SOURCE
// su：提权到 root 后执行命令或交互 shell
// 用法： su             -> 进入 root shell
//        su -c "命令"   -> 以 root 执行命令
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (setgid(0) != 0 || setuid(0) != 0) {
        fprintf(stderr, "提权失败: %s\n", strerror(errno));
        return 1;
    }
    if (geteuid() != 0) {
        fprintf(stderr, "提权后仍非 root\n");
        return 1;
    }
    if (argc >= 3 && strcmp(argv[1], "-c") == 0) {
        char *args[] = { "/system/bin/sh", "-c", argv[2], NULL };
        execv("/system/bin/sh", args);
    } else if (argc >= 2) {
        execvp(argv[1], &argv[1]);
    } else {
        char *args[] = { "/system/bin/sh", "-i", NULL };
        execv("/system/bin/sh", args);
    }
    fprintf(stderr, "exec 失败: %s\n", strerror(errno));
    return 1;
}
