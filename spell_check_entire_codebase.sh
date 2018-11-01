#/usr/bin/env bash

find . -iname "*.ex" -o -iname "*.exs" | grep "/lib/" | grep -v deps | grep -v _build | xargs -I cmd sh -c "cat cmd | nl -ba -w 1 | sed 's@^[0-9]*@cmd:&@'" | pcregrep -M "\"\"\".*?(\n|.)*?.*?\"\"\"|#[^{].*?\n|:error, \"(\n|.)*?\"" > /tmp/spell; aspell -l en -d en -c /tmp/spell; rm /tmp/spell;

