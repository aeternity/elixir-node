from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer
import SocketServer
import requests
import json
import urllib2

class S(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

    def do_HEAD(self):
        self._set_headers()

    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = json.loads(self.rfile.read(content_length))['data']
        print post_data['query_data']['currency']
        get_data = json.loads(urllib2.urlopen("https://api.fixer.io/latest?symbols=" + post_data['query_data']['currency']).read())
        payload = {"oracle_hash":post_data['oracle_hash'], "response":get_data, "fee":10}
        req = urllib2.Request('http://localhost:4000/oracle_response')
        req.add_header('Content-Type', 'application/json')
        response = urllib2.urlopen(req, json.dumps(payload))
        self._set_headers()

def run(server_class=HTTPServer, handler_class=S, port=80):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print 'Starting httpd...'
    httpd.serve_forever()

if __name__ == "__main__":
    from sys import argv

    if len(argv) == 2:
        run(port=int(argv[1]))
    else:
        run()
