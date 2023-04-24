using TerminalLoggers: default_metafmt, format_message

using ProgressLogging

@noinline func1() = backtrace()

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
        kws = Dict(pairs(kws))
        id = pop!(kws, :_id, :an_id)
        # Avoid markdown formatting while testing layouting. Don't wrap
        # progress messages though; ProgressLogging.asprogress() doesn't
        # like that.
        is_progress = message isa Progress || haskey(kws, :progress)
        handle_message(logger, level, message, _module, :a_group, id,
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

    # Basic tests for the default setup
    @test genmsg("msg", level=Info, meta_formatter=default_metafmt) ==
    """
    [ Info: msg
    """
    @test genmsg("msg", level=Warn, _module=Base,
                 file="other.jl", line=42, meta_formatter=default_metafmt) ==
    """
    ┌ Warning: msg
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
        @test genmsg("xxxxxxxx xxxxxxxx", width=20, right_justify=200) ==
        """
        ┌ PREFIX xxxxxxxx
        └ xxxxxxxx    SUFFIX
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
    │    Stacktrace:""")
    @test occursin("[1] func1", genmsg("msg", exception=(DivideError(),bt)))

    # Exception stacks
    if VERSION >= v"1.2"
        excstack = try
            error("Root cause")
        catch
            try
                error("An exception")
            catch
                if VERSION >= v"1.7.0-DEV.1106"
                    current_exceptions()
                else
                    Base.catch_stack()
                end
            end
        end
        @test occursin(r"An exception.*Stacktrace.*caused by.*Root cause.*Stacktrace"s,
                       genmsg("msg", exception=excstack))
    end

    @testset "Limiting large data structures" begin
        a = fill(1.00001, 10,10)
        b = fill(2.00002, 10,10)
        @test genmsg("msg", a=a, b=b) ==
        replace("""
        ┌ PREFIX msg
        │   a =
        │    $(summary(a)):
        │     1.00001  1.00001  1.00001  1.00001  …  1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     ⋮                                   ⋱                           EOL
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │     1.00001  1.00001  1.00001  1.00001     1.00001  1.00001  1.00001
        │   b =
        │    $(summary(b)):
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
        @test genmsg("msg", a=a, show_limited=false) ==
        """
        ┌ PREFIX msg
        │   a =
        │    $(summary(a)):
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
    @test genmsg("line1\n\nline2", color=true) ==
    """
    \e[36m\e[1m┌ \e[22m\e[39m\e[36m\e[1mPREFIX \e[22m\e[39mline1
    \e[36m\e[1m│ \e[22m\e[39m
    \e[36m\e[1m│ \e[22m\e[39mline2
    \e[36m\e[1m└ \e[22m\e[39m\e[90mSUFFIX\e[39m
    """

    # Using infix operator so that `@test` prints lhs and rhs when failed:
    ⊏(s, re) = match(re, s) !== nothing

    @test genmsg("", progress=0.1, width=60) ⊏
    r"Progress:  10%\|█+.* +\|  ETA: .*"
    @test genmsg("", progress=NaN, width=60) ⊏
    r"Progress:   0%\|. +\|  ETA: .*"
    @test genmsg("", progress=1.0, width=60) == ""
    @test genmsg("", progress="done", width=60) == ""
    @test genmsgs([("", (progress = 0.1,)), ("", (progress = 1.0,))], width = 60)[end] ⊏
    r"Progress: 100%\|█+\| Time: .*"
    @test genmsgs([("", (progress = 0.1,)), ("", (progress = "done",))], width = 60)[end] ⊏
    r"Progress: 100%\|█+\| Time: .*"

    @testset "Message formatting" begin
        io_ctx = IOContext(IOBuffer(), :displaysize=>(20,20))

        # Short paragraph on a single line
        @test format_message("Hi `code`", 6, io_ctx) ==
            ["Hi code"]

        # Longer paragraphs wrap around the prefix
        @test format_message("x x x x x x x x x x x x x x x x x x x x x", 6, io_ctx) ==
             ["x x x x x"
              "x x x x x x x x"
              "x x x x x x x x"]

        # Markdown block elements get their own lines
        @test format_message("# Hi", 6, io_ctx) ==
            ["",
             "Hi",
             VERSION < v"1.10-DEV" ? "≡≡≡≡" : "≡≡"]

        # For non-strings a blank line is added so that any formatting for
        # vertical alignment isn't broken
        @test format_message(Text(" 1  2\n 3  4"), 6, io_ctx) ==
            ["",
             " 1  2",
             " 3  4"]
    end

    @testset "Independent progress bars" begin
        msgs = genmsgs([
            ("Bar1", (progress = 0.0, _id = 1111)), # 1
            ("Bar2", (progress = 0.5, _id = 2222)),
            ("Bar2", (progress = 1.0, _id = 2222)), # 3
            ("", (progress = "done", _id = 2222)),  # 4
            ("Bar1", (progress = 0.2, _id = 1111)), # 5
            ("Bar2", (progress = 0.5, _id = 2222)),
            ("Bar2", (progress = 1.0, _id = 2222)), # 7
            ("", (progress = "done", _id = 2222)),  # 8
            ("Bar1", (progress = 0.4, _id = 1111)),
            ("", (progress = "done", _id = 1111)),
        ]; width=60)
        @test msgs[1] ⊏ r"""
        Bar1   0%\|. +\|  ETA: N/A
        """
        @test msgs[3] ⊏ r"""
        Bar2 100%\|█+\| Time: .*
        Bar1   0%\|. +\|  ETA: .*
        """
        @test msgs[4] ⊏ r"""
        Bar1   0%\|. +\|  ETA: .*
        Bar2 100%\|█+\| Time: .*
        """
        @test msgs[5] ⊏ r"""
        Bar1  20%\|█+.* +\|  ETA: .*
        """
        @test msgs[7] ⊏ r"""
        Bar2 100%\|█+\| Time: .*
        Bar1  20%\|█+.* +\|  ETA: .*
        """
        @test msgs[8] ⊏ r"""
        Bar1  20%\|█+.* +\|  ETA: .*
        Bar2 100%\|█+\| Time: .*
        """
        @test msgs[end] ⊏ r"""
        Bar1 100%\|█+\| Time: .*
        """
    end

    @testset "Nested progress bars" begin
        id_outer = UUID(100)
        id_inner_1 = UUID(201)
        id_inner_2 = UUID(202)
        outermsg(fraction; kw...) =
            (Progress(id_outer, fraction; name = "Outer", kw...), Dict())
        innermsg(id, fraction; kw...) =
            (Progress(id, fraction; name = "Inner", parentid = id_outer, kw...), Dict())
        msgs = genmsgs([
            outermsg(0.0),                              # 1
            innermsg(id_inner_1, 0.5),
            innermsg(id_inner_1, 1.0),                  # 3
            innermsg(id_inner_1, nothing; done = true), # 4
            outermsg(0.2),                              # 5
            innermsg(id_inner_2, 0.5),
            innermsg(id_inner_2, 1.0),                  # 7
            innermsg(id_inner_2, nothing; done = true), # 8
            outermsg(0.4),
            outermsg(nothing; done = true),
        ]; width=60)
        @test msgs[1] ⊏ r"""
        Outer   0%\|. +\|  ETA: N/A
        """
        @test msgs[3] ⊏ r"""
          Inner 100%\|█+\| Time: .*
        Outer   0%\|. +\|  ETA: .*
        """
        @test msgs[4] ⊏ r"""
        Outer   0%\|. +\|  ETA: .*
          Inner 100%\|█+\| Time: .*
        """
        @test msgs[5] ⊏ r"""
        Outer  20%\|█+.* +\|  ETA: .*
        """
        @test msgs[7] ⊏ r"""
          Inner 100%\|█+\| Time: .*
        Outer  20%\|█+.* +\|  ETA: .*
        """
        @test msgs[8] ⊏ r"""
        Outer  20%\|█+.* +\|  ETA: .*
          Inner 100%\|█+\| Time: .*
        """
        @test msgs[end] ⊏ r"""
        Outer 100%\|█+\| Time: .*
        """
    end

    @static if VERSION >= v"1.3.0"
        @testset "Parallel progress" begin
            buf = IOBuffer()
            io = IOContext(buf, :displaysize=>(30,75), :color=>false)
            logger = TerminalLogger(io, Debug)
            # Crude multithreading test: generate some contention.
            #
            # Generate some contention in multi-threaded cases
            ntasks = 8
            @sync begin
                with_logger(logger) do
                    for i=1:ntasks
                        Threads.@spawn for j=1:100
                            @info "XXXX <$i,$j>" maxlog=100
                            #sleep(0.001)
                        end
                    end
                end
            end
            log_str = String(take!(buf))
            @test length(findall("XXXX", log_str)) == 100

            # Fun test of parallel progress logging to watch interactively:
            #=
            using ProgressLogging
            @sync begin
                for i=1:8
                    Threads.@spawn @progress name="task $i" threshold=0.00005 for j=1:10000
                        #sleep(0.001)
                    end
                end
            end
            =#
        end
    end
end
