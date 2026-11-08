"""Serve a directory over HTTP with byte-range support (206 responses).

The player engine seeks with Range requests; python's built-in server
ignores them, which the player treats as an unseekable stream. Used only by
the iPhone Duo simulator check: python3 serve_range.py PORT DIRECTORY
"""
import http.server
import os
import re
import sys


class RangeHandler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        match = re.match(r'bytes=(\d*)-(\d*)$', self.headers.get('Range', ''))
        handle = open(path, 'rb')
        if not match:
            self.send_response(200)
            self.send_header('Content-Length', str(size))
            start, self._remaining = 0, size
        else:
            first, last = match.groups()
            if first:
                start = int(first)
                end = int(last) if last else size - 1
            else:
                start, end = size - int(last), size - 1
            end = min(end, size - 1)
            self.send_response(206)
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
            self.send_header('Content-Length', str(end - start + 1))
            self._remaining = end - start + 1
        handle.seek(start)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()
        return handle

    def copyfile(self, source, outputfile):
        remaining = self._remaining
        while remaining > 0:
            chunk = source.read(min(65536, remaining))
            if not chunk:
                break
            outputfile.write(chunk)
            remaining -= len(chunk)


if __name__ == '__main__':
    port, directory = int(sys.argv[1]), sys.argv[2]
    handler = lambda *a, **k: RangeHandler(*a, directory=directory, **k)
    http.server.ThreadingHTTPServer(('127.0.0.1', port), handler).serve_forever()
