using Documenter, TerminalLoggers

makedocs(;
    modules=[TerminalLoggers],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    checkdocs=:exports,
    sitename="TerminalLoggers.jl",
    authors="Chris Foster <chris42f@gmail.com>"
)

deploydocs(;
    repo="github.com/JuliaLogging/TerminalLoggers.jl",
    push_preview=true
)
