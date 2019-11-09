module TerminalLoggers

using Logging:
    AbstractLogger,
    LogLevel, BelowMinLevel, Debug, Info, Warn, Error, AboveMaxLevel

import Logging:
    handle_message, shouldlog, min_enabled_level, catch_exceptions

using ProgressMeter:
    Progress, update!

export TerminalLogger

const ProgressLevel = LogLevel(-1)

include("StickyMessages.jl")
include("TerminalLogger.jl")

end # module
