"""Verifica REST y WebSocket por el mismo dominio sin crear datos ni iniciar sesión."""
import argparse,base64,hashlib,json,os,socket,ssl,urllib.request
from urllib.error import HTTPError
from urllib.parse import urlsplit

def check(base):
    u=urlsplit(base.rstrip('/'))
    if u.scheme not in ('http','https') or not u.hostname or u.username or u.password or u.query or u.fragment or u.path not in ('','/'):
        raise ValueError('Indica solo el origen HTTP/HTTPS del gateway, sin credenciales ni /api/v1.')
    base=base.rstrip('/')
    paths={'/platform-info':200,'/api/v1/auth/me':401,'/api/products':401,'/api/retazos/products':401,'/api/pedidos/products':401,'/api/ubicaciones/spaces':401,'/api/v1/logistica/rutas':401,'/api/v1/logistica/health':200}
    for path,expected in paths.items():
        try:
            with urllib.request.urlopen(base+path,timeout=15) as response:
                status=response.status;body=response.read().decode()
        except HTTPError as error:status=error.code;body=error.read().decode()
        assert status==expected,f'{path}: HTTP {status}, esperado {expected}'
        if path=='/platform-info':assert 'AlumVid API Gateway' in body
    for path in ['/ws-logistica','/ws-logistica/websocket']:
        port=u.port or (443 if u.scheme=='https' else 80)
        conn=socket.create_connection((u.hostname,port),timeout=15)
        if u.scheme=='https':conn=ssl.create_default_context().wrap_socket(conn,server_hostname=u.hostname)
        key=base64.b64encode(os.urandom(16)).decode()
        try:
            conn.sendall((f'GET {path} HTTP/1.1\r\nHost: {u.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
            data=b''
            while b'\r\n\r\n' not in data:
                chunk=conn.recv(4096)
                if not chunk:break
                data+=chunk
            headers=data.split(b'\r\n\r\n',1)[0].decode()
            assert headers.split('\r\n')[0].split()[1]=='101',f'{path}: no se pudo actualizar a WebSocket'
            expected=base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            assert expected in headers,f'{path}: handshake WebSocket inválido'
        finally:conn.close()
    print(json.dumps({'passed':True,'restChecks':len(paths),'websocketChecks':2,'url':base,'businessDataCreated':False},indent=2))
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--url',default='http://localhost:8080');args=parser.parse_args();check(args.url)
