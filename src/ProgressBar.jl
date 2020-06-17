Base.@kwdef mutable struct ProgressBar
    fraction::Union{Float64,Nothing}
    name::String
    level::Int = 0
    barglyphs::BarGlyphs = BarGlyphs()
    tlast::Float64 = time()
    tfirst::Float64 = time()
    id::UUID
    parentid::UUID
end

set_fraction!(bar::ProgressBar, ::Nothing) = bar
function set_fraction!(bar::ProgressBar, fraction::Real)
    bar.tlast = time()
    bar.fraction = fraction
    return bar
end

# This is how `ProgressMeter.printprogress` decides "ETA" vs "Time":
ensure_done!(bar::ProgressBar) = bar.fraction = 1

function eta_seconds(bar)
    total = (bar.tlast - bar.tfirst) / something(bar.fraction, NaN)
    return total - (time() - bar.tfirst)
end


function printprogress(io::IO, bar::ProgressBar)
    if bar.name == ""
        desc = "Progress: "
    else
        desc = bar.name
        if !endswith(desc, " ")
            desc *= " "
        end
    end

    pad = "  "^bar.level
    print(io, pad)

    lines, columns = displaysize(io)
    ProgressMeter.printprogress(
        IOContext(io, :displaysize => (lines, max(1, columns - length(pad)))),
        bar.barglyphs,
        bar.tfirst,
        desc,
        bar.fraction,
        eta_seconds(bar),
    )
end
