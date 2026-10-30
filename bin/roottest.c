#define _GNU_SOURCE
// 验证 cap_capable 补丁：普通 uid(2000) 进程调用 setuid(0) 应当成功
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <stdlib.h>

int main(void) {
    setbuf(stdout, NULL);
    printf("before: uid=%d euid=%d gid=%d\n", (int)getuid(), (int)geteuid(), (int)getgid());

    int r = setuid(0);
    printf("setuid(0) -> %d (%s)\n", r, r == 0 ? "OK" : strerror(errno));
    if (r != 0) {
        r = seteuid(0);
        printf("seteuid(0) -> %d (%s)\n", r, r == 0 ? "OK" : strerror(errno));
    }
    printf("after : uid=%d euid=%d\n", (int)getuid(), (int)geteuid());

    if (geteuid() == 0) {
        printf("ROOT OK\n");
        /* 顺手把 /data 下的东西证明一下 */
        system("id; echo root-ok > /data/local/tmp/root_ok; ls -l /data/local/tmp/root_ok");
    } else {
        printf("NOT ROOT\n");
    }
    return 0;
}
