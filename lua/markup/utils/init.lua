local markup = require("markup")
local log = require("markup.logger") ---@diagnostic disable-line: unused-local

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

local AVG_MEASURE = {}

function utils.avg(tbl)
    local sum = 0
    local count = 0

    for _, value in pairs(tbl) do
        sum = sum + value
        count = count + 1
    end

    return count == 0 and 0 or (sum / count)
end

function utils.starts_with(str, start)
    return str:sub(1, #start) == start
end

function utils.measure_time(name, fn)
    local start_time = vim.uv.hrtime()
    local res = fn()
    local end_time = vim.uv.hrtime()

    local elapsed = end_time - start_time
    local elapsed_ms, fps = elapsed / 1e6, math.floor(1e9 / elapsed)

    AVG_MEASURE[name] = AVG_MEASURE[name] or {}
    table.insert(AVG_MEASURE[name], elapsed_ms)
    log.debug(("[%s]: %.2f ms | %d fps"):format(name, utils.avg(AVG_MEASURE[name]), fps))

    return res
end

---@param object any
---@param class any
function utils.is_instance(object, class)
    return markup.Object.is_instance(object, class) ---@diagnostic disable-line: undefined-field
end

function utils.shallow_copy(original)
    assert(type(original) == "table", "utils.shallow_copy: original must be a table")
    local copy = {}

    if vim.islist(original) then
        for _, value in ipairs(original) do
            table.insert(copy, value)
        end
    else
        for key, value in pairs(original) do
            copy[key] = value
        end
    end

    return copy
end

function utils.index_of(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
end

return utils
