#include "ttl_phantom_injector.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#pragma comment(lib, "Ws2_32.lib")

namespace {

void LogDebug(const std::string& msg) {
  OutputDebugStringA((msg + "\n").c_str());
}

std::string FormatLastError(const std::string& prefix) {
  const auto err = GetLastError();
  std::ostringstream oss;
  oss << prefix << " (err=" << err << ")";
  return oss.str();
}

// Minimal WinDivert declarations to avoid external headers.
typedef enum {
  WINDIVERT_LAYER_NETWORK = 0,
} WINDIVERT_LAYER;

typedef enum {
  WINDIVERT_SHUTDOWN_RECV = 0x1,
  WINDIVERT_SHUTDOWN_SEND = 0x2,
  WINDIVERT_SHUTDOWN_BOTH = 0x3,
} WINDIVERT_SHUTDOWN;

typedef struct {
  UINT32 IfIdx;
  UINT32 SubIfIdx;
} WINDIVERT_DATA_NETWORK;

typedef struct {
  INT64 Timestamp;
  UINT32 Layer : 8;
  UINT32 Event : 8;
  UINT32 Sniffed : 1;
  UINT32 Outbound : 1;
  UINT32 Loopback : 1;
  UINT32 Impostor : 1;
  UINT32 IPv6 : 1;
  UINT32 IPChecksum : 1;
  UINT32 TCPChecksum : 1;
  UINT32 UDPChecksum : 1;
  UINT32 Reserved1 : 8;
  UINT32 Reserved2;
  union {
    WINDIVERT_DATA_NETWORK Network;
    UINT8 Reserved3[64];
  };
} WINDIVERT_ADDRESS;

typedef HANDLE(WINAPI* WinDivertOpen_t)(
    const char* filter, WINDIVERT_LAYER layer, INT16 priority, UINT64 flags);
typedef BOOL(WINAPI* WinDivertRecv_t)(
    HANDLE handle,
    VOID* pPacket,
    UINT packetLen,
    UINT* pRecvLen,
    WINDIVERT_ADDRESS* pAddr);
typedef BOOL(WINAPI* WinDivertSend_t)(
    HANDLE handle,
    const VOID* pPacket,
    UINT packetLen,
    UINT* pSendLen,
    const WINDIVERT_ADDRESS* pAddr);
typedef BOOL(WINAPI* WinDivertShutdown_t)(HANDLE handle, WINDIVERT_SHUTDOWN how);
typedef BOOL(WINAPI* WinDivertClose_t)(HANDLE handle);

constexpr UINT64 kWinDivertFlagFragments = 0x0020;
constexpr size_t kMaxPacketSize = 0xFFFF;
constexpr UINT8 kDecoyTtl = 5;

struct WinDivertApi {
  WinDivertOpen_t open = nullptr;
  WinDivertRecv_t recv = nullptr;
  WinDivertSend_t send = nullptr;
  WinDivertShutdown_t shutdown = nullptr;
  WinDivertClose_t close = nullptr;
};

WinDivertApi g_api;
HMODULE g_windivert_module = nullptr;
HANDLE g_handle = INVALID_HANDLE_VALUE;
std::atomic_bool g_stop{false};
std::mutex g_state_mutex;
std::thread g_worker;

struct SessionKey {
  UINT32 src;
  UINT32 dst;
  UINT16 srcPort;
  UINT16 dstPort;

