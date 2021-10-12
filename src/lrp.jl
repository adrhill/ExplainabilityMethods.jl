"""
    LRP(c::Chain, r::AbstractLRPRule)
    LRP(c::Chain, rs::AbstractVector{<:AbstractLRPRule})
    LRP(layers::AbstractVector{LRPLayer})

Analyzer that applies LRP.
"""
struct LRP{C<:Chain,R<:LRPRuleset} <: AbstractXAIMethod
    model::C
    rules::R

    # Construct LRP analyzer by manually assigning a rule to each layer
    function LRP(model::Chain, rules::LRPRuleset)
        if length(model.layers) != length(rules)
            throw(DimensionError("Length of rules doesn't match length of Flux chain."))
        end
        return new{typeof(model),typeof(rules)}(model, rules)
    end
    # Construct LRP analyzer by assigning a single rule to all layers
    function LRP(model::Chain, r::AbstractLRPRule)
        rules = repeat([r], length(model.layers))
        return new{typeof(model),typeof(rules)}(model, rules)
    end
end
# Additional constructors for convenience:
LRPZero(model::Chain) = LRP(model, ZeroRule())
LRPEpsilon(model::Chain) = LRP(model, EpsilonRule())
LRPGamma(model::Chain) = LRP(model, GammaRule())

# The call to the LRP analyzer.
function (analyzer::LRP)(input, ns::AbstractNeuronSelector; layerwise_relevances=false)
    layers = analyzer.model.layers
    acts = [input]
    # Forward pass through layers, keeping track of activations
    for l in layers
        append!(acts, l(acts[end]))
    end
    rels = acts # allocate arrays

    # Mask output neuron
    output_neuron = ns(activations[end])
    rels[end] .*= 0
    rels[end][output_neuron] .= acts[end][output_neuron]

    # Backward pass through layers, applying LRP rules
    for (i, rule) in Iterators.reverse(enumerate(analyzer.rules))
        rels[i] .= rule(layers[i], acts[i], rels[i + 1]) # Rₖ = rule(layer, aₖ, Rₖ₊₁)
    end

    if layerwise_relevances
        return acts, rels
    else
        return acts[end], rels[1] # corresponds to output, expl
    end
end
