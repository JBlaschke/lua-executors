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

function M.Call:new(cmd, mod, tbl)

    local t = {}
    t._t = {
        command = cmd,
        input = "",
        stdout = "",
        stderr = "",
        exitcode = -1,
        signal = -1,
        previous = {}
    }

    local mt = getmetatable(mod)
    if mt == nil then mt = {} end

    --
    -- Upated index function, which inherits __index from `mod` execpt for keys
    -- in `t._t`. Valid keys to `t._t` need to be prefixed by `__`, and take
    -- precident over keys from `tbl` and `mod`.
    --
    mt.__index = function(obj, k)
        --
        -- check if the index is `__{key}` where key is a valid key to `t._t`. 
        -- If `key` does exist in `t._t` then use `key` to index into `t._t`.
        -- If it does not exist in`t._t`, then default to indexing into `tbl`
        -- first, then followd by `mod`.
        --

        -- allow for class methods
        if rawget(M.Call, k) ~= nil then return rawget(M.Call, k) end

        -- allow direct indexing of `t._t`:
        if k == "_t" then return t._t end

        -- try `t._t` (prefixing `__`)
        if string.len(k) > 2 then
            if k:sub(1, 2) == "__" then
                local key = k:sub(3, #k)
                if nil ~= obj._t[key] then return obj._t[key] end
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
    mt.__newindex = function(obj, k, v)
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
                if nil ~= obj._t[key] then
                    obj._t[key] = v
                    return
                end
            end
        end

        -- default to `tbl`
        tbl[k] = v
    end

    --
    -- Updated pairs iterator, which starts with `_t` and then moves onto `tbl`
    --
    mt.__pairs = function(iter)
        -- iterator state: start iterating over `t._t` (0) then `tbl` (1)
        local state = 0

        -- iterator function takes the table and an index and returns the next
        -- index and associated value or nil to end iteration
        local function stateless_iter(sl_iter, k)
            local v
            if 0 == state then
                k, v = sl_iter:__next(tbl, k, state)
                if nil ~= v then
                    return k, v
                else
                    state = 1
                    return stateless_iter(sl_iter, k)
                end
            elseif 1 == state then
                k, v = sl_iter:__next(tbl, k, state)
                if nil ~= v then
                    return k, v
                else
                    state = 2
                    return stateless_iter(sl_iter, k)
                end
            else
                return nil
            end
        end

        -- Return an iterator function, the table, starting point
        return stateless_iter, iter, nil
    end

    --
    -- Updated ipairs iterator, which starts with `_t` and then moves onto `tbl`
    --
    mt.__ipairs = function(iter)
        -- iterator state: start iterating over `t._t` (0) then `tbl` (1)
        local state = 0

        -- iterator function takes the table and an index and returns the next
        -- index and associated value or nil to end iteration
        local function stateless_iter(sl_iter, i)
            local v
            if 0 == state then
                i = i + 1
                v = sl_iter._t[i]
                if nil ~= v then
                    return i, v
                else
                    i = 0
                    state = 1
                    return stateless_iter(sl_iter, i)
                end
            elseif 1 == state then
                i = i + 1
                v = tbl[i]
                if nil ~= v then
                    return i, v
                else
                    state = 2
                    return stateless_iter(sl_iter, i)
                end
            else
                return nil
            end
        end

        -- Return an iterator function, the table, starting point
        return stateless_iter, iter, 0
    end

    -- mt.__tostring = tostring
    -- mt.__concat = concat
    return setmetatable(t, mt)
end

--
-- Iterate which iterates over `_t` if and only if `state == 0`. When iterating
-- over `_t` it prefixes `__` to the keys.
--
function M.Call:__next(tbl, k, state)
    state = state or 0
    -- initiate iteration based `state`
    if nil == k and 0 == state then
        local nk, nv = next(self._t, nil)
        if nil ~= nv then
            return "__" .. nk, nv
        end
        return
    elseif nil == k then
        return next(tbl, nil)
    end

    -- try `t._t` (prefixing `__`)
    if string.len(k) > 2 then
        if k:sub(1, 2) == "__" then
            local key = k:sub(3, #k)
            if nil ~= self._t[key] then
                local nk, nv = next(self._t, key)
                if nil ~= nv then
                    return "__" .. nk, nv
                end
            end
        end
    end

    -- try tbl
    if nil ~= tbl[k] then return next(tbl, k) end
end

return M
