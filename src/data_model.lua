--
-- We'll be overwriding the lua `tostring` function, so keep a reference to the
-- original lua version here:
---
local _lua_tostring = tostring

local M = {}


--
-- converts key and it's argument to "-k" or "-k=v" or just ""
--
local function arg(k, a)
    if not a then return k end
    if type(a) == "string" and #a > 0 then return k .. "=\'" .. a .. "\'" end
    if type(a) == "number" then return k .. "=" .. _lua_tostring(a) end
    if type(a) == "boolean" and a == true then return k end
    error("invalid argument type: " .. type(a), a)
end


--
-- converts nested tables into a flat list of arguments and concatenated input
--
function M.flatten(t)
    local result = {
        args = {}, input = "", __stdout = "", __stderr = "",
        __exitcode = nil, __signal = nil
    }

    local function f(t)
        local keys = {}
        for k = 1, #t do
            keys[k] = true
            local v = t[k]
            if type(v) == "table" then
                f(v)
            else
                table.insert(result.args, _lua_tostring(v))
            end
        end
        for k, v in pairs(t) do
            if k == "__input" then
                result.input = result.input .. v
            elseif k == "__stdout" then
                result.__stdout = result.__stdout .. v
            elseif k == "__stderr" then
                result.__stderr = result.__stderr .. v
            elseif k == "__exitcode" then
                result.__exitcode = v
            elseif k == "__signal" then
                result.__signal = v
            elseif not keys[k] and k:sub(1, 1) ~= "_" then
                local key = '-' .. k
                if #k > 1 then key = "-" .. key end
                table.insert(result.args, arg(key, v))
            end
        end
    end

    f(t)
    return result
end


--
-- return a string representation of a shell command output
--
local function strip(str)
    -- capture repeated charaters (.-) startign with the first non-space ^%s,
    -- and not captuing any trailing spaces %s*
    return str:match("^%s*(.-)%s*$")
end


local function tostring(self)
    -- return trimmed command output as a string
    local out = strip(self.__stdout)
    local err = strip(self.__stderr)
    if #err == 0 then
        return out
    end
    -- if there is an error, print the output and error string
    return "O: " .. out .. "\nE: " .. err .. "\n" .. self.__exitcode
end


--
-- the concatenation (..) operator must be overloaded so you don't have to keep
-- calling `tostring`
--
local function concat(self, rhs)
    local out, err = self, ""
    if type(out) ~= "string" then
        out, err = strip(self.__stdout), strip(self.__stderr)
    end

    if #err ~= 0 then
        out = "O: " .. out .. "\nE: " .. err .. "\n" .. self.__exitcode
    end

    -- errors when type(rhs) == "string" for some reason
    return out..(type(rhs) == "string" and rhs or tostring(rhs))
end


M.Call = {}

function M.Call:Create(mod, tbl)

    local t = {}
    t._t = {
        input = {},
        stdout = {},
        stderr = {},
        exitcode = {},
        signal = {}
    }

    local mt = getmetatable(mod)
    if mt == nil then mt = {} end

    --
    -- Upated index function, which inherits __index from `mod` execpt for keys
    -- in `t._t`. Valid keys to `t._t` need to be prefixed by `__`, and take
    -- precident over keys from `tbl` and `mod`.
    --
    ---@diagnostic disable-next-line: unused-local, redefined-local
    mt.__index = function(self, k)
        --
        -- check if the index is `__{key}` where key is a valid key to `t._t`. 
        -- If `key` does exist in `t._t` then use `key` to index into `t._t`.
        -- If it does not exist in`t._t`, then default to indexing into `tbl`
        -- first, then followd by `mod`.
        --

        -- allow direct indexing of `t._t`:
        if k == "_t" then return t._t end

        -- try `t._t` (prefixing `__`)
        if string.len(k) > 2 then
            if k:sub(1, 2) == "__" then
                local key = k:sub(3, #k)
                if nil ~= t._t[key] then return t._t[key] end
            end
        end

        -- next try `tbl`
        if nil ~= tbl[k] then return tbl[k] end

        -- finally default to `mod`
        return mod[k]
    end

    --
    -- Upated newindex function, which inherits __newindex from `tbl` execpt for
    -- keys in `t._t`. Valid keys to `t._t` need to be prefixed by `__`, and
    -- take precident over keys from `tbl`. `mod` will not be modified directly.
    --
    ---@diagnostic disable-next-line: unused-local, redefined-local
    mt.__newindex = function(self, k, v)
        --
        -- check if the index is `__{key}` where key is a valid key to `t._t`. 
        -- If `key` does exist in `t._t` then use `key` to index into `t._t`.
        -- If it does not exist in`t._t`, then default to indexing into `tbl`.
        --

        -- don't allow setting `t._t` directly

        -- try `t._t` (prefixing `__`)
        if string.len(k) > 2 then
            if k:sub(1, 2) == "__" then
                local key = k:sub(3, #k)
                if nil ~= t._t[key] then t._t[key] = v end
            end
        end

        -- default to `tbl`
        tbl[k] = v
    end


    local __next = function(self, k)
        if nil == k then
            return next(t._t, nil)
        end
        -- try `t._t` (prefixing `__`)
        if string.len(k) > 2 then
            if k:sub(1, 2) == "__" then
                local key = k:sub(3, #k)
                if nil ~= t._t[key] then return next(t._t, key) end
            end
        end
        if nil ~= tbl[k] then return next(tbl, k) end
    end


    ---@diagnostic disable-next-line: redefined-local
    mt.__pairs = function(self)
        -- iterator state: start iterating over `t._t` (0) then `tbl` (1)
        local state = 0

        -- iterator function takes the table and an index and returns the next
        -- index and associated value or nil to end iteration
        ---@diagnostic disable-next-line: redefined-local
        local function stateless_iter(self, k)
            local v
            if 0 == state then
                print(k)
                k, v = __next(t._t, k)
                if nil ~= v then
                    return "__" .. k, v
                else
                    state = 1
                    return stateless_iter(self, k)
                end
            elseif 1 == state then
                k, v = next(tbl, k)
                if nil ~= v then
                    return k, v
                else
                    state = 2
                    return stateless_iter(self, k)
                end
            else
                return nil
            end
        end

        -- Return an iterator function, the table, starting point
        return stateless_iter, self, nil
    end


    ---@diagnostic disable-next-line: redefined-local
    mt.__ipairs = function(self)
        -- iterator state: start iterating over `t._t` (0) then `tbl` (1)
        local state = 0
        local offset = 0

        -- iterator function takes the table and an index and returns the next
        -- index and associated value or nil to end iteration
        ---@diagnostic disable-next-line: redefined-local
        local function stateless_iter(self, i)
            local v
            if 0 == state then
                i = i + 1
                v = self._t[i]
                if nil ~= v then
                    return i, v
                else
                    offset = i
                    state = 1
                    return stateless_iter(self, i)
                end
            elseif 1 == state then
                i = i + 1 - offset
                v = tbl[i]
                if nil ~= v then
                    return i, v
                else
                    state = 2
                    return stateless_iter(self, i)
                end
            else
                return nil
            end
        end

        -- Return an iterator function, the table, starting point
        return stateless_iter, self, 0
    end

    -- mt.__tostring = tostring
    -- mt.__concat = concat
    return setmetatable(t, mt)
end

return M
