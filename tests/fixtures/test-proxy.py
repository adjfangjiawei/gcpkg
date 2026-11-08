#!/usr/bin/env python3
"""Tiny HTTP proxy used by tests/proxy.sh.

Supports CONNECT (HTTPS) and absolute-form GET (plain HTTP), forwards bytes
both ways, and appends every request line to a log file. It deliberately
ignores Proxy-Authorization: the point is to prove that gcpkg passes the
proxy (and its credentials) via the child environment, not via argv.

    python3 tests/fixtures/test-proxy.py PORT LOGFILE
"""
import re
import select
import socket
import sys
import threading

PORT = int(sys.argv[1])
LOG = sys.argv[2]


def record(line):
    with open(LOG, "a") as out:
        out.write(line + "\n")
        out.flush()


def pipe(client, upstream, initial=b""):
    if initial:
        upstream.sendall(initial)
    while True:
        try:
            ready, _, _ = select.select([client, upstream], [], [], 60)
        except OSError:
            return
        if not ready:
            return
        for sock in ready:
            try:
                data = sock.recv(65536)
            except OSError:
                return
            if not data:
                return
            try:
                (upstream if sock is client else client).sendall(data)
            except OSError:
                return


def handle(client):
    try:
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = client.recv(8192)
            if not chunk:
                return
            data += chunk
        header, rest = data.split(b"\r\n\r\n", 1)
        lines = header.split(b"\r\n")
        request = lines[0].decode("latin-1")
        record(request)

        connect = re.match(r"^CONNECT\s+([^:\s]+):(\d+)\s", request)
        if connect:
            host, port = connect.group(1), int(connect.group(2))
        else:
            absolute = re.match(
                r"^([A-Z]+)\s+http://([^/\s:]+)(?::(\d+))?(/[^\s]*)\s", request)
            if not absolute:
                client.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
                return
            method, host, port, path = (absolute.group(1), absolute.group(2),
                                       int(absolute.group(3) or 80), absolute.group(4))
            kept = ["%s %s HTTP/1.1" % (method, path)]
            kept += [line.decode("latin-1") for line in lines[1:]
                     if not line.lower().startswith(b"proxy-")
                     and not line.lower().startswith(b"proxy-authorization:")]
            header = ("\r\n".join(kept) + "\r\n\r\n").encode("latin-1")

        try:
            upstream = socket.create_connection((host, port), timeout=20)
        except OSError:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            return
        if connect:
            client.sendall(b"HTTP/1.1 200 Connection established\r\n\r\n")
            pipe(client, upstream, rest)
        else:
            pipe(client, upstream, header + rest)
    finally:
        try:
            client.close()
        except OSError:
            pass


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", PORT))
    server.listen(32)
    open(LOG, "w").close()
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle, args=(client,), daemon=True).start()


if __name__ == "__main__":
    main()
