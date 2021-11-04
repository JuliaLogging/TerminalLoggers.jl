using TerminalLoggers
using Test

using Logging:
    LogLevel, BelowMinLevel, Debug, Info, Warn, Error, AboveMaxLevel,
    shouldlog, handle_message, min_enabled_level, catch_exceptions,
    with_logger

using ProgressLogging: Progress
using UUIDs: UUID

include("TerminalLogger.jl")
include("StickyMessages.jl")
