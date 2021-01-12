"""
    StickyMessages(io::IO; ansi_codes=io isa Base.TTY && 
                   (!Sys.iswindows() || VERSION >= v"1.5.3"))

A `StickyMessages` type manages the display of a set of persistent "sticky"
messages in a terminal. That is, messages which are not part of the normal
scrolling output. Each message is identified by a label and may may be added to
the set using `push!(messages, label=>msg)`, and removed using
`pop!(messages, label)`, or `empty!()`.

Only a single StickyMessages object should be associated with a given TTY, as
the object manipulates the terminal scrolling region.
"""
mutable struct StickyMessages
    io::IO
    # Bool for controlling TTY escape codes.
    ansi_codes::Bool
    # Messages is just used as a (short) OrderedDict here
    messages::Vector{Pair{Any,String}}
end

function StickyMessages(io::IO; ansi_codes=io isa Base.TTY &&
        # scroll region code on Windows only works with recent libuv, present in 1.5.3+
        (!Sys.iswindows() || VERSION >= v"1.5.3"))
    sticky = StickyMessages(io, ansi_codes, Vector{Pair{Any,String}}())
    # Ensure we clean up the terminal
    finalizer(sticky) do sticky
        # See also empty!()
        if !sticky.ansi_codes
            return
        end
        prev_nlines = _countlines(sticky.messages)
        if prev_nlines > 0
            # Clean up sticky lines. Hack: must be async to do the IO outside
            # of finalizer. Proper fix would be an uninstall event triggered by
            # with_logger.
            @async showsticky(sticky.io, prev_nlines, [])
        end
    end
    sticky
end

# Count newlines in a message or sequence of messages
_countlines(msg::String) = sum(c->c=='\n', msg)
_countlines(messages) = length(messages) > 0 ? sum(_countlines, messages) : 0
_countlines(messages::Vector{<:Pair}) = _countlines(m[2] for m in messages)

# Selected TTY cursor and screen control via ANSI codes
# * https://en.wikipedia.org/wiki/ANSI_escape_code#CSI_sequences
# * See man terminfo on linux, eg `tput csr $row1 $row2` and `tput cup $row $col`
# * For windows see https://docs.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences
change_scroll_region!(io, rows::Pair) = write(io, "\e[$(rows[1]);$(rows[2])r")
change_cursor_line!(io, line::Integer) = write(io, "\e[$line;1H")
clear_to_end!(io) = write(io, "\e[J")

function showsticky(io, prev_nlines, messages)
    height,_ = displaysize(io)
    iob = IOBuffer()
    if prev_nlines > 0
        change_cursor_line!(iob, height + 1 - prev_nlines)
        clear_to_end!(iob)
    end
    # Set scroll region to the first N lines.
    #
    # Terminal scrollback buffers seem to be populated with a heuristic which
    # relies on the scrollable region starting at the first row, so to have
    # normal scrollback work we have to position sticky messages at the bottom
    # of the screen.
    linesrequired = _countlines(messages)
    if prev_nlines < linesrequired
        # Scroll screen up to preserve the lines which we will overwrite
        change_cursor_line!(iob, height - prev_nlines)
        write(iob, "\n"^(linesrequired-prev_nlines))
    end
    if prev_nlines != linesrequired
        change_scroll_region!(iob, 1=>height-linesrequired)
    end
    # Write messages. Avoid writing \n of last message to kill extra scrolling
    if !isempty(messages)
        change_cursor_line!(iob, height + 1 - linesrequired)
        for i = 1:length(messages)-1
            write(iob, messages[i][2])
        end
        write(iob, chop(messages[end][2]))
    end
    # TODO: Ideally we'd query the terminal for the line it was on before doing
    # all this and restore it if it's not in the new non-scrollable region.
    change_cursor_line!(iob, height - max(prev_nlines, linesrequired))
    # Write in one block to make the whole operation as atomic as possible.
    write(io, take!(iob))
    nothing
end

function Base.push!(sticky::StickyMessages, message::Pair)
    if !sticky.ansi_codes
        println(sticky.io, rstrip(message[2]))
        return
    end
    label,text = message
    endswith(text, '\n') || (text *= '\n';)
    prev_nlines = _countlines(sticky.messages)
    idx = findfirst(m->m[1] == label, sticky.messages)
    if idx === nothing
        push!(sticky.messages, label=>text)
    else
        sticky.messages[idx] = label=>text
    end
    showsticky(sticky.io, prev_nlines, sticky.messages)
end

function Base.pop!(sticky::StickyMessages, label)
    sticky.ansi_codes || return
    idx = findfirst(m->m[1] == label, sticky.messages)
    if idx !== nothing
        prev_nlines = _countlines(sticky.messages)
        deleteat!(sticky.messages, idx)
        showsticky(sticky.io, prev_nlines, sticky.messages)
    end
    nothing
end

function Base.empty!(sticky::StickyMessages)
    sticky.ansi_codes || return
    prev_nlines = _countlines(sticky.messages)
    empty!(sticky.messages)
    showsticky(sticky.io, prev_nlines, sticky.messages) # Resets scroll region
    nothing
end

