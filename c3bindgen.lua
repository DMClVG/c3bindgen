-- MIT License

-- Copyright (c) 2022 DMClVG

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- c3bindgen.lua v0.0.1

package.path = package.path..";./lua-c-parser/?.lua"
package.cpath = package.cpath..";./lua-c-parser/?.so"

local inspect = require("inspect")
local cparser = require("cparser")
local table = table
local floor = math.floor
local tinsert = table.insert

local c3TypeMap = {
    ["char"] = "char",
    ["signed char"] = "ichar",
    ["short"] = "CShort",
    ["int"] = "CInt",
    ["long"] = "CLong",
    ["long long"] = "CLongLong",
    ["unsigned char"] = "char",
    ["unsigned short"] = "CUShort",
    ["unsigned int"] = "CUInt",
    ["unsigned long"] = "CULong",
    ["unsigned long long"] = "CULongLong",

    ["int8_t"] = "ichar",
    ["int16_t"] = "short",
    ["int32_t"] = "int",
    ["int64_t"] = "long",
    ["uint8_t"] = "char",
    ["uint16_t"] = "ushort",
    ["uint32_t"] = "uint",
    ["uint64_t"] = "ulong",
    ["size_t"] = "isize",
    ["usize_t"] = "usize",
    ["wchar_t"] = "char",
}

local kwReplacements = {
    ["fn"] = "func",
    ["macro"] = "_macro"
}

local function firstToUpper(str)
    return (str:gsub("^_*%l", string.upper))
end

local function firstToLower(str)
    return (str:gsub("^_*%u", string.lower))
end

local function pascalCase(str)
    str = firstToUpper(str)
    str = str:gsub("_+%l", string.upper)
    return str
end

local function camelCase(str)
    str = str:lower()
    str = str:gsub("_+%l", string.upper)
    return str
end

local function replaceKw(str)
    if kwReplacements[str] then
        return kwReplacements[str]
    else
        return str
    end
end

local function isEmpty(str)
    return not str or #str == 0
end

local function toTypeName(name)
    return pascalCase(name:lower())
end

local function toFieldName(name)
    return camelCase(name:lower())
end

local function toConstName(name)
    return name:upper()
end

local function toFunctionName(name)
    return camelCase(name:lower())
end


local module = {
    name=arg[1],
    structs={},
    enums={},
    unions={},
    fns={},
    defs={}
}

function struct(name, ...)
    local fields = {...}
    assert(not isEmpty(name))
    if #fields == 0 then
        return table.concat({ "define ", name, " = void;"})
    end

    local out = { "struct ", name, " {"}

    for _, field in ipairs(fields) do
        tinsert(out, "\n\t")
        tinsert(out, field.type)
        if field.name then -- FIXME: uggly
            tinsert(out, " ")
            tinsert(out, field.name)
            tinsert(out, ";")
        end
    end
    tinsert(out, "\n}")
    return table.concat(out)
end

function union(name, ...)
    local fields = {...}
    assert(not isEmpty(name))
    local out = { "union ", name, " {"}

    for _, field in ipairs(fields) do
        tinsert(out, "\n\t")
        tinsert(out, field.type)
        if field.name then
            tinsert(out, " ")
            tinsert(out, field.name)
            tinsert(out, ";")
        end
    end
    tinsert(out, "\n}")
    return table.concat(out)
end

function enum(name, ...)
    assert(false)
    local fields = {...}
    assert(not isEmpty(name))
    local out = { "enum ", name , " {"}

    for _, field in ipairs(fields) do
        tinsert(out, "\n\t")
        tinsert(out, field.name)
        tinsert(out, " = ")
        tinsert(out, field.value)
        tinsert(out, ",")
    end
    tinsert(out, "\n}")
    return table.concat(out)
end

function fn(name, inline, extname, ret, ...)
    local params = {...}
    assert(not isEmpty(name))
    assert(not isEmpty(ret))

    local out = { "extern fn ", ret, " ", name, "("}
    for i, param in ipairs(params) do
        tinsert(out, param.type)
        tinsert(out, " ")
        tinsert(out, param.name)
        if i ~= #params then
            tinsert(out, ", ")
        end
    end
    tinsert(out, ")")
    if inline then
        tinsert(out, " @inline")
    end
    if not isEmpty(extname) then
        tinsert(out, " @extname(\"")
        tinsert(out, extname)
        tinsert(out, "\")")
    end
    tinsert(out, ";")
    return table.concat(out)
end


function define(name, value)
    assert(not isEmpty(name))
    assert(not isEmpty(value))
    return table.concat({ "define ", name, " = ", value, ";"})
end


if #arg ~= 3 then
    error("Usage: c3bindgen [module] [header-path] [filter]")
end

local path = arg[2]
local filter = "^"..arg[3].."$"

local decls = cparser.parse(path)


function resolveType(t)
    if type(t) == "string" then
        return t
    elseif t.tag == "decl" then
        return resolveType(decls[t.decl])
    elseif t.tag == "pointer" then
        return { tag="pointer", type=resolveType(t.type) }
    elseif t.tag == "array" then
        return { tag="array", type=resolveType(t.type), n=floor(t.n) }
    elseif t.tag == "typedef" then
        if c3TypeMap[t.type] then
            return c3TypeMap[t.type]
        end

        local underlying = resolveType(t.underlying_type)
        if type(underlying) == "table" and (underlying.tag == "union" or underlying.tag == "struct" or underlying.tag == "enum") and isEmpty(underlying.name) then
            return t
        else
            return underlying
        end
    elseif t.tag == "struct" or t.tag == "enum" or t.tag == "union" then
        return t
    elseif t.tag == "function-pointer" then
        return t
    else
        assert(false, inspect(t))
    end