  bool operator==(const SessionKey& other) const {
    return src == other.src && dst == other.dst && srcPort == other.srcPort &&
           dstPort == other.dstPort;
  }
};

struct SessionKeyHasher {
  size_t operator()(const SessionKey& key) const noexcept {
    size_t h1 = std::hash<UINT32>{}(key.src);
    size_t h2 = std::hash<UINT32>{}(key.dst);
    size_t h3 = std::hash<UINT16>{}(key.srcPort);
    size_t h4 = std::hash<UINT16>{}(key.dstPort);
    return (((h1 ^ (h2 << 1)) ^ (h3 << 1)) ^ (h4 << 1));
  }
};

std::unordered_set<SessionKey, SessionKeyHasher> g_sessions;

#pragma pack(push, 1)
struct Ipv4Header {
  UINT8 versionIhl;
  UINT8 tos;
  UINT16 totalLength;
  UINT16 id;
  UINT16 fragOff;
  UINT8 ttl;
  UINT8 protocol;
  UINT16 checksum;
  UINT32 srcAddr;
  UINT32 dstAddr;
};

struct TcpHeader {
  UINT16 srcPort;
  UINT16 dstPort;
  UINT32 seqNum;
  UINT32 ackNum;
  UINT16 dataOffsetAndFlags;
  UINT16 window;
  UINT16 checksum;
  UINT16 urgPtr;
};
#pragma pack(pop)

bool load_windivert() {
  if (g_api.open != nullptr) {
    return true;
  }
  if (g_windivert_module == nullptr) {
    g_windivert_module = LoadLibraryW(L"WinDivert.dll");
  }
  if (!g_windivert_module) {
    LogDebug(FormatLastError("WinDivert.dll not loaded"));
    return false;
  }

  g_api.open =
      reinterpret_cast<WinDivertOpen_t>(GetProcAddress(g_windivert_module, "WinDivertOpen"));
  g_api.recv =
      reinterpret_cast<WinDivertRecv_t>(GetProcAddress(g_windivert_module, "WinDivertRecv"));
  g_api.send =
      reinterpret_cast<WinDivertSend_t>(GetProcAddress(g_windivert_module, "WinDivertSend"));
  g_api.shutdown = reinterpret_cast<WinDivertShutdown_t>(
      GetProcAddress(g_windivert_module, "WinDivertShutdown"));
  g_api.close =
      reinterpret_cast<WinDivertClose_t>(GetProcAddress(g_windivert_module, "WinDivertClose"));

  const bool ok = g_api.open && g_api.recv && g_api.send && g_api.shutdown && g_api.close;
  if (!ok) {
    LogDebug("WinDivert symbols missing");
  } else {
    LogDebug("WinDivert loaded successfully");
  }
  return ok;
}

uint16_t fold_checksum(uint32_t sum) {
  while (sum >> 16) {
    sum = (sum & 0xFFFF) + (sum >> 16);
  }
  return static_cast<uint16_t>(~sum);
}

uint16_t compute_ipv4_checksum(const Ipv4Header* ip, size_t headerLen) {
  uint32_t sum = 0;
  const uint8_t* data = reinterpret_cast<const uint8_t*>(ip);
  for (size_t i = 0; i + 1 < headerLen; i += 2) {
    sum += (data[i] << 8) | data[i + 1];
  }
  if (headerLen & 1) {
    sum += data[headerLen - 1] << 8;
  }
  return fold_checksum(sum);
}

uint16_t compute_tcp_checksum(const Ipv4Header* ip,
                              const TcpHeader* tcp,
                              const uint8_t* payload,
                              size_t payloadLen,
                              size_t tcpHeaderLen) {
  uint32_t sum = 0;
  sum += (ip->srcAddr >> 16) & 0xFFFF;
  sum += ip->srcAddr & 0xFFFF;
  sum += (ip->dstAddr >> 16) & 0xFFFF;
  sum += ip->dstAddr & 0xFFFF;
  sum += htons(IPPROTO_TCP);
  sum += htons(static_cast<uint16_t>(tcpHeaderLen + payloadLen));

  const uint8_t* tcpBytes = reinterpret_cast<const uint8_t*>(tcp);
  size_t totalLen = tcpHeaderLen + payloadLen;
  for (size_t i = 0; i + 1 < totalLen; i += 2) {
    sum += (tcpBytes[i] << 8) | tcpBytes[i + 1];
  }
  if (totalLen & 1) {
    sum += tcpBytes[totalLen - 1] << 8;
  }
  return fold_checksum(sum);
}

bool parse_tcp_packet(const uint8_t* packet,
                      size_t length,
                      const Ipv4Header*& ip,
                      const TcpHeader*& tcp,
                      size_t& ipHeaderLen,
                      size_t& tcpHeaderLen) {
  if (length < sizeof(Ipv4Header)) return false;
  ip = reinterpret_cast<const Ipv4Header*>(packet);
  if ((ip->versionIhl >> 4) != 4) return false;

  ipHeaderLen = (ip->versionIhl & 0x0F) * 4;
  if (ipHeaderLen < sizeof(Ipv4Header) || length < ipHeaderLen + sizeof(TcpHeader)) {
    return false;
  }

  tcp = reinterpret_cast<const TcpHeader*>(packet + ipHeaderLen);
  tcpHeaderLen = ((ntohs(tcp->dataOffsetAndFlags) >> 12) & 0x0F) * 4;
  if (tcpHeaderLen < sizeof(TcpHeader)) {
    return false;
  }

  if (length < ipHeaderLen + tcpHeaderLen) return false;
  return true;
}

std::vector<uint8_t> build_decoy(const Ipv4Header* ip,
                                 const TcpHeader* tcp,
                                 size_t ipHeaderLen,
                                 size_t tcpHeaderLen,
                                 std::mt19937& rng) {
  std::uniform_int_distribution<int> payloadSizeDist(16, 32);
  const size_t junkSize = static_cast<size_t>(payloadSizeDist(rng));
  const size_t totalSize = ipHeaderLen + tcpHeaderLen + junkSize;

  std::vector<uint8_t> buffer(totalSize);
  std::memcpy(buffer.data(), ip, ipHeaderLen);
  std::memcpy(buffer.data() + ipHeaderLen, tcp, tcpHeaderLen);

  auto* outIp = reinterpret_cast<Ipv4Header*>(buffer.data());
  auto* outTcp = reinterpret_cast<TcpHeader*>(buffer.data() + ipHeaderLen);

  outIp->totalLength = htons(static_cast<uint16_t>(totalSize));
  outIp->ttl = kDecoyTtl;
  outIp->checksum = 0;

  uint16_t flags = ntohs(outTcp->dataOffsetAndFlags);
  flags &= 0xF000;           // keep data offset
  flags |= 0x0002;           // SYN flag
  outTcp->dataOffsetAndFlags = htons(flags);
  outTcp->ackNum = 0;
  outTcp->seqNum = std::uniform_int_distribution<uint32_t>()(rng);
  outTcp->checksum = 0;

  auto* payload = buffer.data() + ipHeaderLen + tcpHeaderLen;
  for (size_t i = 0; i < junkSize; ++i) {
    payload[i] = static_cast<uint8_t>(std::uniform_int_distribution<int>(0, 255)(rng));
  }

  outIp->checksum = compute_ipv4_checksum(outIp, ipHeaderLen);
  outTcp->checksum =
      compute_tcp_checksum(outIp, outTcp, payload, junkSize, tcpHeaderLen);
  return buffer;
}

void remove_session_if_done(const TcpHeader* tcp, const SessionKey& key) {
  const uint16_t flags = ntohs(tcp->dataOffsetAndFlags);
  const bool fin = (flags & 0x0001) != 0;
  const bool rst = (flags & 0x0004) != 0;
  if (fin || rst) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_sessions.erase(key);
  }
}

