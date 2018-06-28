#!/bin/bash

mix credo -a || exit 2
mix compile --warnings-as-errors || exit 3
mix test || exit 1
mix format
git commit -am 'mix format'
git push
