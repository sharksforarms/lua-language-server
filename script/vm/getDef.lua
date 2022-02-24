---@class vm
local vm        = require 'vm.vm'
local util      = require 'utility'
local compiler  = require 'vm.node.compiler'
local guide     = require 'parser.guide'
local localID   = require 'vm.local-id'
local globalMgr = require 'vm.global-manager'

local simpleMap

local function searchGetLocal(source, node, pushResult)
    local key = guide.getKeyName(source)
    for _, ref in ipairs(node.node.ref) do
        if  ref.type == 'getlocal'
        and guide.isSet(ref.next)
        and guide.getKeyName(ref.next) == key then
            pushResult(ref.next)
        end
    end
end

simpleMap = util.switch()
    : case 'local'
    : call(function (source, pushResult)
        pushResult(source)
        if source.ref then
            for _, ref in ipairs(source.ref) do
                if ref.type == 'setlocal' then
                    pushResult(ref)
                end
            end
        end

        if source.dummy then
            for _, res in ipairs(vm.getDefs(source.method.node)) do
                pushResult(res)
            end
        end
    end)
    : case 'getlocal'
    : case 'setlocal'
    : call(function (source, pushResult)
        simpleMap['local'](source.node, pushResult)
    end)
    : case 'field'
    : call(function (source, pushResult)
        local parent = source.parent
        simpleMap[parent.type](parent, pushResult)
    end)
    : case 'setfield'
    : case 'getfield'
    : call(function (source, pushResult)
        local node = source.node
        if node.type == 'getlocal' then
            searchGetLocal(source, node, pushResult)
            return
        end
    end)
    : case 'getindex'
    : case 'setindex'
    : call(function (source, pushResult)
        local node = source.node
        if node.type == 'getlocal' then
            searchGetLocal(source, node, pushResult)
        end
    end)
    : getMap()

local searchFieldMap = util.switch()
    : case 'table'
    : call(function (node, key, pushResult)
        for _, field in ipairs(node) do
            if field.type == 'tablefield'
            or field.type == 'tableindex' then
                if guide.getKeyName(field) == key then
                    pushResult(field)
                end
            end
        end
    end)
    : case 'global'
    : call(function (node, key, pushResult)
        local newGlobal = globalMgr.getGlobal(node.name, key)
        if not newGlobal then
            return
        end
        for _, set in ipairs(newGlobal:getSets()) do
            pushResult(set)
        end
    end)
    : getMap()

local nodeMap;nodeMap = util.switch()
    : case 'field'
    : call(function (source, pushResult)
        local parent = source.parent
        nodeMap[parent.type](parent, pushResult)
    end)
    : case 'getfield'
    : case 'setfield'
    : case 'getmethod'
    : case 'setmethod'
    : case 'getindex'
    : case 'setindex'
    : call(function (source, pushResult)
        local node = compiler.compileNode(source.node)
        if not node then
            return
        end
        if searchFieldMap[node.type] then
            searchFieldMap[node.type](node, guide.getKeyName(source), pushResult)
        end
    end)
    : getMap()

    ---@param source  parser.object
    ---@param pushResult fun(src: parser.object)
local function searchBySimple(source, pushResult)
    local simple = simpleMap[source.type]
    if simple then
        simple(source, pushResult)
    end
end

---@param source  parser.object
---@param pushResult fun(src: parser.object)
local function searchByGlobal(source, pushResult)
    local global = globalMgr.getNode(source)
    if not global then
        return
    end
    for _, src in ipairs(global:getSets()) do
        pushResult(src)
    end
end

---@param source  parser.object
---@param pushResult fun(src: parser.object)
local function searchByID(source, pushResult)
    local idSources = localID.getSources(source)
    if not idSources then
        return
    end
    for _, src in ipairs(idSources) do
        if guide.isSet(src) then
            pushResult(src)
        end
    end
end

---@param source  parser.object
---@param pushResult fun(src: parser.object)
local function searchByNode(source, pushResult)
    local node = nodeMap[source.type]
    if node then
        node(source, pushResult)
    end
end

---@param source parser.object
---@return       parser.object[]
function vm.getDefs(source)
    local results = {}
    local mark    = {}

    local function pushResult(src)
        if not mark[src] then
            mark[src] = true
            results[#results+1] = src
        end
    end

    searchBySimple(source, pushResult)
    searchByGlobal(source, pushResult)
    searchByID(source, pushResult)
    searchByNode(source, pushResult)

    return results
end

---@param source parser.object
---@return       parser.object[]
function vm.getAllDefs(source)
    return vm.getDefs(source)
end