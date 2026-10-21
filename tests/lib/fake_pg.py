# A PostgreSQL server that misbehaves, for Test Connection:
#   fake_pg.py silent   <port>   accepts and never answers (packets lost on the way: VPN, firewall)
#   fake_pg.py password <port>   asks for a password (none in ~/.pgpass)
# Runs until killed.
import socket
import struct
import sys
import threading

mode, port = sys.argv[1], int(sys.argv[2])


def serve(conn):
    if mode == 'silent':
        threading.Event().wait()
    while True:
        head = conn.recv(8)
        if len(head) < 8:
            return
        length, code = struct.unpack('!ii', head)
        conn.recv(length - 8)
        if code == 80877103:  # SSLRequest: no SSL here
            conn.sendall(b'N')
            continue
        conn.sendall(b'R' + struct.pack('!ii', 8, 3))  # AuthenticationCleartextPassword
        conn.recv(1024)
        return


server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', port))
server.listen()
while True:
    conn, _ = server.accept()
    threading.Thread(target=serve, args=(conn,), daemon=True).start()
