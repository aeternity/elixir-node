Python helper for managing multiple nodes and interactive testing.

Usage:
```
python2 -m virtualenv /tmp/env
source /tmp/env/bin/activate
pip install -r requirements

python2 start_helper.py
```

The script will prompt us with the following menu:
```
 [?] Welcome to node manager. Options:
       1) Create Elixir Node
       2) Create Epoch Node
       3) Create Elixir Node via SSH
       4) Create Epoch Node via SSH
       5) List managed nodes
       6) Interactive shell
       7) Connect all to chosen node
       8) Exit

```

We can choose a option using arrow keys or by pressing the corresponding number. To select the option press the enter key.

Options 6) and 7) will then prompt you in a similar manner for a node.
To exit the interactive shell use CTL+C - please note that this won't close the node process and we can later reopen the shell.

Due to this one nice line of code deeply hidden in the pwntools library: https://github.com/Gallopsled/pwntools/blob/dev/pwnlib/term/term.py#L310
tab autocompletion won't work right now.
