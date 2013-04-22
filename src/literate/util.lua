module("literate.util", package.seeall)

local function test()
    print("UTILS TEST")
end

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
                elseif k == "key" or k == "str" then
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