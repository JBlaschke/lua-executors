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

function M.Call:Create(mod)

    local t = {};
    t._t = {
        input = nil,
        stdout = nil,
        stderr = nil,
        exitcode = nil,
        signal = nil
    }

    local mt = getmetatable(mod)
    if mt == nil then
        mt = {
            __index = function(self, k, ...)
                return M[k]
            end,
            __tostring = tostring,
            __concat = concat
        }
    end
    return setmetatable(t, mt)
end

return M