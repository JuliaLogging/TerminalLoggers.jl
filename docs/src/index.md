# TerminalLoggers.jl

TerminalLoggers provides a logger type [`TerminalLogger`](@ref) which can
format your log messages in a richer way than the default `ConsoleLogger` which
comes with the julia standard `Logging` library.


## Installation and setup

```julia-repl
pkg> add https://github.com/c42f/TerminalLoggers.jl
```

To use `TerminalLogger` in all your REPL sessions by default, you may add a
snippet such as the following to your startup file (in `.julia/config/startup.jl`)

```julia
atreplinit() do repl
    try
        @eval begin
            import Logging: global_logger
            import TerminalLoggers: TerminalLogger
            global_logger(TerminalLogger(stderr))
        end
    catch
    end
end
```


## Progress bars

`TerminalLogger` displays progress logging as a set of progress bars which are
cleanly separated from the rest of the program output at the bottom of the
terminal. Try an example like the following

```julia
global_logger(TerminalLogger(stderr, right_justify=120))
for i=1:100
    @info "Some progress" progress=i/100
    if i == 50
        @warn "Middle of computation" i
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


## API Reference

```@docs
TerminalLogger
```

