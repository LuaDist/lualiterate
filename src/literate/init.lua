-------------------------------------------------------------------------------
-- Interface for literate module
-- @release 2013/03/18, Michal Juranyi
-------------------------------------------------------------------------------

--local io, table, ipairs, pairs, type, print, pcall = io, table, ipairs, pairs, type, print, pcall

local string = require "string"
local re = require "re"
local scanner = require "leg.scanner"
local parser = require "leg.parser"
local highlighter = require "luapretty.highlighter"
local util = require "literate.util"
local lxsh = require "lxsh"
local luacomments = require "comments"
require "markdown"

module("literate", package.seeall)

--[[# 
*doc\_blocks* table contains split source file into documentation and code part.
The table has following structure:

*   doc\_blocks['doc'].str
*   doc\_blocks['doc'].type
*   doc\_blocks['code']
--]]
local doc_blocks = {}
local functions = {}

local last_docstring
local last_stat

------------------------------------------------------------------------
-- This function prepares table with separated documentation and code parts,
-- that will be used to generate HTML output
-- @name extractCodeNodes
-- @param ast root node of AST
local function extractCodeNodes(ast)
    --[[
    This function splits AST into LP documentation part and code part.
    Code part may also contain comments, such as API documentation or commented out code.
    --]]
    for i,v in ipairs(ast) do
        --^ `filter comments`
        if v.key == "COMMENT" and v.parsed.style == "literate" then
            if last_docstring ~= v.parsed.text then
                table.insert(doc_blocks, { doc = "", code = ""})
            end
            if v.parsed.type == "lp" or v.parsed.type == "markdown" then
                doc_blocks[#doc_blocks].doc = { str = v.parsed.text, type = v.parsed.type }
            end
        elseif v.key == "COMMENT" and v.parsed.style == "custom" then
            if v.parsed.type == "startblock" then
                table.insert(doc_blocks, { doc = { str = "<strong>"..v.parsed.block.."</strong><br/>"..v.parsed.text, type = v.parsed.type }, code = ""})
            elseif v.parsed.type == "endblock" then
                table.insert(doc_blocks, { doc = { str = "end of <strong>"..(v.parsed.block or "").."</strong> block", type = v.parsed.type }, code = ""})
                table.insert(doc_blocks, { doc ={}, code = "" })
            end
        --v
        elseif type(v) == "table" and #v > 0 then
            if (v['key'] == "GlobalFunction" or v['key'] == "LocalFunction") and v.docstring then
                table.insert(doc_blocks, { doc = "", code = ""})
                last_stat = "FunctionDef"
            elseif v['key'] == "FunctionCall" then
                last_stat = "FunctionCall"
            elseif v['key'] == "GlobalFunction" or v['key'] == "LocalFunction" then
                last_stat = "FunctionDef"
            end
            extractCodeNodes(v)
        else
            if v['key'] == "ID" and last_stat == "FunctionCall" then
                doc_blocks[#doc_blocks].code = doc_blocks[#doc_blocks].code .. "--[[|link "..v['str'].."|]]"..v['str'].."--[[||]]"
                last_stat = nil
            elseif v['key'] == "ID" and last_stat == "FunctionDef" then
                doc_blocks[#doc_blocks].code = doc_blocks[#doc_blocks].code .. "--[[|anchor "..v['str'].."|]]"..v['str']
                last_stat = nil
            else
                doc_blocks[#doc_blocks].code = doc_blocks[#doc_blocks].code .. v['str']
            end
        end
    end
end

local block_comments_stack = {}
local block_comments_count = 0

local function block_comments_class()
    if #block_comments_stack == 0 then
        return nil
    end
    --^ `chaining class` This creates class string for HTML begining with "block_comment" and adds block# for each block comment level above current
    local class = "block_comment"
    for _,v in ipairs(block_comments_stack) do
        class = class .. " block"..tostring(v)
    end
    --v `chaining class`
    return class
end

local function replaceLinks(html)
    local html = html
    for k,v in pairs(functions) do
        html = html:gsub('<span class="comment">%-%-%[%[%|link '..k..'%|%]%]</span>', '<a href="#'.. k ..'" title="'..(v.node.docstring or "")..'">')
        html = html:gsub('<span class="comment">%-%-%[%[%|anchor '..k..'%|%]%]</span>', '<a name="'.. k ..'"></a>')
    end
    html = html:gsub('<span class="comment">%-%-%[%[%|%|%]%]</span>', '</a>')
    html = html:gsub('<span class="comment">%-%-%[%[%|link [a-z]*%|%]%]</span>', '')
    return html
end

local function ASTtoHTML(ast)
    local html
    local class
    extractCodeNodes(ast)
    --dumpTree(ast)
    --dumpTree(doc_blocks)
    html = "<table>"
    for _,v in ipairs(doc_blocks) do
        if v.doc.type == "startblock" then
            block_comments_count = block_comments_count + 1
            table.insert(block_comments_stack, block_comments_count)
            html = html .. '<tr class="folder '..block_comments_class()..'"><td class="docs">~v~ hidden block ~v~</td><td class="code"></td></tr>'
        elseif v.doc.type == "markdown" then
            v.doc.str = markdown(v.doc.str)
        end

        class = block_comments_class()
        if class then
            html = html .. '<tr class="'.. class ..'"><td class="docs">'
        else
            html = html .. '<tr><td class="docs">'
        end
        html = html .. (v.doc.str or "")
        html = html .. '</td><td class="code">'
        html = html .. "<pre class=\"highlighted_code\">"
        html = html .. lxsh.highlighters.lua(v.code, { formatter = lxsh.formatters.html, external = true })
        html = html .. "</pre>"
        html = html .. "</td></tr>"

        if v.doc.type == "endblock" then
            table.remove(block_comments_stack)
        end
    end
    html = html .. "</table>"
    return replaceLinks(html)
end

local search_docstring = false
local inline = ""

local search_funcname = false
local func_node
------------------------------------------------------------------------
-- Function looking for comments and function definitions
-- @name findCommentsAndFunctions
-- @param ast - AST to extend
local function findFunctions(ast)

    for i,v in ipairs(ast) do
        if v.key == "GlobalFunction" or v.key == "LocalFunction" then
            search_funcname = true
            func_node = v
        elseif v.key == "Name" and search_funcname == true then
            functions[v.str] = { node = func_node }
            search_funcname = false
        end

        if #v > 0 then
            findFunctions(v)
        end
    end
end

------------------------------------------------------------------------
-- Main function for source code analysis text equal true
-- returns an AST with included metric values in each node
-- @name processText
-- @param code - string containing the source code to be analyzed
function literate(ast)
    doc_blocks = {}
    findFunctions(ast)
    --_ Reset doc_blocks table for each source file
    table.insert(doc_blocks, { doc = "", code = "" })
    return ASTtoHTML(ast)
end

function dumpTree(ast, depth)
    --print("Node size: "..#ast)
    if ast == nil then return nil end
	if depth==nil then
            depth = 0
        end
        
        local indent = ""
        for i=1,depth do
            indent = indent .. "--"
        end
        for k,v in pairs(ast) do
            if type(v)~="table" then
                print(indent..k.." = "..v)
            else
                print(indent..k.." = ")
                if k ~= "comment" then
                    dumpTree(v,depth+1)
                end
            end
        end
end
