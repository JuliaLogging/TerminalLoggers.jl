using Markdown

"""
    TerminalLogger(stream=stderr, min_level=$ProgressLevel; meta_formatter=default_metafmt,
                   show_limited=true, right_justify=0)

Logger with formatting optimized for interactive readability in a text console
(for example, the Julia REPL). This is an enhanced version of the terminal
logger `Logging.ConsoleLogger` which comes installed with Julia by default.

Log levels less than `min_level` are filtered out.

Message formatting can be controlled by setting keyword arguments:

* `meta_formatter` is a function which takes the log event metadata
  `(level, _module, group, id, file, line)` and returns a color (as would be
  passed to printstyled), prefix and suffix for the log message.  The
  default is to prefix with the log level and a suffix containing the module,
  file and line location.
* `show_limited` limits the printing of large data structures to something
  which can fit on the screen by setting the `:limit` `IOContext` key during
  formatting.
* `right_justify` is the integer column which log metadata is right justified
  at. The default is zero (metadata goes on its own line).
"""
struct TerminalLogger <: AbstractLogger
    stream::IO
    min_level::LogLevel
    meta_formatter
    show_limited::Bool
    right_justify::Int
    always_flush::Bool
    margin::Int
    message_limits::Dict{Any,Int}
    sticky_messages::StickyMessages
    bartrees::Vector{Node{ProgressBar}}
    lock::ReentrantLock
end
function TerminalLogger(stream::IO=stderr, min_level=ProgressLevel;
                        meta_formatter=default_metafmt, show_limited=true,
                        right_justify=0, always_flush=false, margin=0)
    TerminalLogger(
        stream,
        min_level,
        meta_formatter,
        show_limited,
        right_justify,
        always_flush,
        margin,
        Dict{Any,Int}(),
        StickyMessages(stream),
        Union{}[],
        ReentrantLock()
    )
end

function shouldlog(logger::TerminalLogger, level, _module, group, id)
    lock(logger.lock) do
        get(logger.message_limits, id, 1) > 0
    end
end

min_enabled_level(logger::TerminalLogger) = logger.min_level

function default_logcolor(level)
    level < Info  ? :blue :
    level < Warn  ? Base.info_color()  :
    level < Error ? Base.warn_color()  :
                    Base.error_color()
end

function default_metafmt(level, _module, group, id, file, line)
    color = default_logcolor(level)
    prefix = (level == Warn ? "Warning" : string(level))*':'
    suffix = ""
    Info <= level < Warn && return color, prefix, suffix
    _module !== nothing && (suffix *= "$(_module)")
    if file !== nothing
        _module !== nothing && (suffix *= " ")
        suffix *= string(file)
        if line !== nothing
            suffix *= ":$(isa(line, UnitRange) ? "$(first(line))-$(last(line))" : line)"
        end
    end
    !isempty(suffix) && (suffix = "@ " * suffix)
    return color, prefix, suffix
end

# Length of a string as it will appear in the terminal (after ANSI color codes
# are removed)
function termlength(str)
    N = 0
    in_esc = false
    for c in str
        if in_esc
            if c == 'm'
                in_esc = false
            end
        else
            if c == '\e'
                in_esc = true
            else
                N += 1
            end
        end
    end
    return N
end

function format_message(message, prefix_width, io_context)
    formatted = sprint(show, MIME"text/plain"(), message, context=io_context)
    msglines = split(chomp(formatted), '\n')
    if length(msglines) > 1
        # For multi-line messages it's possible that the message was carefully
        # formatted with vertical alignemnt. Therefore we play it safe by
        # prepending a blank line.
        pushfirst!(msglines, SubString(""))
    end
    msglines
end

