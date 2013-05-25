module("literate.util", package.seeall)

---
-- This function trims code block by removing newlines from the begin and the end of block.
-- @name trimCodeBlock
-- @param block code block from doc_blocks table
function trimCodeBlock(block)

    --[[
    This function trims code block by removing newlines from the begin and the end of block.
    --]]

    for i,v in ipairs(block) do
        if v.key == "NEWLINE" then
            table.remove(block,i)
        else
            break
        end
    end

    for i = #block, 1, -1 do
        if block[i].key == "SPACE" or block[i].key == "NEWLINE" then
            table.remove(block,i)
        else
            break
        end
    end
end

---
-- This function dumps AST created by luametrics module
-- @name dumpTree
-- @param ast AST to dump
-- @param depth internal depth indicator
function dumpTree(ast, depth)

	--[[
	This function dumps AST created by luametrics module.
	--]]

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
            if type(v) ~= "string" then
                print(indent..k)
            else
                print(indent..k.." = "..v)
            end
        else
            print(indent..k.." = ")
            if k == "data" or type(k)=="number" then
                dumpTree(v,depth+1)
            end
        end
    end
end