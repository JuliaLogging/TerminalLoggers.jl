using TerminalLoggers: StickyMessages

@testset "Sticky messages without ANSI codes" begin
    buf = IOBuffer()
    # Without TTY, messages are just piped through
    stickies = StickyMessages(buf, ansi_codes=false)
    push!(stickies, :a=>"Msg\n")
    @test String(take!(buf)) == "Msg\n"
    push!(stickies, :a=>"Msg\n")
    @test String(take!(buf)) == "Msg\n"
    pop!(stickies, :a)
    @test String(take!(buf)) == ""
end

@testset "Sticky messages with ANSI codes" begin
    buf = IOBuffer()
    dsize = (20, 80) # Intentionally different from default of 25 rows
    # In TTY mode, we generate various escape codes.
    stickies = StickyMessages(IOContext(buf, :displaysize=>dsize), ansi_codes=true)
    push!(stickies, :a=>"Msg\n")
    @test String(take!(buf)) ==  #scroll    #csr    #pos   #msg #pos
                                "\e[20;1H\n\e[1;19r\e[20;1HMsg\e[19;1H"
    push!(stickies, :a=>"MsgMsg\n")
    @test String(take!(buf)) == #clear      #msgpos #msg #repos
                               "\e[20;1H\e[J\e[20;1HMsgMsg\e[19;1H"
    push!(stickies, :b=>"BBB\n")
    @test String(take!(buf)) ==
        #clear       #scroll   #csr    #pos    #msgs      #pos
        "\e[20;1H\e[J\e[19;1H\n\e[1;18r\e[19;1HMsgMsg\nBBB\e[18;1H"
    pop!(stickies, :a)
    @test String(take!(buf)) == #clear       #csr    #pos   #msg #pos
                                "\e[19;1H\e[J\e[1;19r\e[20;1HBBB\e[18;1H"
    pop!(stickies, :b)
    @test String(take!(buf)) == #clear       #csr    #pos
                                "\e[20;1H\e[J\e[1;20r\e[19;1H"
    pop!(stickies, :b)
    @test String(take!(buf)) == ""

    push!(stickies, :a=>"αβγ\n")
    @test String(take!(buf)) ==  #scroll    #csr    #pos   #msg #pos
                                "\e[20;1H\n\e[1;19r\e[20;1Hαβγ\e[19;1H"

    push!(stickies, :b=>"msg\n")
    take!(buf)

    # Remove all two messages
    empty!(stickies)
    @test String(take!(buf)) == #clear       #csr    #pos
                                "\e[19;1H\e[J\e[1;20r\e[18;1H"
end

@testset "Sticky messages with ANSI codes" begin
    buf = IOBuffer()
    dsize = (20, 80) # Intentionally different from default of 25 rows
    stickies = StickyMessages(IOContext(buf, :displaysize=>dsize), ansi_codes=true)
    push!(stickies, :a=>"a-msg\n")
    push!(stickies, :b=>"b-msg\n")
    take!(buf)
    finalize(stickies)
    # Hack to allow StickyMessages async cleanup to run
    for i=1:1000
        yield()
    end
    @test String(take!(buf)) == #clear       #csr    #pos
                                "\e[19;1H\e[J\e[1;20r\e[18;1H"
end
