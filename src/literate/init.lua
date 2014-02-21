--[[#
# LuaLiterate

LuaLiterate is a literate programming module for LuaDocer. Is't highly inspired by [Locco](http://rgieseke.github.io/locco/),
but has some interesting improvements.

## Specific features

*   Block comments
*   Block comments folding
*   Function cross-references

### Block comments

Block comments are used to comment wider part of code than just one line or loop.
Comments are described by grammar and have following syntax:

    --^ `name` description
        <code>
    --v `name`

*Name* describes block in max. few words.
*Description* is optional. It can be as long as needed (but only on the same line) to explain more specificaly what the block does.

Code demaked by block comments has no lenght limitations and can contain even nested block comments.

### Block comments folding

Code folding, or in this case block comments folding, brings the option to fold not interesting parts of code.
In case of block comments, the block comment and whole its content is folded into one line, showing name of the block.
When running with cursor over the block name, the block description appears on the right.
Code is folded and unfolded by double-clicking on the desired block.

### Function cross-references

This is great feature. It is inspired by IDEs such as Eclipse. When running cursor over the function call, it show a docstring describing that function.
When clicking on the function call, the documentation of file containg the desired function opens and scrolls to the begining of the function.

## Dependencies

LuaLiterate directly depends on *luapretty* module. It also depends on abstract syntax tree (AST) which in this case needs to have same structure as the one created by the *luametrics*.


--]]

-------------------------------------------------------------------------------
-- Interface for literate module
-- @release 2013/03/18, Michal Juranyi
-------------------------------------------------------------------------------

--[[#
# The program:
--]]

--[[#
This module directly depends on *luapretty* module, which it uses for syntax highlighted code.
--]]

local highlighter = require "luapretty.highlighter"
local ast_helper = require "luapretty.ast_helper"
local util = require "literate.util"
local luadoc = require "luadocer.doclet.html"
require "markdown"

module("literate", package.seeall)

--[[#
*doc\_blocks* table contains split source file into documentation and code part.
The table has following structure:

*   `doc_blocks['doc'].str` - text of documentation
*   `doc_blocks['doc'].type` - type of documentation
*   `doc_blocks['code']` - code to which the documentation belongs
--]]
local doc_blocks = {}

