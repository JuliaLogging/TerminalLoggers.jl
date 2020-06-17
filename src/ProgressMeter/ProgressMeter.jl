module ProgressMeter

using Printf: @printf, @sprintf

"""
Holds the five characters that will be used to generate the progress bar.
"""
mutable struct BarGlyphs
    leftend::Char
    fill::Char
    front::Union{Vector{Char}, Char}
    empty::Char
    rightend::Char
end

BarGlyphs() = BarGlyphs(
    '|',
    '█',
    Sys.iswindows() ? '█' : ['▏', '▎', '▍', '▌', '▋', '▊', '▉'],
    ' ',
    '|',
)

"""
    printprogress(io::IO, barglyphs::BarGlyphs, tfirst::Float64, desc, progress, eta_seconds::Real)

Print progress bar to `io`.

# Arguments
- `io::IO`
- `barglyphs::BarGlyphs`
- `tfirst::Float64`
- `desc`: description to be printed at left side of progress bar.
- `progress`: a number between 0 and 1 or `nothing`.
- `eta_seconds::Real`: ETA in seconds
"""
function printprogress(
    io::IO,
    barglyphs::BarGlyphs,
    tfirst::Float64,
    desc,
    progress,
    eta_seconds::Real,
)
    t = time()
    percentage_complete = 100.0 * (isnothing(progress) || isnan(progress) ? 0.0 : progress)

    #...length of percentage and ETA string with days is 29 characters
    barlen = max(0, displaysize(io)[2] - (length(desc) + 29))

    if !isnothing(progress) && progress >= 1
        bar = barstring(barlen, percentage_complete, barglyphs=barglyphs)
        dur = durationstring(t - tfirst)
        @printf io "%s%3u%%%s Time: %s" desc round(Int, percentage_complete) bar dur
        return
    end

    bar = barstring(barlen, percentage_complete, barglyphs=barglyphs)
    if 0 <= eta_seconds <= typemax(Int)
        eta_sec = round(Int, eta_seconds)
        eta = durationstring(eta_sec)
    else
        eta = "N/A"
    end
    @printf io "%s%3u%%%s  ETA: %s" desc round(Int, percentage_complete) bar eta
    return
end

function compute_front(barglyphs::BarGlyphs, frac_solid::AbstractFloat)
    barglyphs.front isa Char && return barglyphs.front
    idx = round(Int, frac_solid * (length(barglyphs.front) + 1))
    return idx > length(barglyphs.front) ? barglyphs.fill :
           idx == 0 ? barglyphs.empty :
           barglyphs.front[idx]
end

function barstring(barlen, percentage_complete; barglyphs)
    bar = ""
    if barlen>0
        if percentage_complete == 100 # if we're done, don't use the "front" character
            bar = string(barglyphs.leftend, repeat(string(barglyphs.fill), barlen), barglyphs.rightend)
        else
            n_bars = barlen * percentage_complete / 100
            nsolid = trunc(Int, n_bars)
            frac_solid = n_bars - nsolid
            nempty = barlen - nsolid - 1
            bar = string(barglyphs.leftend,
                         repeat(string(barglyphs.fill), max(0,nsolid)),
                         compute_front(barglyphs, frac_solid),
                         repeat(string(barglyphs.empty), max(0, nempty)),
                         barglyphs.rightend)
        end
    end
    bar
end

function durationstring(nsec)
    days = div(nsec, 60*60*24)
    r = nsec - 60*60*24*days
    hours = div(r,60*60)
    r = r - 60*60*hours
    minutes = div(r, 60)
    seconds = floor(r - 60*minutes)

    hhmmss = @sprintf "%u:%02u:%02u" hours minutes seconds
    if days>9
        return @sprintf "%.2f days" nsec/(60*60*24)
    elseif days>0
        return @sprintf "%u days, %s" days hhmmss
    end
    hhmmss
end

# issue #31: isnothing require Julia 1.1
# copy-over from
# https://github.com/JuliaLang/julia/blob/0413ef0e4de83b41b637ba02cc63314da45fe56b/base/some.jl
if !isdefined(Base, :isnothing)
    isnothing(::Any) = false
    isnothing(::Nothing) = true
end

end
