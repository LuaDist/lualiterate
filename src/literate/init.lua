-------------------------------------------------------------------------------
-- Interface for literate module
-- @release 2013/03/18, Michal Juranyi
-------------------------------------------------------------------------------

local io, table, pairs, type, print = io, table, pairs, type, print 

module ("literate")

-- needed to set higher because of back-tracking patterns

------------------------------------------------------------------------
-- Main function for source code analysis
-- returns an AST with included metric values in each node
-- @name processText
-- @param code - string containing the source code to be analyzed
function dumpTree(ast, depth)
        --print("Node size: "..#ast)
	if depth==nil then
            depth = 0
        end
        
        local indent = ""
        for i=1,depth do
            indent = indent .. "--"
        end

        if #ast==0 then
            io.stdout:write(ast.str)
        end
        
        for k,v in pairs(ast) do
            if type(v)~="table" then
                --print(indent..k.." = "..v)
            else
                --print(indent..k.." = ")
                dumpTree(v,depth+1)
            end
        end
end
