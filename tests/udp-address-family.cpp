// Compile with -I pointing to the patched ZeroTierOne source directory.
// Only telemetry is stubbed; socket creation, sending, and receiving are real.
#include <cassert>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

#define METRICS_H_
namespace ZeroTier { namespace Metrics { unsigned long udp_send = 0; } }

static unsigned int sendCalls = 0;
static ssize_t trackedSendto(int fd, const void* data, size_t len, int flags,
                            const sockaddr* addr, socklen_t addrlen)
{
    ++sendCalls;
    return ::sendto(fd, data, len, flags, addr, addrlen);
}
#define sendto trackedSendto
#include "osdep/Phy.hpp"
#undef sendto

struct Handler {
    template<typename... T> void phyOnTcpConnect(T...) {}
    template<typename... T> void phyOnTcpClose(T...) {}
    template<typename... T> void phyOnUnixClose(T...) {}
};

static sockaddr_storage destination(int fd)
{
    sockaddr_storage addr = {};
    socklen_t len = sizeof(addr);
    assert(getsockname(fd, reinterpret_cast<sockaddr*>(&addr), &len) == 0);
    return addr;
}

int main()
{
    Handler handler;
    ZeroTier::Phy<Handler*> phy(&handler, false, false);
    sockaddr_in v4 = {};
    v4.sin_family = AF_INET;
    v4.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sockaddr_in6 v6 = {};
    v6.sin6_family = AF_INET6;
    v6.sin6_addr = in6addr_loopback;
    auto* s4 = phy.udpBind(reinterpret_cast<sockaddr*>(&v4));
    auto* s6 = phy.udpBind(reinterpret_cast<sockaddr*>(&v6));
    assert(s4 && s6);
    const int fd4 = phy.getDescriptor(s4), fd6 = phy.getDescriptor(s6);
    const auto a4 = destination(fd4), a6 = destination(fd6);
    const auto* p4 = reinterpret_cast<const sockaddr*>(&a4);
    const auto* p6 = reinterpret_cast<const sockaddr*>(&a6);
    const char payload[] = "udp-family-regression";
    sockaddr invalid = {};
    invalid.sa_family = AF_UNSPEC;
    for (int i = 0; i < 10000; ++i) {
        assert(!phy.udpSend(s4, p6, payload, sizeof(payload)));
        assert(!phy.udpSend(s6, p4, payload, sizeof(payload)));
        assert(!phy.udpSend(s4, &invalid, payload, sizeof(payload)));
    }
    assert(!phy.udpSend(nullptr, p4, payload, sizeof(payload)));
    assert(!phy.udpSend(s4, nullptr, payload, sizeof(payload)));
    assert(sendCalls == 0);
    assert(ZeroTier::Metrics::udp_send == 0);
    char received[sizeof(payload)] = {};
    assert(phy.udpSend(s4, p4, payload, sizeof(payload)));
    assert(recv(fd4, received, sizeof(received), 0) == sizeof(payload));
    assert(std::memcmp(payload, received, sizeof(payload)) == 0);
    assert(phy.udpSend(s6, p6, payload, sizeof(payload)));
    assert(recv(fd6, received, sizeof(received), 0) == sizeof(payload));
    assert(std::memcmp(payload, received, sizeof(payload)) == 0);
    assert(sendCalls == 2);
    assert(ZeroTier::Metrics::udp_send == 2 * sizeof(payload));
    phy.close(s4, false);
    assert(!phy.udpSend(s4, p4, payload, sizeof(payload)));
    assert(sendCalls == 2);
    std::puts("PASS: 30000 rejected destinations, no sendto; IPv4/IPv6 delivery, metrics, null and closed sockets");
}