function format_message(message::AbstractString, prefix_width, io_context)
    # For strings, use Markdown to do the formatting. The markdown renderer
    # isn't very composable with other text formatting so this is quite hacky.
    message = Markdown.parse(message)
    prepend_prefix = !isempty(message.content) &&
                     message.content[1] isa Markdown.Paragraph
    if prepend_prefix
        # Hack: We prepend the prefix here to allow the markdown renderer to be
        # aware of the indenting which will result from prepending the prefix.
        # Without this we will get many issues of broken vertical alignment.
        # Avoid collisions: using placeholder from unicode private use area
        placeholder = '\uF8FF'^prefix_width
        pushfirst!(message.content[1].content, placeholder)
    end
    formatted = sprint(show, MIME"text/plain"(), message, context=io_context)
    msglines = split(chomp(formatted), '\n')
    # Hack': strip left margin which can't be configured in Markdown
    # terminal rendering.
    msglines = [startswith(s, "  ") ? s[3:end] : s for s in msglines]
    if prepend_prefix
        # Hack'': Now remove the prefix from the rendered markdown.
        msglines[1] = replace(msglines[1], placeholder=>""; count=1)
    elseif !isempty(msglines[1])
        pushfirst!(msglines, SubString(""))
    end
    msglines
end

# Formatting of values in key value pairs
function showvalue(io, key, msg)
    if key === :exception && msg isa Vector && length(msg) > 1 && msg[1] isa Tuple{Exception,Any}
        if VERSION >= v"1.2"
            # Ugly code path to support passing exception=Base.catch_stack()
            # `Base.ExceptionStack` was only introduced in Julia 1.7.0-DEV.1106
            # https://github.com/JuliaLang/julia/pull/29901 (dispatched on below).
            Base.show_exception_stack(io, msg)
        else
            # v1.0 and 1.1 don't have Base.show_exception_stack
            show(io, MIME"text/plain"(), msg)
        end
    else
        show(io, MIME"text/plain"(), msg)
    end
end
function showvalue(io, key, e::Tuple{Exception,Any})
    ex,bt = e
    showerror(io, ex, bt; backtrace = bt!==nothing)
end
showvalue(io, key, ex::Exception) = showerror(io, ex)

# Generate a text representation of all key value pairs, split into lines with
# per-line indentation as an integer.
function format_key_value_pairs(kwargs, io_context)
    msglines = Tuple{Int,String}[]
    valbuf = IOBuffer()
    dsize = displaysize(io_context)
    rows_per_value = max(1, dsize[1]÷(length(kwargs)+1))
    valio = IOContext(valbuf, IOContext(io_context, :displaysize=>(rows_per_value,dsize[2]-3)))
    for (key,val) in kwargs
        showvalue(valio, key, val)
        vallines = split(String(take!(valbuf)), '\n')
        if length(vallines) == 1
            push!(msglines, (2,SubString("$key = $(vallines[1])")))
        else
            push!(msglines, (2,SubString("$key =")))
            append!(msglines, ((3,line) for line in vallines))
        end
    end
    msglines
end

function findbar(bartree, id)
    if !(bartree isa AbstractArray)
        bartree.data.id === id && return bartree
    end
    for node in bartree
        found = findbar(node, id)
        found === nothing || return found
    end
    return nothing
end

function foldtree(op, acc, tree)
    for node in tree
        acc = foldtree(op, acc, node)
    end
    if !(tree isa AbstractArray)
        acc = op(acc, tree)
    end
    return acc
end

const BAR_MESSAGE_ID = gensym(:BAR_MESSAGE_ID)

