local markup = require("markup")
local log = require("markup.logger")

---@class markup.Utils
local utils = {}

function utils.set_option_value(name, value, opts)
    local ok, err = pcall(vim.api.nvim_set_option_value, name, value, opts)
    if not ok then
        log.error(err)
    end
end

function utils.buf_set_opts(bufnr, options)
    if vim.api.nvim_buf_is_valid(bufnr) then
        for opt, value in pairs(options) do
            utils.set_option_value(opt, value, { buf = bufnr })
        end
    end
end

function utils.win_set_opts(winid, options)
    if vim.api.nvim_win_is_valid(winid) then
        for opt, value in pairs(options) do
            utils.set_option_value(opt, value, { win = winid, scope = "local" })
        end
    end
end

function utils.measure_time(fn)
    local start_time = vim.uv.hrtime()
    fn()
    local end_time = vim.uv.hrtime()

    local elapsed = end_time - start_time
    local elapsed_ms, fps = elapsed / 1e6, math.floor(1e9 / elapsed)
    return elapsed_ms, fps
end

---@param object any
---@param class any
function utils.is_instance(object, class)
    if not object or not object.class then
        return false
    end

    return markup.Object.is_instance(object, class) ---@diagnostic disable-line
end

function utils.shallow_copy(original)
    local copy = {}
    for _, value in ipairs(original) do
        table.insert(copy, value)
    end
    return copy
end

function utils.index_of(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
    return 0
end

return utils