void worker_loop(const std::string targetIp, UINT16 targetPort) {
  std::ostringstream filter;
  filter << "outbound and ip and tcp and tcp.DstPort == " << targetPort
         << " and ip.DstAddr == " << targetIp;

  HANDLE handle =
      g_api.open(filter.str().c_str(), WINDIVERT_LAYER_NETWORK, 0, kWinDivertFlagFragments);
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_handle = handle;
  }
  if (handle == INVALID_HANDLE_VALUE) {
    LogDebug(FormatLastError("WinDivertOpen failed"));
    g_stop.store(true);
    return;
  }

  std::vector<uint8_t> packet(kMaxPacketSize);
  std::mt19937 rng{std::random_device{}()};

  while (!g_stop.load()) {
    WINDIVERT_ADDRESS addr{};
    UINT recvLen = 0;
    if (!g_api.recv(handle, packet.data(), static_cast<UINT>(packet.size()), &recvLen, &addr)) {
      if (g_stop.load()) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }
    if (recvLen == 0) continue;

    const Ipv4Header* ip = nullptr;
    const TcpHeader* tcp = nullptr;
    size_t ipHeaderLen = 0;
    size_t tcpHeaderLen = 0;
    if (!parse_tcp_packet(packet.data(), recvLen, ip, tcp, ipHeaderLen, tcpHeaderLen)) {
      continue;
    }

    SessionKey key{ip->srcAddr, ip->dstAddr, tcp->srcPort, tcp->dstPort};
    bool isNewSession = false;
    {
      std::lock_guard<std::mutex> lock(g_state_mutex);
      auto [_, inserted] = g_sessions.insert(key);
      isNewSession = inserted;
    }

    if (isNewSession) {
      auto decoy = build_decoy(ip, tcp, ipHeaderLen, tcpHeaderLen, rng);
      g_api.send(handle, decoy.data(), static_cast<UINT>(decoy.size()), nullptr, &addr);
    }

    g_api.send(handle, packet.data(), recvLen, nullptr, &addr);
    remove_session_if_done(tcp, key);
  }

  g_api.close(handle);
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_handle = INVALID_HANDLE_VALUE;
    g_sessions.clear();
  }
}

}  // namespace

bool start_ttl_phantom_injector(const char* server_ip, UINT16 server_port) {
  if (server_ip == nullptr || server_ip[0] == '\0' || server_port == 0) {
    return false;
  }

  stop_ttl_phantom_injector();
  if (!load_windivert()) {
    LogDebug("load_windivert failed");
    return false;
  }

  g_stop.store(false);
  const std::string ip(server_ip);
  LogDebug("Starting WinDivert worker for " + ip + ":" + std::to_string(server_port));
  g_worker = std::thread(worker_loop, ip, server_port);
  return true;
}

void stop_ttl_phantom_injector() {
  g_stop.store(true);
  HANDLE handle = INVALID_HANDLE_VALUE;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    handle = g_handle;
  }
  if (handle != INVALID_HANDLE_VALUE && g_api.shutdown) {
    g_api.shutdown(handle, WINDIVERT_SHUTDOWN_BOTH);
  }
  if (g_worker.joinable()) {
    g_worker.join();
  }
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_handle != INVALID_HANDLE_VALUE && g_api.close) {
      g_api.close(g_handle);
    }
    g_handle = INVALID_HANDLE_VALUE;
    g_sessions.clear();
  }
}
