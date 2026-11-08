#include <curl/curl.h>
#include <openssl/crypto.h>
#include <openssl/sha.h>

#include <stdio.h>
#include <string.h>

int main(void) {
    const curl_version_info_data *v = curl_version_info(CURLVERSION_NOW);
    const char *message = "gcpkg builds the whole curl DAG bottom-up";
    unsigned char digest[SHA256_DIGEST_LENGTH];

    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
        fprintf(stderr, "curl_global_init failed\n");
        return 1;
    }
    if (SHA256((const unsigned char *)message, strlen(message), digest) == NULL) {
        fprintf(stderr, "SHA256 failed\n");
        return 1;
    }

    printf("libcurl       : %s\n", v->version);
    printf("  SSL backend : %s\n", v->ssl_version ? v->ssl_version : "(none)");
    printf("  HTTP2       : %s\n", (v->features & CURL_VERSION_HTTP2) ? "yes" : "no");
    printf("  async DNS   : %s\n", (v->features & CURL_VERSION_ASYNCHDNS) ? "yes" : "no");
    printf("  brotli/zstd : %s / %s\n",
           (v->features & CURL_VERSION_BROTLI) ? "yes" : "no",
           (v->features & CURL_VERSION_ZSTD) ? "yes" : "no");
    printf("OpenSSL       : %s\n", OpenSSL_version(OPENSSL_VERSION_STRING));
    printf("SHA256        : ");
    for (size_t i = 0; i < SHA256_DIGEST_LENGTH; ++i) {
        printf("%02x", digest[i]);
    }
    printf("\n");

    CURL *easy = curl_easy_init();
    if (!easy) {
        fprintf(stderr, "curl_easy_init failed\n");
        return 1;
    }
    curl_easy_cleanup(easy);
    curl_global_cleanup();
    return 0;
}
