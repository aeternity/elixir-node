from node import Node
from configuration_creator import ConfigurationCreator
import pwn
import re
import os
import shutil

class EpochNode(Node):
    def create_handle(self):

        path = os.path.dirname(os.path.abspath(__file__))

        self.tmp_dir = ConfigurationCreator().get_unused_tmp_path("epoch")
        os.makedirs(os.path.join(self.tmp_dir, "data/aecore/keys/"))
        os.mkdir(os.path.join(self.tmp_dir, "data/aecore/.genesis"))
        shutil.copy(os.path.join(path, "accounts.json"), os.path.join(self.tmp_dir, "data/aecore/.genesis"))
        conf_template = ConfigurationCreator().get_epoch_template()
        self.sync_port = ConfigurationCreator().get_unused_port()
        self.conf_path = os.path.join(self.tmp_dir, "system.config")

        conf_template = conf_template.replace("CONF_HTTP_PORT", str(ConfigurationCreator().get_unused_port()))
        conf_template = conf_template.replace("CONF_INTERNAL_PORT", str(ConfigurationCreator().get_unused_port()))
        conf_template = conf_template.replace("CONF_INTERNAL_WEBSOCKET_PORT", str(ConfigurationCreator().get_unused_port()))
        conf_template = conf_template.replace("CONF_CHANNEL_WEBSOCKET_PORT", str(ConfigurationCreator().get_unused_port()))
        conf_template = conf_template.replace("CONF_SYNC_PORT", str(self.sync_port))
        conf_template = conf_template.replace("CONF_TMP_DIR", self.tmp_dir)

        with open(self.conf_path, "w") as f:
            f.write(conf_template)

        process = pwn.process([os.path.join(self.build_path, "./rebar3"), "shell", "--config", self.conf_path], raw=False, shell=False, cwd=self.build_path)
        process.readuntil("aec_peers started at", timeout=10)

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
        raise NotImplementedError

    def get_connection_pubkey(self):
        self.process.sendline("{ok, Pub} = aec_keys:peer_pubkey().")
        self.process.clean()
        self.process.sendline("erlang:display(Pub).")
        res = self.read_binary()
        self.process.sendline("f(Pub).")
        return res

    def get_sync_host_and_port(self):
        return ("localhost", self.sync_port)

    def get_signing_pubkey(self):
        self.process.sendline("{ok, Pub} = aec_keys:pubkey().")
        self.process.clean()
        self.process.sendline("erlang:display(Pub).")
        res = self.read_binary()
        self.process.sendline("f(Pub).")
        return res

    def connect_to(self, conn, pubkey):
        (host, port) = conn
        self.process.clean()
        self.process.sendline("aec_peers:add_and_ping_peers([#{ host => <<\""+host+"\">>, port => "+str(port)+", pubkey => "+pubkey+" }]).")
        assert "ok" == self.sanitize_data(self.process.readline())

    def before_interactive(self):
        self.process.sendline("2+2.")
        self.process.readline()

    def __str__(self):
        return "Epoch, logs: " + self.tmp_dir + ", addr: " + str(self.get_sync_host_and_port()) + ", peer_pub: " + self.get_connection_pubkey() +", sign_pub: " + self.get_signing_pubkey()



