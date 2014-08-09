using BinaryAnalysis
using Base.Test


root = joinpath(JULIA_HOME,"julia")
dylibs = get_dltree(root)
@show dylibs