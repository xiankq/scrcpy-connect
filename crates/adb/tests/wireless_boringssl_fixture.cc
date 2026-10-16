// Test-only peer using the actual BoringSSL primitives used by AOSP adbd.
// It is deliberately outside Cargo dependencies; it is NOT an adbd emulator.
// Verified with google/boringssl commit 34ea2105ef7034bc0f5da539480732f797623acb.
// Build: c++ -std=c++17 -I<BORINGSSL>/include wireless_boringssl_fixture.cc
//        <BUILD>/libssl.a <BUILD>/libcrypto.a -pthread -o /tmp/adb-boringssl-peer
// Protocol reference: AOSP adb 9084198a2d4b0f6a0f174260fb42da33485b684d,
// pairing_connection/pairing_connection.cpp, pairing_auth/{pairing_auth,aes_128_gcm}.cpp.
#include <openssl/aead.h>
#include <openssl/curve25519.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/hkdf.h>
#include <openssl/rsa.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <array>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
using Bytes = std::vector<uint8_t>;
static void check(bool ok, const char* msg) {
    if (!ok) { ERR_print_errors_fp(stderr); throw std::runtime_error(msg); }
}
static void io(SSL* ssl, int fd, uint8_t* data, size_t size, bool write) {
    while (size) {
        int n = ssl ? (write ? SSL_write(ssl, data, size) : SSL_read(ssl, data, size))
                    : (write ? ::write(fd, data, size) : ::read(fd, data, size));
        check(n > 0, "peer I/O failed"); data += n; size -= n;
    }
}
static void send_pair(SSL* ssl, uint8_t kind, const Bytes& bytes) {
    std::array<uint8_t, 6> hdr{1, kind, 0, 0, 0, 0};
    auto length = htonl(bytes.size()); std::memcpy(hdr.data() + 2, &length, 4);
    io(ssl, -1, hdr.data(), hdr.size(), true);
    io(ssl, -1, const_cast<uint8_t*>(bytes.data()), bytes.size(), true);
}
static Bytes recv_pair(SSL* ssl, uint8_t kind, size_t expected) {
    std::array<uint8_t, 6> hdr{}; io(ssl, -1, hdr.data(), hdr.size(), false);
    uint32_t size; std::memcpy(&size, hdr.data() + 2, 4); size = ntohl(size);
    check(hdr[0] == 1 && hdr[1] == kind && size == expected, "invalid pairing header");
    Bytes bytes(size); io(ssl, -1, bytes.data(), bytes.size(), false); return bytes;
}
static void send_adb(SSL* ssl, int fd, const char* command, uint32_t arg0, uint32_t arg1, const Bytes& payload) {
    uint32_t cmd; std::memcpy(&cmd, command, 4);
    uint32_t sum = 0; for (auto b : payload) sum += b;
    std::array<uint32_t,6> header{cmd, arg0, arg1, uint32_t(payload.size()), sum, cmd ^ 0xffffffff};
    io(ssl, fd, reinterpret_cast<uint8_t*>(header.data()), 24, true);
    io(ssl, fd, const_cast<uint8_t*>(payload.data()), payload.size(), true);
}
static void recv_adb(int fd, const char* command) {
    std::array<uint32_t,6> header{}; io(nullptr, fd, reinterpret_cast<uint8_t*>(header.data()), 24, false);
    check(std::memcmp(header.data(), command, 4) == 0 && header[3] <= 4096, "invalid ADB negotiation frame");
    Bytes payload(header[3]); io(nullptr, fd, payload.data(), payload.size(), false);
}
static void pair(SSL* ssl, const std::string& code) {
    constexpr char label[] = "adb-label";
    std::array<uint8_t,64> exported{};
    check(SSL_export_keying_material(ssl, exported.data(), exported.size(), label, sizeof(label), nullptr, 0, 0), "exporter");
    Bytes password(code.begin(), code.end()); password.insert(password.end(), exported.begin(), exported.end());
    constexpr char client_name[] = "adb pair client";
    constexpr char server_name[] = "adb pair server";
    auto* spake = SPAKE2_CTX_new(spake2_role_bob,
        reinterpret_cast<const uint8_t*>(server_name), sizeof(server_name),
        reinterpret_cast<const uint8_t*>(client_name), sizeof(client_name));
    check(spake != nullptr, "SPAKE2_CTX_new");
    Bytes message(SPAKE2_MAX_MSG_SIZE); size_t len = 0;
    check(SPAKE2_generate_msg(spake, message.data(), &len, message.size(), password.data(), password.size()), "SPAKE2_generate_msg");
    message.resize(len); send_pair(ssl, 0, message);
    auto incoming = recv_pair(ssl, 0, 32);
    Bytes material(SPAKE2_MAX_KEY_SIZE);
    check(SPAKE2_process_msg(spake, material.data(), &len, material.size(), incoming.data(), incoming.size()), "SPAKE2_process_msg");
    material.resize(len); SPAKE2_CTX_free(spake);
    std::array<uint8_t,16> key{};
    constexpr char info[] = "adb pairing_auth aes-128-gcm key";
    check(HKDF(key.data(), key.size(), EVP_sha256(), material.data(), material.size(), nullptr, 0,
        reinterpret_cast<const uint8_t*>(info), sizeof(info)-1), "HKDF");
    auto* aead = EVP_AEAD_CTX_new(EVP_aead_aes_128_gcm(), key.data(), key.size(), EVP_AEAD_DEFAULT_TAG_LENGTH);
    check(aead != nullptr, "AEAD init");
    Bytes guid(8192, 0); guid[0] = 1;
    constexpr char device_guid[] = "adb-boringssl-official-crypto";
    std::memcpy(guid.data()+1, device_guid, sizeof(device_guid));
    std::array<uint8_t,12> nonce{};
    Bytes sealed(8192 + 16);
    check(EVP_AEAD_CTX_seal(aead, sealed.data(), &len, sealed.size(), nonce.data(), nonce.size(), guid.data(), guid.size(), nullptr, 0), "GCM seal");
    sealed.resize(len); send_pair(ssl, 1, sealed);
    auto host_info = recv_pair(ssl, 1, 8192+16);
    Bytes opened(8192);
    check(EVP_AEAD_CTX_open(aead, opened.data(), &len, opened.size(), nonce.data(), nonce.size(), host_info.data(), host_info.size(), nullptr, 0), "GCM open (wrong pairing code)");
    check(len == 8192 && opened[0] == 0 && std::memchr(opened.data()+1, 0, 8191), "host PeerInfo");
    // Check that the Android public key sent in PeerInfo has the same RSA modulus
    // as the actual client certificate. This detects accidental identity substitution.
    std::string line(reinterpret_cast<char*>(opened.data()+1));
    auto base64 = line.substr(0, line.find(' '));
    std::array<uint8_t, 1024> binary{}; size_t decoded = 0;
    check(EVP_DecodeBase64(binary.data(), &decoded, binary.size(), reinterpret_cast<const uint8_t*>(base64.data()), base64.size()), "Android public key base64");
    check(decoded == 524, "Android public key length");
    auto* peer = SSL_get_peer_certificate(ssl); check(peer != nullptr, "missing client certificate");
    auto* pkey = X509_get_pubkey(peer); auto* rsa = EVP_PKEY_get0_RSA(pkey);
    check(rsa != nullptr, "client certificate not RSA");
    const BIGNUM* modulus = nullptr; RSA_get0_key(rsa, &modulus, nullptr, nullptr);
    std::array<uint8_t, 256> little{}; check(BN_bn2le_padded(little.data(), little.size(), modulus), "RSA modulus encoding");
    check(std::memcmp(little.data(), binary.data()+8, little.size()) == 0, "TLS identity differs from PeerInfo");
    EVP_PKEY_free(pkey); X509_free(peer); EVP_AEAD_CTX_free(aead);
}
int main(int argc, char** argv) {
    try {
        check(argc >= 2, "expected mode: pair, wrong, stls");
        std::string mode = argv[1];
        auto* ctx = SSL_CTX_new(TLS_server_method()); check(ctx != nullptr, "TLS context");
        check(SSL_CTX_set_min_proto_version(ctx, TLS1_3_VERSION) && SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION), "TLS1.3");
        SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, [](int, X509_STORE_CTX*) { return 1; });
        auto* rsa = RSA_new(); auto* exponent = BN_new(); BN_set_word(exponent, 65537);
        check(RSA_generate_key_ex(rsa, 2048, exponent, nullptr), "RSA generation"); BN_free(exponent);
        auto* key = EVP_PKEY_new(); check(EVP_PKEY_assign_RSA(key, rsa), "RSA key");
        auto* cert = X509_new(); X509_set_version(cert, 2); ASN1_INTEGER_set(X509_get_serialNumber(cert), 1);
        X509_gmtime_adj(X509_get_notBefore(cert), -60); X509_gmtime_adj(X509_get_notAfter(cert), 86400);
        X509_set_pubkey(cert, key);
        auto* name = X509_get_subject_name(cert);
        X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, reinterpret_cast<const uint8_t*>("Adb"), -1, -1, 0);
        X509_set_issuer_name(cert, name); check(X509_sign(cert, key, EVP_sha256()) > 0, "certificate signing");
        check(SSL_CTX_use_certificate(ctx, cert) && SSL_CTX_use_PrivateKey(ctx, key), "TLS identity");
        X509_free(cert); EVP_PKEY_free(key);
        int listener = socket(AF_INET, SOCK_STREAM, 0); check(listener >= 0, "socket");
        sockaddr_in addr{}; addr.sin_family = AF_INET; addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        check(bind(listener, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0 && listen(listener, 1) == 0, "bind");
        socklen_t size = sizeof(addr); getsockname(listener, reinterpret_cast<sockaddr*>(&addr), &size);
        std::cout << ntohs(addr.sin_port) << std::endl;
        int fd = accept(listener, nullptr, nullptr); close(listener); check(fd >= 0, "accept");
        timeval timeout{10,0}; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        if (mode == "stls") { recv_adb(fd, "CNXN"); send_adb(nullptr, fd, "STLS", 0x01000000, 0, {}); recv_adb(fd, "STLS"); }
        auto* ssl = SSL_new(ctx); SSL_set_fd(ssl, fd); check(SSL_accept(ssl) == 1, "TLS handshake");
        check(SSL_version(ssl) == TLS1_3_VERSION, "incorrect TLS version");
        if (mode == "stls") {
            std::string banner("device::features=shell_v2,cmd"); Bytes bytes(banner.begin(), banner.end()); bytes.push_back(0);
            send_adb(ssl, -1, "CNXN", 0x01000001, 1048576, bytes);
        } else { pair(ssl, "123456"); }
        SSL_free(ssl); SSL_CTX_free(ctx); close(fd);
        std::cout << "BORINGSSL_INTEROP_OK" << std::endl; return 0;
    } catch (const std::exception& e) { std::cerr << e.what() << std::endl; return 1; }
}
