const water_fraction_to_M = 1.0m^3*m^-3 * 1kg*L^-1 / 18.0g*mol^-1

using Base: tail


abstract type AbstractLayerInterpolator end

struct LinearLayerInterpolator <: AbstractLayerInterpolator
    layer::Int
    frac::Float64
end

struct LinearLayerInterpolators{H} <: AbstractLayerInterpolator
    range::LinearLayerInterpolator
    increment::LinearLayerInterpolator
    height::H
end
LinearLayerInterpolators(env, height) =
    LinearLayerInterpolators(range_interpolator(env, height), increment_interpolator(env, height), height)

# Use recursion so the compiler does this with tuples. Huge performance improvement.
@inline layer_sizes(z, I::Tuple, NL) = (lsize(z, I[1], I[2]), layer_sizes(I, NL)...)
@inline layer_sizes(I::Tuple, NL) = (lsize(I[1], I[2], I[3]), layer_sizes(tail(I), NL)...)
@inline layer_sizes(I::Tuple{X,X}, NL) where X = (lsize(I[1], I[2], NL),)

@inline lsize(a, b, c) = (c + b)  / 2 - (b + a) / 2

@inline layer_bounds(inc::Tuple{X,Vararg}, next) where X = (bound(inc[1], inc[2]), layer_bounds(tail(inc), next)...)
@inline layer_bounds(inc::Tuple{X}, next) where X = (bound(inc[1], next),)

@inline bound(a::Number, b::Number) = (a + b) / 2


@inline max_height(env) = sum(layer_sizes(env))
@inline layer_props(env) = layer_sizes(env) ./ max_height(env)


" Calculate current interpolation layers and fraction from NicheMapR data"
@inline increment_interpolator(env, height) = begin
    increments = get_increments(env)
    for (i, height_upper) in enumerate(increments)
        if height_upper > height
            height_lower = increments[i - 1]
            frac = (height - height_lower) / (height_upper - height_lower)
            return LinearLayerInterpolator(i - 1, frac)
        end
    end
    # Otherwise it's taller/deeper than we have data, so use the largest we have.
    LinearLayerInterpolator(lastindex(increments) - 1, 1.0)
end

@inline range_interpolator(env, height) = begin
    lower, upper = get_range(env)
    h = min(max(height, lower), upper)
    frac = (h - lower)/(upper - lower)
    LinearLayerInterpolator(1, frac)
end


" Interpolate between two layers of environmental data. "
@inline interp_layer(layers::Matrix, t, interp) =
    lin_interp(layers, t, interp.layer) * (oneunit(interp.frac) - interp.frac) +
    lin_interp(layers, t, interp.layer + 1) * interp.frac


" Linear interpolation "
@inline lin_interp(vector::Vector, t) = begin
    t_int = floor(Int64, t)
    frac = t - t_int
    vector[t_int] * (oneunit(frac) - frac) + vector[t_int + 1] * frac
end
@inline lin_interp(matrix::Matrix, t, l) = begin
    t_int = floor(Int64, t)
    frac = t - t_int
    matrix[t_int, l] * (oneunit(frac) - frac) + matrix[t_int + 1, l] * frac
end
@inline lin_interp(vector::Vector, t::Int) = vector[t]
@inline lin_interp(matrix::Matrix, t::Int, l) = matrix[t, l]


@inline weightedmean(env, layers, t, inpterp::LinearLayerInterpolators) = 
    weightedmean(env, layers, t, inpterp.height)
weightedmean(env, layers, t, height::Number) = begin
    wmean = zero(layers[1][1])*m
    lbounds = layer_bounds(env)
    lsizes = layer_sizes(env)
    h = min(height, max_height(env))
    # sum all layers < height, after size adjustment
    for l = 1:length(lbounds)
        if h > lbounds[l]
            # add the whole layer 
            wmean += lin_interp(layers, t, l) * lsizes[l]
        else
            # add the last fractional layer and break the loop
            frac = 1 - ((lbounds[l] - h) / lsizes[l])
            wmean += lin_interp(layers, t, l) * lsizes[l] * frac
            break
        end
    end
    wmean / h
end

@inline layermax(layers, t, interp) = begin
    t_int = floor(Int, t)
    val = layers[t_int, 1]
    for l = 2:interp.layer
        val = max(val, layers[t_int, l])
    end
    val
end
