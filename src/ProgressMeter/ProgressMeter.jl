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

struct ProgressBar
    barglyphs::BarGlyphs
    tfirst::Float64
end

ProgressBar(barglyphs = BarGlyphs()) = ProgressBar(barglyphs, time())

"""
    printprogress(io::IO, p::ProgressBar, desc, progress::Real)

Print progress bar to `io` with setting `p`.

# Arguments
- `io::IO`
- `p::ProgressBar`
- `desc`: description to be printed at left side of progress bar.
- `progress::Real`: a number between 0 and 1 or a `NaN`.
"""
function printprogress(io::IO, p::ProgressBar, desc, progress::Real)
    t = time()
    percentage_complete = 100.0 * (isnan(progress) ? 0.0 : progress)

    #...length of percentage and ETA string with days is 29 characters
    barlen = max(0, displaysize(io)[2] - (length(desc) + 29))

    if progress >= 1
        bar = barstring(barlen, percentage_complete, barglyphs=p.barglyphs)
        dur = durationstring(t - p.tfirst)
        @printf io "%s%3u%%%s Time: %s" desc round(Int, percentage_complete) bar dur
        return
    end

    bar = barstring(barlen, percentage_complete, barglyphs=p.barglyphs)
    elapsed_time = t - p.tfirst
    est_total_time = 100 * elapsed_time / percentage_complete
    if 0 <= est_total_time <= typemax(Int)
        eta_sec = round(Int, est_total_time - elapsed_time)
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

end
