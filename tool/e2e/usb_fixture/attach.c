// Test-only USB/IP import for a rooted, disposable Android AVD. The product app
// remains unprivileged and obtains its own UsbManager permission and descriptor.
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdint.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static volatile sig_atomic_t restore_enforcing;
static void enforce(void) {
    if (!restore_enforcing) return;
    int fd = open("/sys/fs/selinux/enforce", O_WRONLY | O_CLOEXEC);
    if (fd < 0 || write(fd, "1", 1) != 1) {
        const char message[] = "Unable to restore SELinux enforcing\n";
        write(STDERR_FILENO, message, sizeof(message) - 1);
        _exit(1);
    }
    close(fd);
    restore_enforcing = 0;
}

static void interrupted(int signum) {
    enforce();
    _exit(128 + signum);
}

_Noreturn static void fail(const char *operation) {
    perror(operation);
    exit(1);
}

static void transfer(int fd, void *buffer, size_t length, int sending) {
    unsigned char *bytes = buffer;
    while (length) {
        ssize_t count = sending ? write(fd, bytes, length) : read(fd, bytes, length);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { if (count == 0) errno = ECONNRESET; fail("USB/IP exchange"); }
        bytes += count;
        length -= (size_t)count;
    }
}

static uint32_t be32(const unsigned char *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | p[3];
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "Usage: attach HOST TCP_PORT BUS_ID VHCI_PORT\n");
        return 2;
    }
    if (strlen(argv[3]) >= 32) return 2;
    char *end;
    long port = strtol(argv[4], &end, 10);
    if (*end || port < 0 || port > 7) return 2;
    struct addrinfo hints = { .ai_family = AF_INET, .ai_socktype = SOCK_STREAM };
    struct addrinfo *addresses = NULL;
    int error = getaddrinfo(argv[1], argv[2], &hints, &addresses);
    if (error) { fprintf(stderr, "getaddrinfo: %s\n", gai_strerror(error)); return 1; }
    // Stock AVD policy cannot create/connect a kernel-labelled socket in
    // enforcing mode. Relax policy only for the setup handshake, before any
    // USB device exists, and restore it before handing the socket to vhci.
    int policy = open("/sys/fs/selinux/enforce", O_RDWR | O_CLOEXEC);
    char state;
    if (policy < 0 || read(policy, &state, 1) != 1) fail("read SELinux mode");
    if (state != '1') {
        fprintf(stderr, "Fixture requires an initially enforcing AVD\n"); return 1;
    }
    restore_enforcing = 1;
    atexit(enforce);
    struct sigaction action = { .sa_handler = interrupted };
    sigfillset(&action.sa_mask);
    if (sigaction(SIGINT, &action, NULL) || sigaction(SIGTERM, &action, NULL) ||
        sigaction(SIGHUP, &action, NULL)) fail("signal handlers");
    action.sa_handler = SIG_IGN;
    if (sigaction(SIGPIPE, &action, NULL)) fail("SIGPIPE handler");
    if (lseek(policy, 0, SEEK_SET) < 0 || write(policy, "0", 1) != 1) fail("setup SELinux mode");
    close(policy);
    // The kernel vhci worker, rather than this root setup process, owns I/O.
    // Label only its socket so the rest of the AVD stays SELinux enforcing.
    int context = open("/proc/thread-self/attr/sockcreate", O_WRONLY | O_CLOEXEC);
    if (context < 0) fail("open socket context");
    const char label[] = "u:r:kernel:s0";
    if (write(context, label, sizeof(label) - 1) != sizeof(label) - 1) fail("socket context");
    close(context);
    int fd = -1;
    for (struct addrinfo *a = addresses; a; a = a->ai_next) {
        fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd >= 0 && connect(fd, a->ai_addr, a->ai_addrlen) == 0) break;
        if (fd >= 0) close(fd);
        fd = -1;
    }
    freeaddrinfo(addresses);
    if (fd < 0) fail("connect");
    struct timeval timeout = { .tv_sec = 10 };
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout))) fail("timeout");
    unsigned char request[40] = { 0x01, 0x11, 0x80, 0x03 };
    memcpy(request + 8, argv[3], strlen(argv[3]));
    transfer(fd, request, sizeof(request), 1);
    unsigned char response[320];
    transfer(fd, response, 8, 0);
    if (memcmp(response, "\x01\x11\x00\x03\x00\x00\x00\x00", 8)) {
        fprintf(stderr, "USB/IP import rejected\n"); close(fd); return 1;
    }
    transfer(fd, response + 8, sizeof(response) - 8, 0);
    uint32_t bus = be32(response + 296), device = be32(response + 300);
    uint32_t speed = be32(response + 304);
    if (bus > 65535 || device > 65535 || speed != 3) {
        fprintf(stderr, "Expected USB2 high-speed fixture\n"); close(fd); return 1;
    }
    timeout.tv_sec = 0;
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout))) fail("timeout");
    enforce();
    int attach = open("/sys/devices/platform/vhci_hcd.0/attach", O_WRONLY | O_CLOEXEC);
    if (attach < 0) fail("open vhci attach");
    char command[96];
    int size = snprintf(command, sizeof(command), "%ld %d %u %u", port, fd,
                        (bus << 16) | device, speed);
    if (write(attach, command, (size_t)size) != size) fail("vhci attach");
    close(attach);
    close(fd); // vhci retains its own reference to the imported socket.
    printf("Imported USB/IP fixture on vhci port %ld\n", port);
    return 0;
}
