struct Row
    id
    names::Vector{String}
    values::Vector{String}
end

struct TableMonitor
    sticky_messages::StickyMessages
    io::IO
    rows::Vector{Row}
    flushed::Vector{Bool}
end

TableMonitor(sticky_messages::StickyMessages, io::IO = sticky_messages.io) =
    TableMonitor(sticky_messages, io, [], [])

function tablelines(
    table::TableMonitor,
    oldrows = nothing,
    tobeflushed = ();
    bottom_line = false,
)
    data = permutedims(mapreduce(row -> row.values, vcat, table.rows))
    highlighters = ()
    if oldrows !== nothing
        data = vcat(data, permutedims(mapreduce(row -> row.values, vcat, oldrows)))
        right = cumsum(Int[length(row.values) for row in oldrows])
        left = insert!(right[1:end-1], 1, 0)
        # Dim unchanged rows:
        highlighters = Highlighter(
            (data, i, j) -> i == 2 && !any(k -> left[k] < j <= right[k], tobeflushed);
            foreground = :dark_gray,
        )
    end
    text = sprint(context = table.io) do io
        pretty_table(
            io,
            data,
            mapreduce(row -> row.names, vcat, table.rows),
            PrettyTableFormat(top_line = false, bottom_line = bottom_line);
            highlighters = highlighters,
        )
    end
    return split(text, "\n")
end

function draw!(table::TableMonitor, oldrows = nothing, tobeflushed = ())
    lines = tablelines(table, oldrows, tobeflushed)
    formatted = join(reverse!(lines[1:3]), "\n")  # row, hline, header
    if oldrows !== nothing
        print(table.io, '\n', lines[4])
    end
    push!(table.sticky_messages, _tablelabel => formatted; first = true)
end

const _tablelabel = gensym("TableMonitor")

Base.push!(table::TableMonitor, (id, namedtuple)::Pair{<:Any,<:NamedTuple}) = push!(
    table,
    Row(id, collect(string.(keys(namedtuple))), collect(string.(values(namedtuple)))),
)

function Base.push!(table::TableMonitor, row::Row)
    idx = findfirst(x -> x.id == row.id, table.rows)
    if idx !== nothing
        if table.flushed[idx]
            tobeflushed = ()
            oldrows = nothing
            table.flushed[idx] = false
        else
            tobeflushed = findall(!, table.flushed)
            oldrows = copy(table.rows)
            table.flushed .= [i != idx for i in 1:length(table.rows)]
        end
        table.rows[idx] = row
        draw!(table, oldrows, tobeflushed)
    else
        push!(table.flushed, false)
        push!(table.rows, row)
        draw!(table)
    end
    return table
end

function flush_table!(table::TableMonitor)
    pop!(table.sticky_messages, _tablelabel)

    lines = tablelines(table; bottom_line = true)[1:end-1]
    bottom = pop!(lines)
    for line in reverse!(lines)
        print(table.io, '\n', line)
    end
    print(table.io, '\n', bottom)

    fill!(table.flushed, true)
end

function Base.pop!(table::TableMonitor, id)
    idx = findfirst(x -> x.id == id, table.rows)
    idx === nothing && return

    if !table.flushed[idx]
        flush_table!(table)
    end

    deleteat!(table.flushed, idx)
    return deleteat!(table.rows, idx)
end