--_ LuaDoc path to currently processed file.
filename = ""
--_ Associated array of function nodes from AST, where keys are function names.
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
    This function recursively process whole AST and splits it into LP documentation part and code part.
    Code part may also contain comments, such as API documentation or commented out code.
    --]]

    if #ast.data > 0 then
        --_ We check current node's children.
        for i,v in ipairs(ast.data) do
            --^ `filter comments` If child (node) is comment, we process it based on its type.

            if v.key == "COMMENT" and v.parsed.style == "literate" then
                --[[
                If we haven't found a docstring we just add a new row into doc_block table,
                so the comment that we have just found could be aligned with the code it belongs to.
                --]]
                if last_docstring ~= v.parsed.text then
                    table.insert(doc_blocks, { doc = "", code = {}})
                end
                --_ LP and LP - Markdown comments are added into current row's doc part.
                if v.parsed.type == "lp" or v.parsed.type == "markdown" then
                    doc_blocks[#doc_blocks].doc = { str = v.parsed.text, type = v.parsed.type }
                end

            elseif v.key == "COMMENT" and v.parsed.style == "luadoc" then
                if v.parsed.type == "descr" then
                    if v.parsed.text == "" and doc_blocks[#doc_blocks].doc.type ~= "api" then
                        table.insert(doc_blocks,
                            {
                                doc = { str = "", type = "api" },
                                code = {}
                            })
                    else
                        if doc_blocks[#doc_blocks].doc.type == "api" then
                            doc_blocks[#doc_blocks].doc.str = doc_blocks[#doc_blocks].doc.str .. v.parsed.text
                        end
                    end
                elseif v.parsed.type == "name" then
                    if doc_blocks[#doc_blocks].doc.type == "api" then
                            doc_blocks[#doc_blocks].doc.str = '<em>Function</em> <strong>'.. v.parsed.name ..'</strong><br/>' .. doc_blocks[#doc_blocks].doc.str
                    end
                elseif v.parsed.type == "param" then
                    if doc_blocks[#doc_blocks].doc.type == "api" then
                            doc_blocks[#doc_blocks].doc.str = doc_blocks[#doc_blocks].doc.str .. '<br/><em>Param </em><strong>' .. v.parsed.name .. '</strong>: ' .. v.parsed.text .. ''
                    end
                end

            --[[
            Block comments are parsed different way. There is emphasized block name before the description.
            It's inserted as a new row into doc_blocks table.
            --]]
            elseif v.key == "COMMENT" and v.parsed.style == "custom" then
                if v.parsed.type == "startblock" then
                    table.insert(doc_blocks,
                        {
                            doc =
                                {
                                    str = "<strong>"..v.parsed.block.."</strong> block<br/>"..v.parsed.text,
                                    type = v.parsed.type
                                },
                            code = {}
                        })
                elseif v.parsed.type == "endblock" then
                    table.insert(doc_blocks,
                        {
                            doc =
                                {
                                    str = "end of <strong>"..(v.parsed.block or "").."</strong> block",
                                    type = v.parsed.type
                                },
                            code = {}
                        })
                    --_ After the end of block, an extra line needs to be inserted in order to keep the output properly aligned.
                    table.insert(doc_blocks, { doc ={}, code = {} })
                end
            --v `filter comments`

            --[[
            If current node is not the AST's leaf, we check it for being a function call or definition. Then we recurse into this subtree.
            --]]
            elseif type(v.data) == "table" and #v.data > 0 then
                if doc_blocks[#doc_blocks].doc.type == "api" then table.insert(doc_blocks, { doc = {}, code = {} }) end
                --_ In case is's function definition with docstring, the new line is inserted. In the code part, a cross-reference anchor is inserted and the docstring is remembered.
                if (v['key'] == "GlobalFunction" or v['key'] == "LocalFunction") and v.docstring then
                    table.insert(doc_blocks, { doc = "", code = {}})
                    table.insert(doc_blocks[#doc_blocks].code, '<a name="'..v['name']..'Xref"></a>')
                    last_docstring = v.docstring
                    --_ If it's a function without docstring, only a cross-reference anchor has to be inserted.
                elseif v['key'] == "GlobalFunction" or v['key'] == "LocalFunction" then
                    table.insert(doc_blocks[#doc_blocks].code, '<a name="'..v['name']..'Xref"></a>')
                --_ When a function call is found, we remember that it is the last (most recent) found statement.
                elseif v['key'] == "FunctionCall" then
                    last_stat = "FunctionCall"
                end
                --_ When any statement is found, we forget about the previous one.
                if v['key'] == "Stat" then last_stat = nil end
                extractCodeNodes(v)
            else
                --_ Finally, if current node is a leaf and it's name of function being called, the name is wrapped into a cross-reference link.
                if v['key'] == "ID" and last_stat == "FunctionCall" and functions[v.str] then
                    table.insert(doc_blocks[#doc_blocks].code,'<a href="../'.. luadoc.file_link(functions[v.str].path,filename) ..'#'.. v['str'] ..'Xref" title="'.. (functions[v.str].docstring or "") ..'">')
                    table.insert(doc_blocks[#doc_blocks].code, v)
                    table.insert(doc_blocks[#doc_blocks].code, '</a>')
                    last_stat = nil
                --_ Otherwise, if it's any other leaf in AST, its text is just appended to current row's code part.
                else
                    table.insert(doc_blocks[#doc_blocks].code, v)
                end
            end
        end
    end
end

local block_comments_stack = {}
local block_comments_count = 0

---
-- Creates CSS class string for block comments,
-- deliberating blocks nesting
-- @name blockCommentsClass
local function blockCommentsClass()
    --[[
    Function prepares CSS class string for block comments, deliberating blocks nesting.
    --]]
    if #block_comments_stack == 0 then
        return nil
    end
    --^ `chaining class` This creates class string for HTML begining with "block_comment" and adds block# for each block comment level above current.
    local class = "block_comment"
    for _,v in ipairs(block_comments_stack) do
        class = class .. " block"..tostring(v)
    end
    --v `chaining class`
    return class
end

local function encapsulateNode(node)
    --[[
    Wraps node recursively into its ancestors in the same manner as in the AST.
    --]]

    --_ Duplicate current node, ignoring most of its attributes.
    local t = { key = node.key, text = node.text, data = {} }

    if node.varid then
        t.varid = node.varid
    end

    --_ The root of the AST returns self.
    if node.parent == nil then
        return t, t
    end

    --_ All children recurse into their parent and add self as their parent's child.
    local new, p = encapsulateNode(node.parent)
    p.data[1] = t

    --_ Function returns reference to the topmost node (root) and to current node.
    return new, t
end


---
-- Generates HTML documentation from supplied AST
-- @name ASTtoHTML
-- @param ast AST to generate HTML from
local function ASTtoHTML(ast)

    --[[
    Process table with split code and documentation and outputs final HTML code.
    --]]

    local html
    local class
    local fullwidth = true
    extractCodeNodes(ast)
    html = "<table>"
    for _,v in ipairs(doc_blocks) do
        --_ Special processing for start of block comments and Markdown formatted comments.
        if v.doc.type == "startblock" then
            block_comments_count = block_comments_count + 1
            table.insert(block_comments_stack, block_comments_count)
            html = html .. '<tr class="folder '..blockCommentsClass()..'"><td class="docs">~v~ hidden block ~v~</td><td class="code"></td></tr>'
        elseif v.doc.type == "markdown" then
            v.doc.str = markdown(v.doc.str)
        end

        util.trimCodeBlock(v.code)
        if #v.code == 0 and fullwidth then
            if v.doc.type == "api" then
                html = html .. '<tr class="api"><td class="docs" colspan="2">'
            else
                html = html .. '<tr><td class="docs" colspan="2">'
            end
            html = html .. (v.doc.str or "")
            html = html .. "</td></tr>"
        else
            fullwidth = false
            class = blockCommentsClass()
            --_ If class variable is not empty (we are inside of block comment), put it into table row's class attribute.
            if class then
                html = html .. '<tr class="'.. class ..'"><td class="docs">'
            elseif v.doc.type == "api" then
                html = html .. '<tr class="api"><td class="docs">'
            else
                html = html .. '<tr><td class="docs">'
            end
            html = html .. (v.doc.str or "")
            html = html .. '</td><td class="code">'
            html = html .. "<pre class=\"highlighted_code\">"

            for _,v in ipairs(v.code) do
                if type(v) == "table" then
                    -- v = encapsulateNode(v)
                    --[[
                    Use highlighter module to convert code node from metrics AST
                    to highlighter compatible node, highlight and print it out.
                    --]]
                    local tree = ast_helper.metrics_to_highlighter(v)
                    local text, tree = highlighter.highlight_text("",tree)
                    html = html .. highlighter.assemble_table(tree)
                else
                    html = html .. v
                end
            end
            html = html .. "</pre>"
            html = html .. "</td></tr>"
        end

        --_ At the end of block comment, pop value from stack, which is used for marking nested block comments.
        if v.doc.type == "endblock" then
            table.remove(block_comments_stack)
        end
    end
    html = html .. "</table>"

    return html
end

------------------------------------------------------------------------
-- Main function for LP documentation generation from AST
-- @name literate
-- @param ast AST to generate documentation from
function literate(ast)
    doc_blocks = {}
    --_ Reset doc_blocks table for each source file
    table.insert(doc_blocks, { doc = "", code = {} })
    return ASTtoHTML(ast), doc_blocks
end
