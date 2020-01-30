using Documenter, TerminalLoggers

makedocs(;
    modules=[TerminalLoggers],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/c42f/TerminalLoggers.jl/blob/{commit}{path}#L{line}",
    sitename="TerminalLoggers.jl",
    authors="Chris Foster <chris42f@gmail.com>"
)

deploydocs(;
    repo="github.com/c42f/TerminalLoggers.jl",
    push_preview=true
)
