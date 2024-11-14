#!/usr/bin/env bash

find ~/projects/markup.nvim/lua -name "*.lua" -exec stylua {} \;
find ~/projects/markup.nvim/tests -name "*.lua" -exec stylua {} \;
