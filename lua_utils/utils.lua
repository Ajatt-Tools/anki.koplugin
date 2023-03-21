local utils = {}

function utils.get_extension(filename)
    return filename:match("%.([%a]+)$")
end

function utils.read_file(filename, line_parser)
    local fn_not_found = "ERROR: file %q was not found!"
    line_parser = line_parser or function(x) return x end
    local f, data = io.open(filename, 'r'), {}
    assert(f, fn_not_found:format(filename))
    for line in f:lines("*l") do
        table.insert(data, line_parser(line))
    end
    return data
end

function utils.split(input, sep, is_regex)
    local splits, last_idx, plain = {}, 1, true
    local function add_substring(from, to)
        local split = input:sub(from,to)
        if #split > 0 then
            splits[#splits+1] = split
        end
    end
    if is_regex == true then
        plain = false
    end

    while true do
        local s,e = input:find(sep, last_idx, plain)
        if s == nil then
            break
        end
        add_substring(last_idx, s-1)
        last_idx = e+1
    end
    add_substring(last_idx, #input)
    return splits
end

function utils.defaultdict(func)
    local f = type(func) == 'function' and func or function() return func end
    local mt = { __index = function(t, idx) return rawget(t, idx) or rawset(t, idx, f())[idx] end }
    return setmetatable({}, mt)
end

function utils.table_to_set(t, in_place)
    local t_ = (in_place or true) and t or {}
    for i,v in ipairs(t) do
        assert(utils.is_numeric(v) == false, "Table t should not contain numeric values!")
        t_[v] = i
    end
    return t_
end

function utils.path_exists(path)
    local f = io.open(path, 'r')
    if f then
        f:close()
        return true
    end
    return false
end

function utils.run_cmd(cmd)
    local output = {}
    local f = io.popen(cmd, 'r')
    for line in f:lines("*l") do
        table.insert(output, line)
    end
    f:close()
    return output
end

function utils.iterate_cmd(cmd)
    local output = {}
    local f = io.popen(cmd, 'r')
    for line in f:lines("*l") do
        table.insert(output, line)
    end
    f:close()
    return function()
        return table.remove(output, 1)
    end
end

function utils.strip_path(path)
    local stripped = string.match(path, "^.*/([^/]+)$")
    return stripped or path
end

function utils.dir_name(path)
    return utils.run_cmd(string.format("dirname %q", path))[1]
end


function utils.is_numeric_int(s)
    return string.match(s, "^%d+$") ~= nil
end

function utils.is_numeric(str)
    return string.match(str, "^-?[%d%.]+$")
end

return utils
