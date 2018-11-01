#/usr/bin/env bash

function filter_codebase {
find . -iname "*.ex" -o -iname "*.exs" | grep -E "/lib/|/test/|/config/" | grep -v deps | grep -v _build | xargs -I cmd sh -c "cat cmd | nl -ba -w 1 | sed 's@^[0-9]*@cmd:&@'" | pcregrep -M "\"\"\".*?(\n|.)*?.*?\"\"\"|#[^{].*?\n|:error, \"(\n|.)*?\"" | sort > $1
}

ORIG=$(git branch | grep \* | cut -d ' ' -f2);

filter_codebase /tmp/spell_orig;

git stash;
git checkout master;
git reset --hard master;

filter_codebase /tmp/spell_master;

# https://stackoverflow.com/questions/18204904/fast-way-of-finding-lines-in-one-file-that-are-not-in-another
diff --new-line-format="" --unchanged-line-format=""  /tmp/spell_orig /tmp/spell_master > /tmp/spell;

git checkout $ORIG;
git stash apply;
git stash drop;

rm /tmp/spell_orig;
rm /tmp/spell_master;

aspell -l en -d en -c /tmp/spell;

rm /tmp/spell;
