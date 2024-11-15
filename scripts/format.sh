#!/usr/bin/env bash

project_dir=~/projects/markup.nvim

find $project_dir/lua -name "*.lua" -exec stylua {} \;
find $project_dir/tests -name "*.lua" -exec stylua {} \;
