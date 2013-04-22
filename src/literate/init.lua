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
local ast_helper = require "luapretty.ast_helper"
local util = require "literate.util"
local luacomments = require "comments"
local luadoc = require "luadoc.doclet.html"
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
filename = ""
functions = {}

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

    if #ast.data > 0 then
        for i,v in ipairs(ast.data) do
            --^ `filter comments`
            if v.key == "COMMENT" and v.parsed.style == "literate" then
                if last_docstring ~= v.parsed.text then
                    table.insert(doc_blocks, { doc = "", code = {}})
                end
                if v.parsed.type == "lp" or v.parsed.type == "markdown" then
                    doc_blocks[#doc_blocks].doc = { str = v.parsed.text, type = v.parsed.type }
                end
            elseif v.key == "COMMENT" and v.parsed.style == "custom" then
                if v.parsed.type == "startblock" then
                    table.insert(doc_blocks, { doc = { str = "<strong>"..v.parsed.block.."</strong><br/>"..v.parsed.text, type = v.parsed.type }, code = {}})
                elseif v.parsed.type == "endblock" then
                    table.insert(doc_blocks, { doc = { str = "end of <strong>"..(v.parsed.block or "").."</strong> block", type = v.parsed.type }, code = {}})
                    table.insert(doc_blocks, { doc ={}, code = {} })
                end
            --v
            elseif type(v.data) == "table" and #v.data > 0 then
                if (v['key'] == "GlobalFunction" or v['key'] == "LocalFunction") and v.docstring then
                    table.insert(doc_blocks, { doc = "", code = {}})
                    table.insert(doc_blocks[#doc_blocks].code, '<a name="'..v['name']..'Xref"></a>')
                    last_docstring = v.docstring
                elseif v['key'] == "FunctionCall" then
                    last_stat = "FunctionCall"
                elseif v['key'] == "GlobalFunction" or v['key'] == "LocalFunction" then
                    table.insert(doc_blocks[#doc_blocks].code, '<a name="'..v['name']..'Xref"></a>')
                end
                if v['key'] == "Stat" then last_stat = nil end
                extractCodeNodes(v)
            else
                if v['key'] == "ID" and last_stat == "FunctionCall" and functions[v.str] then
                    table.insert(doc_blocks[#doc_blocks].code, '<a href="../'.. luadoc.file_link(functions[v.str].path,filename) ..'#'.. v['str'] ..'Xref" title="'.. (functions[v.str].docstring or "") ..'">')
                    table.insert(doc_blocks[#doc_blocks].code, v)
                    table.insert(doc_blocks[#doc_blocks].code, '</a>')
                    last_stat = nil
                else
                    table.insert(doc_blocks[#doc_blocks].code, v)
                end
            end
        end
    else

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

local function ASTtoHTML(ast)
    local html
    local class
    extractCodeNodes(ast)
    util.dumpTree()
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
        for _,v in ipairs(v.code) do
            if type(v) == "table" then
                --html = html .. lxsh.highlighters.lua(v.code, { formatter = lxsh.formatters.html, external = true })
                local tree = ast_helper.metrics_to_highlighter(v)
                local text, tree = highlighter.highlight_text("",tree)
                html = html .. highlighter.assemble_table(tree)
            else
                html = html .. v
            end
        end
        html = html .. "</pre>"
        html = html .. "</td></tr>"

        if v.doc.type == "endblock" then
            table.remove(block_comments_stack)
        end
    end
    html = html .. "</table>"

    return html
    --return replaceLinks(html)
end

------------------------------------------------------------------------
-- Main function for source code analysis text equal true
-- returns an AST with included metric values in each node
-- @name processText
-- @param code - string containing the source code to be analyzed
function literate(ast)
    doc_blocks = {}
    --_ Reset doc_blocks table for each source fiastle
    table.insert(doc_blocks, { doc = "", code = {} })
    return ASTtoHTML(ast)
end