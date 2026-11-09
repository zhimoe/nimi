"""Run the adapter against an ephemeral local server; no external credentials."""
import base64
import hashlib
import io
import wave
import http.server
import json
import os
import subprocess
import threading
import urllib.parse

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        q = urllib.parse.parse_qs(url.query)
        salt = q.get('s', [''])[0]
        valid = q.get('u') == ['test'] and q.get('t') == [hashlib.md5(('secret' + salt).encode()).hexdigest()]
        result = {'status': 'ok' if valid else 'failed'}
        if valid and url.path.endswith('/search3.view'):
            if q.get('query') != ['中文']:
                result['status'] = 'failed'
            else:
                result['searchResult3'] = {'song': [{'id': 'song-1', 'title': '中文歌曲', 'duration': 123, 'coverArt': 'cover-1'}]}
        body = json.dumps({'subsonic-response': result}).encode()
        if valid and url.path.endswith('/stream.view') and q.get('id') == ['song-1']:
            with io.BytesIO() as buffer:
                with wave.open(buffer, 'wb') as wav:
                    wav.setnchannels(1)
                    wav.setsampwidth(2)
                    wav.setframerate(8000)
                    wav.writeframes(bytes(16000))
                body = buffer.getvalue()
        if valid and url.path.endswith('/getCoverArt.view') and q.get('id') == ['cover-1']:
            body = base64.b64decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    env = dict(os.environ, NIMI_TEST_SUBSONIC=f'http://127.0.0.1:{server.server_port}')
    result = subprocess.run(['/tmp/nimi_test_subsonic'], env=env)
finally:
    server.shutdown()
    server.server_close()
    thread.join()
raise SystemExit(result.returncode)
