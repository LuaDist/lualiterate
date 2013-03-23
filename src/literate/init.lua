-------------------------------------------------------------------------------
-- Interface for literate module
-- @release 2013/03/18, Michal Juranyi
-------------------------------------------------------------------------------

local io, table, ipairs, pairs, type, print = io, table, ipairs, pairs, type, print 

local string = require "string"
local highlighter = require "luapretty.highlighter"

module ("literate")

local comment_blocks = {}
local code_tree = { key = 1 }

local function containsComment(subtree)
    local res
    for _,v in ipairs(subtree) do
        if v['key'] == "COMMENT_BLOCK" or v['key'] == "COMMENT" then
            return true
        elseif #v > 0 then
            res = containsComment(v)
            if res == true then
                return true
            end
        end
    end
    return false
end

local comment_block_counter = 0

local function extractCodeNodes(ast)
    for _,v in ipairs(ast) do
        if v['key'] == "COMMENT_BLOCK" then
            comment_block_counter = comment_block_counter + 1
        --elseif v['css_extra'] ~= nil or #v == 0 then
        elseif containsComment(v) == false then
            print(comment_block_counter)
            if type(comment_blocks[comment_block_counter].code) ~= "table" then
                comment_blocks[comment_block_counter].code = { key = 1 }
            end
            table.insert(comment_blocks[comment_block_counter].code,v)
        elseif type(v) == "table" then
            extractCodeNodes(v)
        end
    end
end

local function ASTtoHTML(ast)
    local html
    extractCodeNodes(ast)
    dumpTree(comment_blocks)
    html = "<table>"
    for _,v in ipairs(comment_blocks) do
        html = html .. "<tr><td>"
        html = html .. v['str']
        html = html .. "</td><td>"
        html = html .. "<pre class=\"highlighted_code\">"
        html = html .. highlighter.assemble_table(v.code) 
        html = html .. "</pre>"
        html = html .. "</td></tr>"
    end
    html = html .. "</table>"
    return html
end

------------------------------------------------------------------------
-- Function that decide whether subtree begining with current node
-- is comment block
-- @name isCommentBranch
-- @param subtree - root node of tested subtree
-- returns true if subtree contains only COMMENT and SPACE leaves
local function isCommentBranch(subtree)
    if #subtree == 0 then
        if subtree.key == "COMMENT" then 
            return true
        elseif subtree.key == "SPACE" then
            return nil
        else
            return false
        end
    else
        local status = nil --testing endline comment
        local res

        for _,v in ipairs(subtree) do
            if type(v) == "table" then
                res = isCommentBranch(v)
                if type(res) == "boolean" and res == false then
                    return false
                elseif type(res) == "nil" then
                    if type(status) == nil then
                        status = nil
                    end
                elseif type(res) == "boolean" and res == true then
                    status = true
                end
            end
        end
        return status
    end
end

local function findLastComment(subtree)
    for i=#subtree,1,-1 do
        if subtree[i].key == "COMMENT" then
            return i
        end
    end
end

local last_stat = nil

------------------------------------------------------------------------
-- Function extending current AST with LP-related information
-- @name extendTree
-- @param ast - AST to extend
local function extendTree(ast)
    local res

    for i,v in ipairs(ast) do
        --^ Test each found IGNORED node for contents of COMMENT nodes.
        -- Other non-leaf nodes will be tested for being Stat nodes,
        -- in which case they might be related to preceding COMMENT_BLOCK.
        -- For all other non-IGNORED nodes, algorithm will recurse into them.
        if v.key == "IGNORED" then
            res = isCommentBranch(v)
            --^ If IGNORED node contains COMMENT nodes, move whole IGNORED branch
            -- into new COMMENT_BLOCK node, which takes the original IGNORED node's place
            if res then
                local node = {}
                node['key'] = "COMMENT_BLOCK"
                node['str'] = ""
                for ii,vv in ipairs(v) do
                    if node[1] == nil then
                        if vv['key'] == "COMMENT" then
                            table.insert(node, vv)
                            v[ii] = nil
                        end
                    else
                        table.insert(node, vv)
                        v[ii] = nil
                    end
                end
                table.insert(v,node)
                for i=findLastComment(node)+1,#node do
                    table.insert(v,node[i])
                    node[i] = nil
                end
                for _,v in ipairs(node) do
                    node['str'] = node['str'] .. v['str']
                end
                table.insert(comment_blocks, node)
            end
            --v
        elseif type(v) == "table" then
            if v.key == "Stat" then
                if #comment_blocks > 0 and comment_blocks[#comment_blocks].doc_rel == nil then
                    v.doc_rel = #comment_blocks
                    comment_blocks[#comment_blocks].doc_rel = #comment_blocks
                else
                    last_stat = v
                end
            end
            extendTree(v)
        end
        --v
    end
end

------------------------------------------------------------------------
-- Main function for source code analysis text equal true
-- returns an AST with included metric values in each node
-- @name processText
-- @param code - string containing the source code to be analyzed
function literate(ast)
    extendTree(ast)
    return ASTtoHTML(ast)
end

function dumpTree(ast, depth)
        --print("Node size: "..#ast)
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
                dumpTree(v,depth+1)
            end
        end
end
