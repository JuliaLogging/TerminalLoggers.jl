using TerminalLoggers
using Test

using Logging:
    LogLevel, BelowMinLevel, Debug, Info, Warn, Error, AboveMaxLevel,
    shouldlog, handle_message, min_enabled_level, catch_exceptions

include("TerminalLogger.jl")
include("StickyMessages.jl")
