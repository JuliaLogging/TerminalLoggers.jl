module TerminalLoggers

using Logging:
    AbstractLogger,
    LogLevel, BelowMinLevel, Debug, Info, Warn, Error, AboveMaxLevel

import Logging:
    handle_message, shouldlog, min_enabled_level, catch_exceptions

export ConsoleLogger

include("StickyMessages.jl")
include("ConsoleLogger.jl")

end # module
