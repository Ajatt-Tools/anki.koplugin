local List = {}
local list_mt = {
    __index = function(t, k) return rawget(List, k) or rawget(t:get(), k) end,
    __tostring = function(x) return "['" .. table.concat(x:get(), "', '") .. "']" end
}

function List:new(table)
    local data = table
    for _,x in ipairs(data) do data[x] = true end
    return setmetatable({ _data = table }, list_mt)
end

function List:from_iter(iter)
    local data = {}
    for x in iter do
        table.insert(data, x)
        data[x] = true
    end
    return setmetatable({ _data = data }, list_mt)
end

function List:get()
    return rawget(self, "_data")
end

function List:contains(item)
    return self:get()[item] ~= nil
end

function List:contains_any(other)
    for _,x in ipairs(self:get()) do
        if other:contains(x) then return true end
    end
    return false
end

return List
