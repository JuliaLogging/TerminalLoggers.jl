# This file is a part of Julia. License is MIT: https://julialang.org/license

import TerminalLoggers.default_metafmt

@noinline func1() = backtrace()

@testset "TerminalLogger" begin
    # First pass log limiting
    @test min_enabled_level(TerminalLogger(devnull, Debug)) == Debug
    @test min_enabled_level(TerminalLogger(devnull, Error)) == Error

    # Second pass log limiting
    logger = TerminalLogger(devnull)
    @test shouldlog(logger, Info, Base, :group, :asdf) === true
    handle_message(logger, Info, "msg", Base, :group, :asdf, "somefile", 1, maxlog=2)
    @test shouldlog(logger, Info, Base, :group, :asdf) === true
    handle_message(logger, Info, "msg", Base, :group, :asdf, "somefile", 1, maxlog=2)
    @test shouldlog(logger, Info, Base, :group, :asdf) === false

    @testset "Default metadata formatting" begin
        @test default_metafmt(Info,  Main, :g, :i, "a.jl", 1) ==
            (:cyan,      "Info:",    "")
        @test default_metafmt(Warn,  Main, :g, :i, "b.jl", 2) ==
            (:yellow,    "Warning:", "@ Main b.jl:2")
        @test default_metafmt(Error, Main, :g, :i, "", 0) ==
            (:light_red, "Error:",   "@ Main :0")
        # formatting of nothing
        @test default_metafmt(Warn,  nothing, :g, :i, "b.jl", 2) ==
            (:yellow,    "Warning:", "@ b.jl:2")
        @test default_metafmt(Warn,  Main, :g, :i, nothing, 2) ==
            (:yellow,    "Warning:", "@ Main")
        @test default_metafmt(Warn,  Main, :g, :i, "b.jl", nothing) ==
            (:yellow,    "Warning:", "@ Main b.jl")
        @test default_metafmt(Warn,  nothing, :g, :i, nothing, 2) ==
            (:yellow,    "Warning:", "")
        @test default_metafmt(Warn,  Main, :g, :i, "b.jl", 2:5) ==
            (:yellow,    "Warning:", "@ Main b.jl:2-5")
    end

    function dummy_metafmt(level, _module, group, id, file, line)
        :cyan,"PREFIX","SUFFIX"
    end

    # Log formatting
    function genmsgs(events; level=Info, _module=Main,
                     file="some/path.jl", line=101, color=false, width=75,
                     meta_formatter=dummy_metafmt, show_limited=true,
                     right_justify=0)
        buf = IOBuffer()
        io = IOContext(buf, :displaysize=>(30,width), :color=>color)
        logger = TerminalLogger(io, Debug,
                                meta_formatter=meta_formatter,
                                show_limited=show_limited,
                                right_justify=right_justify)
        prev_have_color = Base.have_color
        return map(events) do (message, kws)
            handle_message(logger, level, message, _module, :a_group, :an_id,
                           file, line; kws...)
            String(take!(buf))
        end
    end
    function genmsg(message; kwargs...)
        kws = Dict(kwargs)
        logconfig = Dict(
            k => pop!(kws, k)
            for k in [
                :level,
                :_module,
                :file,
                :line,
                :color,
                :width,
                :meta_formatter,
                :show_limited,
                :right_justify,
            ] if haskey(kws, k)
        )
        return genmsgs([(message, kws)]; logconfig...)[1]
    end

    # Basic tests for the default setup
    @test genmsg("msg", level=Info, meta_formatter=default_metafmt) ==
    """
    [ Info: msg
    """
    @test genmsg("line1\nline2", level=Warn, _module=Base,
                 file="other.jl", line=42, meta_formatter=default_metafmt) ==
    """
    ┌ Warning: line1
    │ line2
    └ @ Base other.jl:42
    """
    # Full metadata formatting
    @test genmsg("msg", level=Debug,
                 meta_formatter=(level, _module, group, id, file, line)->
                                (:white,"Foo!", "$level $_module $group $id $file $line")) ==
    """
    ┌ Foo! msg
    └ Debug Main a_group an_id some/path.jl 101
    """

    @testset "Prefix and suffix layout" begin
        @test genmsg("") ==
        replace("""
        ┌ PREFIX EOL
        └ SUFFIX
        """, "EOL"=>"")
        @test genmsg("msg") ==
        """
        ┌ PREFIX msg
        └ SUFFIX
        """
        # Behavior with empty prefix / suffix
        @test genmsg("msg", meta_formatter=(args...)->(:white, "PREFIX", "")) ==
        """
        [ PREFIX msg
        """
        @test genmsg("msg", meta_formatter=(args...)->(:white, "", "SUFFIX")) ==
        """
        ┌ msg
        └ SUFFIX
        """
    end

    @testset "Metadata suffix, right justification" begin
        @test genmsg("xxx", width=20, right_justify=200) ==
        """
        [ PREFIX xxx  SUFFIX
        """
        @test genmsg("xxx\nxxx", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxx
        └ xxx         SUFFIX
        """
        # When adding the suffix would overflow the display width, add it on
        # the next line:
        @test genmsg("xxxx", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxxx
        └             SUFFIX
        """
        # Same for multiline messages
        @test genmsg("""xxx
                        xxxxxxxxxx""", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxx
        └ xxxxxxxxxx  SUFFIX
        """
        @test genmsg("""xxx
                        xxxxxxxxxxx""", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxx
        │ xxxxxxxxxxx
        └             SUFFIX
        """
        # min(right_justify,width) is used
        @test genmsg("xxx", width=200, right_justify=20) ==
        """
        [ PREFIX xxx  SUFFIX
        """
        @test genmsg("xxxx", width=200, right_justify=20) ==
        """
        ┌ PREFIX xxxx
        └             SUFFIX
        """
    end

    # Keywords
    @test genmsg("msg", a=1, b="asdf") ==
    """
    ┌ PREFIX msg
    │   a = 1
    │   b = "asdf"
    └ SUFFIX
    """
    # Exceptions shown with showerror
    @test genmsg("msg", exception=DivideError()) ==
    """
    ┌ PREFIX msg
    │   exception = DivideError: integer division error
    └ SUFFIX
    """

    # Attaching backtraces
    bt = func1()
    @test startswith(genmsg("msg", exception=(DivideError(),bt)),
    """
    ┌ PREFIX msg
    │   exception =
    │    DivideError: integer division error
    │    Stacktrace:
    │     [1] func1() at""")


    @testset "Limiting large data structures" begin
        @test genmsg("msg", a=fill(1.00001, 100,100), b=fill(2.00002, 10,10)) ==
        replace("""
        ┌ PREFIX msg
        │   a =
        │    100×100 Array{Float64,2}:
        │     1.00001  1.00001  1.00001  1.00001  …  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     ⋮                                   ⋱                           EOL
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │   b =
        │    10×10 Array{Float64,2}:
        │     2.00002  2.00002  2.00002  2.00002  …  2.00002  2.00002  2.00002
        │     2.00002  2.00002  2.00002  2.00002     2.00002  2.00002  2.00002
        │     2.00002  2.00002  2.00002  2.00002     2.00002  2.00002  2.00002
        │     ⋮                                   ⋱                           EOL
        │     2.00002  2.00002  2.00002  2.00002     2.00002  2.00002  2.00002
        │     2.00002  2.00002  2.00002  2.00002     2.00002  2.00002  2.00002
        └ SUFFIX
        """,
        # EOL hack to work around git whitespace errors
        # VERSION dependence due to JuliaLang/julia#33339
        (VERSION < v"1.4-" ? "EOL" : "       EOL")=>""
        )
        # Limiting the amount which is printed
        @test genmsg("msg", a=fill(1.00001, 10,10), show_limited=false) ==
        """
        ┌ PREFIX msg
        │   a =
        │    10×10 Array{Float64,2}:
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001  1.00001
        └ SUFFIX
        """
    end

    # Basic colorization test.
    @test genmsg("line1\nline2", color=true) ==
    """
    \e[36m\e[1m┌ \e[22m\e[39m\e[36m\e[1mPREFIX \e[22m\e[39mline1
    \e[36m\e[1m│ \e[22m\e[39mline2
    \e[36m\e[1m└ \e[22m\e[39m\e[90mSUFFIX\e[39m
    """

    # Using infix operator so that `@test` prints lhs and rhs when failed:
    ⊏(s, re) = match(re, s) !== nothing

    @test genmsg("", progress=0.1, width=60) ⊏
    r"Progress:  10%\|██.                  \|  ETA: 0:00:[0-9][0-9]"
    @test genmsg("", progress=NaN, width=60) ⊏
    r"Progress:   0%|.                    |  ETA: N/A"
    @test genmsg("", progress=1.0, width=60) == ""
    @test genmsg("", progress="done", width=60) == ""
    @test genmsgs([("", (progress = 0.1,)), ("", (progress = 1.0,))], width = 60)[end] ⊏
    r"Progress: 100%|█████████████████████| Time: 0:00:[0-9][0-9]"
    @test genmsgs([("", (progress = 0.1,)), ("", (progress = "done",))], width = 60)[end] ⊏
    r"Progress: 100%|█████████████████████| Time: 0:00:[0-9][0-9]"
end
