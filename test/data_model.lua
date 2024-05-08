local dm = require "data_model"


local q = {}
local args = {a=1, c=true}

local x = dm.Call:new("cmd", q, args)

x.__input = "input"
x.__stdout = "stdout"
x.__stderr = "stderr"
x.__signal = 1
x.__exitcode = 2
x.b = "b"
x[1] = "1"

print("_______________________________________________________________________")
print("Checking the contents of `args`:")
print("-----------------------------------------------------------------------")

local arg_target = {a=1, b="b", c=true, [1]="1"}
-- check arg
for k, v in pairs(args) do
    print("Checking: args[" .. k .. "] = " .. tostring(v))
    assert(v == arg_target[k])
    arg_target[k] = nil
end
-- enure that arg isn't missing anything
assert(nil == next(arg_target))
print("")

print("_______________________________________________________________________")
print("Checking the contents of `_t`:")
print("-----------------------------------------------------------------------")

local t_target = {
    input="input", stdout="stdout", stderr="stderr", signal=1, exitcode=2,
    command="cmd", previous = x.__previous
}
-- check t._t
for k, v in pairs(x._t) do
    print("Checking: x._t[" .. k .. "] = " .. tostring(v))
    assert(v == t_target[k])
    t_target[k] = nil
end
-- ensure that t._t isn't missing anything
assert(nil == next(t_target))
print("")

print("_______________________________________________________________________")
print("Testing Call's pairs iterator:")
print("-----------------------------------------------------------------------")

local x_target = {
    __input="input", __stdout="stdout", __stderr="stderr", __signal=1,
    __exitcode=2, __command="cmd", __previous=x.__previous, [1]="1", a=1, b="b",
    c=true
}
-- check the custom pairs iterator for Call
for k, v in pairs(x) do
    print("Checking: x[" .. k .. "] = " .. tostring(v))
    assert(v == x_target[k])
    x_target[k] = nil
end
-- ensure that x isn't missing anything
assert(nil == next(x_target))
print("")

print("_______________________________________________________________________")
print("Testing Call's ipairs iterator:")
print("-----------------------------------------------------------------------")

local x_i_target = {[1]="1"}
-- check x[<index>]
for i, v in ipairs(x) do
    print("Checking x[" .. i .. "] = " .. tostring(v))
    assert(v == x_i_target[i])
    x_i_target[i] = nil
end
--ensure that x[i] isn't missing anything
assert(nil == next(x_i_target))
print("")

print("_______________________________________________________________________")
print("ALL TESTS PASSED SUCCESSFULLY")
print("-----------------------------------------------------------------------")

for k, v in pairs(dm.flatten(x)) do
    print(k, v)
    if "args" == k then
        for k1, v1  in pairs(v) do
            print("    ", k1, v1)
        end
    end
end

print(dm.tostring(x))