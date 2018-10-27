from abc import ABCMeta, abstractmethod
import shutil
import pwn

class Node(object):
    __metaclass__ = ABCMeta

    def __init__(self, build_path):
        self.build_path = build_path
        self.process = self. create_handle()

    @abstractmethod
    def create_handle(self):
        pass

    @abstractmethod
    def get_sync_host_and_port(self):
        pass

    @abstractmethod
    def get_signing_pubkey(self):
        pass

    @abstractmethod
    def get_connection_pubkey(self):
        pass

    @abstractmethod
    def connect_to(self, host, port, pubkey):
        pass

    def connect_with(self, node):
        pwn.info("Connecting " + node.tmp_dir + " to node " + self.tmp_dir)
        self.connect_to(node.get_sync_host_and_port(), node.get_connection_pubkey())

    def clean(self):
        shutil.rmtree(self.tmp_dir)

    @abstractmethod
    def before_interactive(self):
        pass

    def interactive(self):
        self.process.clean()
        self.before_interactive()
        self.process.interactive(prompt=pwn.term.text.bold_red(self.tmp_dir + '$') + ' ')
