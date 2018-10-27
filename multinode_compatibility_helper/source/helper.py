import os
import pwn
from elixir import ElixirNode
from epoch import EpochNode

class InteractiveHelper:
    def __init__(self):
        self.path = os.path.dirname(os.path.abspath(__file__))
        self.nodes = []

    def start(self):
        try:
            while(1):
                choice = pwn.ui.options("Welcome to node manager. Options:", [
                    "Create Elixir Node",
                    "Create Epoch Node",
                    "Create Elixir Node via SSH",
                    "Create Epoch Node via SSH",
                    "List managed nodes",
                    "Interactive shell",
                    "Connect all to chosen node",
                    "Exit"
                ])

                if(choice == 0):
                    self.nodes.append(ElixirNode(os.path.join(self.path, "../../")))

                if(choice == 1):
                    self.nodes.append(EpochNode("/home/test/epoch"))

                if(choice == 4):
                    print "Nodes:"
                    for id, node in enumerate(self.nodes):
                        print pwn.term.text.bold_red(str(id+1)+"): ")+str(node)
                        print("")

                if(choice == 5):
                    node_choice = pwn.ui.options("Nodes:", map(str, self.nodes) + ["Back"])
                    if node_choice != len(self.nodes):
                        self.nodes[node_choice].interactive()

                if(choice == 6):
                    node_choice = pwn.ui.options("Nodes:", map(str, self.nodes) + ["Back"])
                    if node_choice != len(self.nodes):
                        connect_to = self.nodes[node_choice]
                        for id, node in enumerate(self.nodes):
                            if id != node_choice:
                                connect_to.connect_with(node)


                if(choice == 7):
                    break

        except KeyboardInterrupt:
            pass

        delete = False
        try:
            if pwn.ui.yesno("Do you want to remove the temporary paths with logs?"):
                delete = True

        except KeyboardInterrupt:
            delete = True

        if delete:
            for node in self.nodes:
                node.clean()
