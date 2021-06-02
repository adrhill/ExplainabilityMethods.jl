"""
Annotate layers in the chain by mapping them to one of the following symbols:

  - `:FirstPixels`
  - `:FirstReals`
  - `:Lower`
  - `:Middle`
  - `:Upper`
  - `:Top`
  - `:TopSoftmax`
"""
function annotate_chain(
    chain::Chain, middle_start::Integer, upper_start::Integer; input_type::String="pixels"
)
    n_layers = length(chain)

    function annotate_layer(i)::Symbol
        if i == 1 # Input layer
            if input_type == "pixels"
                return :FirstPixels
            elseif input_type == "reals"
                return :FirstReals
            else
                throw(
                    ArgumentError(
                        """Unknown input type "$(input_type)". Expected "pixels" or "reals".""",
                    ),
                )
            end
        elseif i < middle_start # Lower layers
            return :Lower
        elseif i < upper_start # Middle layers
            return :Middle
        elseif i < n_layers # Upper layers
            return :Upper
        elseif i == n_layers # Output layer
            if chain[n_layers] == softmax
                return :TopSoftmax
            else
                return :Top
            end
        else
            throw(DimensionError("_annotate_layer called outside of chain length."))
        end
    end

    return annotations = ntuple(annotate_layer, Val(n_layers))
end
"""
Annotate layers in the chain by mapping them to one of the following symbols:

  - `:FirstPixels`
  - `:FirstReals`
  - `:Lower`
  - `:Middle`
  - `:Upper`
  - `:Top`
  - `:TopSoftmax`

If no positional arguments are supplied, a 45/35/20%-split heuristic is applied.
"""
function annotate_chain(chain::Chain; kwargs...)
    n_layers = length(chain)
    middle_start = floor(Int, 0.45 * n_layers)
    upper_start = floor(Int, 0.8 * n_layers)

    return annotate_chain(chain, middle_start, upper_start; kwargs...)
end