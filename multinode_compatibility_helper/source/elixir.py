from node import Node
from configuration_creator import ConfigurationCreator
import pwn
import re
import os

class ElixirNode(Node):
    def create_handle(self):

        self.tmp_dir = ConfigurationCreator().get_unused_tmp_path("elixir")
        self.sync_port = ConfigurationCreator().get_unused_port()

        env = os.environ
        env["PEER_KEYS_PATH"] = self.tmp_dir
        env["SIGN_KEYS_PATH"] = self.tmp_dir
        env["PERSISTENCE_PATH"] = self.tmp_dir
        env["MIX_ENV"] = "prod"
        env["SYNC_PORT"] = str(self.sync_port)

        process = pwn.process(["iex", "-S", "mix"], raw=False, shell=False, cwd=self.build_path, env=env)
        process.recvuntil("iex(1)>", timeout=2)
        process.sendline("")
        process.recvuntil("iex(2)>", timeout=2)

        self.ansi_escape = re.compile(r'\x1B\[[0-?]*[ -/]*[@-~]')
        return process

    def color_code_escape(self, text):
        return self.ansi_escape.sub('', text)

    def sanitize_data(self, data):
        data = data.strip().lstrip().replace("\n", "").replace("\r", "").replace(" ", "")
        return self.color_code_escape(data)

    def read_binary(self):
        self.process.recvuntil("<<")
        data = "<<" + self.process.recvuntil(">>")
        return self.sanitize_data(data)

    def get_serialized_object(self, name):
        self.process.sendline("{:ok, serialized_obj} = Serialization.rlp_encode(%s)" % name)
        self.process.clean()
        self.process.sendline("IO.inspect(serialized_obj, limit: :infinity)")
        return self.read_binary()

    def get_connection_pubkey(self):
        self.process.clean()
        self.process.sendline("IO.inspect(Peers.state.local_peer.pubkey, limit: :infinity)")
        return self.read_binary()

    def get_sync_host_and_port(self):
        return ("localhost", self.sync_port)

    def get_signing_pubkey(self):
        self.process.sendline("{pub, _} = Keys.keypair(:sign)")
        self.process.clean()
        self.process.sendline("IO.inspect(Peers.state.local_peer.pubkey, limit: :infinity)")
        return self.read_binary()

    def connect_to(self, conn, pubkey):
        (host, port) = conn
        self.process.clean()
        self.process.sendline("Peers.try_connect(%{host: '"+host+"', port: "+str(port)+", pubkey: "+pubkey+"})")
        assert ":ok" == self.sanitize_data(self.process.readline())

    def before_interactive(self):
        self.process.sendline("2+2")
        self.process.readline()

    def __str__(self):
        return "Elixir, logs: " + self.tmp_dir + ", addr: " + str(self.get_sync_host_and_port()) + ", peer_pub: " + self.get_connection_pubkey() + ", sign_pub: " + self.get_signing_pubkey()