function handle_progress(logger, progress, kwargs)
    node = findbar(logger.bartrees, progress.id)
    if node === nothing
        # Don't do anything when it's already done:
        (progress.done || something(progress.fraction, 0.0) >= 1) && return

        parentnode = findbar(logger.bartrees, progress.parentid)
        bar = ProgressBar(
            fraction = progress.fraction,
            name = progress.name,
            id = progress.id,
            parentid = progress.parentid,
        )
        if parentnode === nothing
            node = Node(bar)
            pushfirst!(logger.bartrees, node)
        else
            bar.level = parentnode.data.level + 1
            node = addchild(parentnode, bar)
        end
    else
        bar = node.data
        set_fraction!(bar, progress.fraction)
        if progress.name != ""
            bar.name = progress.name
        end
        node.data = bar
    end
    if progress.done
        if isroot(node)
            deleteat!(logger.bartrees, findfirst(x -> x === node, logger.bartrees))
        else
            prunebranch!(node)
        end
    end

    bartxt = sprint(context = :displaysize => displaysize(logger.stream)) do io
        foldtree(true, logger.bartrees) do isfirst, node
            isfirst || println(io)
            printprogress(io, node.data)
            false  # next `isfirst`
        end
    end
    if isempty(bartxt)
        pop!(logger.sticky_messages, BAR_MESSAGE_ID)
    else
        bartxt = sprint(context = logger.stream) do io
            printstyled(io, bartxt; color=:green)
        end
        push!(logger.sticky_messages, BAR_MESSAGE_ID => bartxt)
    end

    # "Flushing" non-sticky message should be done after the sticky
    # message is re-drawn:
    if progress.done
        ensure_done!(bar)
        donetxt = sprint(context = :displaysize => displaysize(logger.stream)) do io
            printprogress(io, bar)
        end
        printstyled(logger.stream, donetxt; color=:light_black)
        println(logger.stream)
    end

    if logger.always_flush
        flush(logger.stream)
    end
end

function handle_message(logger::TerminalLogger, level, message, _module, group, id,
                        filepath, line; maxlog=nothing,
                        sticky=nothing, kwargs...)
    if maxlog !== nothing && maxlog isa Integer
        remaining = 0
        lock(logger.lock) do
            remaining = get!(logger.message_limits, id, maxlog)
            logger.message_limits[id] = remaining - 1
        end
        remaining > 0 || return
    end

    progress = asprogress(level, message, _module, group, id, filepath, line; kwargs...)
    if progress !== nothing
        lock(logger.lock) do
            handle_progress(logger, progress, kwargs)
        end
        return
    end

    color,prefix,suffix = logger.meta_formatter(level, _module, group, id, filepath, line)

    # Generate a text representation of the message
    dsize = displaysize(logger.stream)
    context = IOContext(logger.stream, :displaysize=>(dsize[1],dsize[2]-2))
    msglines = format_message(message, textwidth(prefix), context)
    # Add indentation level
    msglines = [(0,l) for l in msglines]
    if !isempty(kwargs)
        ctx = logger.show_limited ? IOContext(context, :limit=>true) : context
        append!(msglines, format_key_value_pairs(kwargs, ctx))
    end

    # Format lines as text with appropriate indentation and with a box
    # decoration on the left.
    minsuffixpad = 2
    buf = IOBuffer()
    iob = IOContext(buf, logger.stream)
    nonpadwidth = 2 + (isempty(prefix) || length(msglines) > 1 ? 0 : length(prefix)+1) +
                  msglines[end][1] + termlength(msglines[end][2]) +
                  (isempty(suffix) ? 0 : length(suffix)+minsuffixpad)
    justify_width = min(logger.right_justify, dsize[2])
    if nonpadwidth > justify_width && !isempty(suffix)
        push!(msglines, (0,SubString("")))
        minsuffixpad = 0
        nonpadwidth = 2 + length(suffix)
    end
    for (i,(indent,msg)) in enumerate(msglines)
        boxstr = length(msglines) == 1 ? "[ " :
                 i == 1                ? "┌ " :
                 i < length(msglines)  ? "│ " :
                                         "└ "
        printstyled(iob, boxstr, bold=true, color=color)
        if i == 1 && !isempty(prefix)
            printstyled(iob, prefix, " ", bold=true, color=color)
        end
        print(iob, " "^indent, msg)
        if i == length(msglines) && !isempty(suffix)
            npad = max(0, justify_width - nonpadwidth) + minsuffixpad
            print(iob, " "^npad)
            printstyled(iob, suffix, color=:light_black)
        end
        println(iob)
    end
    
    if sticky === nothing
        for _ in 1:logger.margin
            println(iob)
        end
    end

    msg = take!(buf)

    lock(logger.lock) do
        if sticky !== nothing
            # Ensure we see the last message, even if it's :done
            push!(logger.sticky_messages, id=>String(msg))
            if sticky == :done
                pop!(logger.sticky_messages, id)
            end
        else
            write(logger.stream, msg)
        end
        
        if logger.always_flush
            flush(logger.stream)
        end
    end

    nothing
end

