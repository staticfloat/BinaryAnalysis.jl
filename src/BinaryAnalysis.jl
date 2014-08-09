module BinaryAnalysis

using MachO

import Base.show
export get_dltree

abstract node
abstract leaf <: node
type branch <: node
    path::String
    children::Array{node,1}
end

type good_leaf <: leaf
    path::String
end

type bad_leaf <: leaf
    path::String
    error::String
end

nodemap = Dict{String,node}()

function get_dltree(path, rpaths=String[])
    # Return cached results if we've got them
    if haskey(nodemap, path)
        return nodemap[path]
    end

    if !isfile(path)
        return bad_leaf(path, "File not found")
    end

    lcs = nothing
    h = readmeta(path)
    if isa(h, MachO.FatMachOHandle)
        lcs = [collect(LoadCmds(h[1])), collect(LoadCmds(h[2]))]
    else
        lcs = collect(LoadCmds(h))
    end

    # Get rpaths from the binary, if they exist 
    new_rpath_cmds = filter(x -> isa(x, MachO.LoadCmd{MachO.rpath_command}), lcs)
    new_rpaths = [x.cmd.path for x in new_rpath_cmds]

    # Canonicalize the new_rpaths and add them to rpaths
    new_rpaths = [abspath(replace(x, "@executable_path", dirname(path))) for x in new_rpaths]
    prepend!(new_rpaths, rpaths)

    # Get only LOAD_DYLIB lc's
    dylib_cmds = filter(x -> isa(x, MachO.LoadCmd{MachO.dylib_command}) && x.cmd_id == MachO.LC_LOAD_DYLIB, lcs)
    dylibs = [x.cmd.name for x in dylib_cmds]
    
    # For any dylib paths that might have @rpath in them, search through rpaths for them
    dylibs = map(dylibs) do search_path
        if contains(search_path, "@rpath")
            for rpath in new_rpaths
                poss_dylib_path = abspath(replace(search_path, "@rpath", rpath))

                # See if we can descend down the tree this way
                poss_dylib = get_dltree(poss_dylib_path, new_rpaths)
                if isa(poss_dylib, good_leaf) || isa(poss_dylib, branch)
                    return poss_dylib
                end
            end

            # If none of our rpaths worked out, complain
            return bad_leaf(search_path, "File not found")
        else
            return get_dltree(search_path)
        end
    end

    # dylibs is an array of nodes
    ret = good_leaf(path)
    if length(dylibs) > 0
        ret = branch(path, dylibs)
    end

    nodemap[path] = ret
    return ret
end

# Convenience function for showing a 
function show(io::IO, n::node, tablevel=0)
    if tablevel >= 2
        print(io, "| "^(tablevel - 1))
    end
    if tablevel >= 1
        print(io, "+-")
    end

    if isa(n,branch)
        println(io, n.path, ":")
        for c in n.children
            show(io, c, tablevel + 1 )
        end
    else
        if isa(n,good_leaf)
            println(io, n.path)
        else
            println(io, n.path, ": ", n.error)
        end
    end
end


end #module

