#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/sha.h>

#include <stdio.h>
#include <string.h>

int main(void) {
    const char *message = "gcpkg builds OpenSSL and indexes it with clangd";
    unsigned char digest[SHA256_DIGEST_LENGTH];

    if (SHA256((const unsigned char *)message, strlen(message), digest) == NULL) {
        fprintf(stderr, "SHA256 failed\n");
        return 1;
    }

    printf("linked OpenSSL : %s\n", OpenSSL_version(OPENSSL_VERSION_STRING));
    printf("message        : %s\n", message);
    printf("SHA256         : ");
    for (size_t i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
        printf("%02x", digest[i]);
    }
    printf("\n");
    return 0;
}
