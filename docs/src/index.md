# TerminalLoggers.jl

TerminalLoggers provides a logger type [`TerminalLogger`](@ref) which can
format your log messages in a richer way than the default `ConsoleLogger` which
comes with the julia standard `Logging` library.


## Installation and setup

```julia-repl
pkg> add TerminalLoggers
```

To use `TerminalLogger` in all your REPL sessions by default, you may add a
snippet such as the following to your startup file (in `.julia/config/startup.jl`)

```julia
atreplinit() do repl
    try
        @eval begin
            using Logging: global_logger
            using TerminalLoggers: TerminalLogger
            global_logger(TerminalLogger())
        end
    catch
    end
end
```

## Markdown

`TerminalLogger` interprets all `AbstractString` log messages as markdown so
you can use markdown formatting to display readable formatted messages. For
example,

```
@info """
    # A heading

    About to do the following

    * A list
    * Of actions
    * To take
    """
```

## Progress bars

`TerminalLogger` displays progress logging as a set of progress bars which are
cleanly separated from the rest of the program output at the bottom of the
terminal.

For robust progress logging, `TerminalLoggers` recognizes the `Progress` type
from the [`ProgressLogging` package](https://junolab.org/ProgressLogging.jl/stable/).
For easy to use progress reporting you can therefore use the `@progress` macro:

```julia
using Logging: global_logger
global_logger(TerminalLogger(right_justify=120))
using ProgressLogging

@progress for i=1:100
    if i == 50
        @info "Middle of computation" i
    elseif i == 70
        println("Normal output does not interfere with progress bars")
    end
    sleep(0.01)
end
@info "Done"
```

!!! note
    Rendering progress bars separately doesn't yet work on windows due to
    limitations of the windows console and its interaction with libuv.
    We expect this will eventually be solved with some combination of libuv
    updates and the new windows terminal.

You can also use the older progress logging API with the `progress=fraction`
key value pair. This is simpler but has some downsides such as not interacting
correctly with exceptions.

## API Reference

```@docs
TerminalLogger
```