end

function getFieldSpelling(fieldName, t)
    if fieldName then
        fieldName = toFieldName(fieldName)
        fieldName = replaceKw(fieldName)
    end
    if type(t) == "string" then
        if t:match("^const ") then
            t = t:sub(7, #t)
        end
        if c3TypeMap[t] then
            t = c3TypeMap[t]
        end
        return {name=fieldName, type=t}
    elseif t.tag == "pointer" then
        return {name=fieldName, type=getFieldSpelling(nil, t.type).type.."*"}
    elseif t.tag == "array" then
        return {name=fieldName, type=table.concat({getFieldSpelling(nil, t.type).type, "[", floor(t.n), "]"})}
    elseif t.tag == "typedef" then
        return {name=fieldName, type=toTypeName(t.type)}
    elseif t.tag == "struct" then
        if isEmpty(t.name) then
            return {type=struct(fieldName, table.unpack(getFields(t)))} -- anonymous struct
        else
            return {name=fieldName, type=toTypeName(t.name)}
        end
    elseif t.tag == "union" then
        if isEmpty(t.name) then
            return {type=union(fieldName, table.unpack(getFields(t)))} -- anonymous union
        else
            return {name=fieldName, type=toTypeName(t.name)}
        end
    elseif t.tag == "enum" then
        if isEmpty(t.name) then
            return {type=enum(fieldName, table.unpack(getFields(t)))} -- anonymous enum
        else
            return {name=fieldName, type=toTypeName(t.name)}
        end
    elseif t.tag == "function-pointer" then
        return {name=fieldName, type="FunPtr*"}
    else
        assert(false, inspect(t))
    end
end

function getUnderlyingType(t)
    if type(t) == "string" then
        return t
    elseif t.tag == "decl" then
        return getUnderlyingType(decls[t.decl])
    elseif t.tag == "typedef" then
        return getUnderlyingType(t.underlying_type)
    else
        return t
    end
end

function getFields(decl)
    if decl.tag == "struct" or decl.tag == "union" then
        local fields = {}
        for _, field in ipairs(decl.fields) do
            local name = toFieldName(field.name)
            local type = resolveType(field.type)
            tinsert(fields, getFieldSpelling(name, type))
        end
        return fields
    elseif decl.tag == "enum" then
        local fields = {}
        for _, field in ipairs(decl.fields) do
            local name = toConstName(field.name)
            tinsert(fields, { name=name, value=field.value})
        end
        return fields
    end
end

function getParams(decl)
    local params = {}
    for _, param in ipairs(decl.params) do
        local name = toFieldName(param.name)
        local type = resolveType(param.type)
        tinsert(params, getFieldSpelling(name, type))
    end
    return params
end

-- print(inspect(decls))

for _, decl in ipairs(decls) do
    if decl.tag == "typedef" and decl.type:match(filter) then
        local underlying = getUnderlyingType(decl.underlying_type)
        if type(underlying) == "table" and (underlying.tag == "union" or underlying.tag == "struct" or underlying.tag == "enum") and isEmpty(underlying.name) then
            tinsert(module[underlying.tag.."s"], { name=toTypeName(decl.type), fields=getFields(underlying) })
        end
    end

    if decl.tag == "struct" and not isEmpty(decl.name) and decl.name:match(filter) then
        tinsert(module.structs, { name=toTypeName(decl.name), fields=getFields(decl) })
    end 
    if decl.tag == "union" and not isEmpty(decl.name) and decl.name:match(filter) then
        tinsert(module.unions, { name=toTypeName(decl.name), fields=getFields(decl) })
    end 
    if decl.tag == "enum" and not isEmpty(decl.name) and decl.name:match(filter) then
        tinsert(module.enums, { name=toTypeName(decl.name), fields=getFields(decl) })
    end
    if decl.tag == "function" and decl.storage_specifier == "extern" and decl.name:match(filter) then
        tinsert(module.fns, { name=toFunctionName(decl.name), extname=decl.name, inline=decl.inline, params=getParams(decl), ret=getFieldSpelling(nil, resolveType(decl.ret)).type })
    end 
end


print("module "..module.name..";")
print("")
print("define FunPtr = void; // Replace occurences with correct function pointers")
print("")

for _, mstruct in ipairs(module.structs) do
    print(struct(mstruct.name, table.unpack(mstruct.fields)))
    print()
end
for _, munions in ipairs(module.unions) do
    print(union(munions.name, table.unpack(munions.fields)))
    print()
end

for _, mfn in ipairs(module.fns) do
    print(fn(mfn.name, mfn.inline, mfn.extname, mfn.ret, table.unpack(mfn.params)))
end

for _, menum in ipairs(module.enums) do
    -- print(enum(menum.name, table.unpack(menum.fields)))

    local typeName = menum.name
    print("module "..module.name.."::"..menum.name:lower()..";")
    print("define "..typeName.." = ".."distinct int;") -- FIXME: this may or may not be int
    
    local out = {}
    for _, field in ipairs(menum.fields) do 
        tinsert(out, "const ")
        tinsert(out, typeName)
        tinsert(out, " ")
        tinsert(out, field.name)
        tinsert(out, " = ")
        tinsert(out, field.value)
        tinsert(out, ";\n")
    end
    print(table.concat(out))
    print()
end
