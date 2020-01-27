Base.@kwdef mutable struct ProgressBar
    fraction::Float64
    name::String
    level::Int = 0
    barglyphs::BarGlyphs = BarGlyphs()
    tlast::Float64 = time()
    tfirst::Float64 = time()
    id::UUID
    parentid::UUID
end

function set_fraction!(bar::ProgressBar, fraction::Real)
    if !isnan(fraction)
        bar.tlast = time()
        bar.fraction = fraction
    end
    return bar
end

function eta_seconds(bar)
    total = (bar.tlast - bar.tfirst) / bar.fraction
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
