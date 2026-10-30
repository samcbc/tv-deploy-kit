#define _GNU_SOURCE
// 端到端验证：走系统网络（此时已被 Clash tun 接管）做真实 HTTP 请求
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <arpa/inet.h>

static int fetch(const char *host, int port, const char *path) {
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char portstr[8];
    snprintf(portstr, sizeof(portstr), "%d", port);
    int g = getaddrinfo(host, portstr, &hints, &res);
    if (g != 0) { printf("  [%s] DNS 失败: %s\n", host, gai_strerror(g)); return -1; }
    char ip[64] = "?";
    struct sockaddr_in *sa = (struct sockaddr_in *)res->ai_addr;
    inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof(ip));
    printf("  [%s] -> %s\n", host, ip);

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct timeval tv = { 15, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    if (connect(fd, res->ai_addr, res->ai_addrlen) != 0) {
        printf("  [%s] connect 失败: %s\n", host, strerror(errno));
        close(fd); freeaddrinfo(res); return -1;
    }
    char req[512];
    int n = snprintf(req, sizeof(req),
                     "GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: tv-probe\r\nConnection: close\r\n\r\n",
                     path, host);
    send(fd, req, n, 0);
    char buf[1024];
    int r = recv(fd, buf, sizeof(buf) - 1, 0);
    if (r <= 0) {
        printf("  [%s] 无响应: %s\n", host, r == 0 ? "连接被关闭" : strerror(errno));
        close(fd); freeaddrinfo(res); return -1;
    }
    buf[r] = 0;
    char *nl = strchr(buf, '\n');
    if (nl) *nl = 0;
    printf("  [%s] 响应: %s\n", host, buf);
    close(fd); freeaddrinfo(res);
    return 0;
}

int main(void) {
    setbuf(stdout, NULL);
    printf("=== 端到端连通性测试（应全部走 Clash 隧道）===\n");
    int ok = 0;
    ok += (fetch("www.gstatic.com", 80, "/generate_204") == 0);
    ok += (fetch("www.youtube.com", 80, "/") == 0);
    ok += (fetch("www.google.com", 80, "/generate_204") == 0);
    printf("成功 %d/3\n", ok);
    return ok == 3 ? 0 : 1;
}
