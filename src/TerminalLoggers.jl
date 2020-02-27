module TerminalLoggers

using Logging:
    AbstractLogger,
    LogLevel, BelowMinLevel, Debug, Info, Warn, Error, AboveMaxLevel

import Logging:
    handle_message, shouldlog, min_enabled_level, catch_exceptions

using LeftChildRightSiblingTrees: Node, addchild, isroot, prunebranch!
using ProgressLogging: asprogress
using UUIDs: UUID

export TerminalLogger

const ProgressLevel = LogLevel(-1)

include("ProgressMeter/ProgressMeter.jl")
using .ProgressMeter:
    BarGlyphs

include("StickyMessages.jl")
include("ProgressBar.jl")
include("TerminalLogger.jl")

end # module
