import os

class Singleton(type):
    _instances = {}
    def __call__(cls, *args, **kwargs):
        if cls not in cls._instances:
            cls._instances[cls] = super(Singleton, cls).__call__(*args, **kwargs)
        return cls._instances[cls]

class ConfigurationCreator():
    __metaclass__ = Singleton

    def __init__(self):
        self.next_port = 8000
        self.tmp_path = "/tmp"
        self.max_known_tmp_number = 1

        path = os.path.dirname(os.path.abspath(__file__))

        with open(os.path.join(path, "epoch_config_template.config"), "r") as f:
            self.epoch_template = f.read()

    def get_unused_port(self):
        port = self.next_port
        self.next_port += 1
        return port

    def get_unused_tmp_path(self, name):
        while(1):
            tmp_path = os.path.join(self.tmp_path, "%s-node-%05d" % (name, self.max_known_tmp_number))
            self.max_known_tmp_number += 1

            if not os.path.isdir(tmp_path):
                os.mkdir(tmp_path)
                return tmp_path

    def get_epoch_template(self):
        return self.epoch_template