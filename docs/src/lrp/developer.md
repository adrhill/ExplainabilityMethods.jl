# [LRP developer documentation](@id lrp-dev-docs)
Before we dive into implementation details, we cover some fundamental theory of LRP.

## Generic LRP rule formulation
The generic LRP rule, of which the ``0``-, ``\epsilon``- and ``\gamma``-rules are special cases, reads[^1][^2]:
```math
R_j^k = \sum_i \frac{\rho(w_{ij}) \; a_j^k}{\epsilon + \sum_{l} \rho(w_{il}) \; a_l^k + b_i} R_i^{k+1}
```

where ``\rho`` is a function that modifies parameters – 
what we call `modify_parameters` or more generally `modify_layer`.

Note that we are using subscript characters to index vectors and matrices 
(e.g. $b_i$ is the $i$-th entry of the bias vector), 
while the superscripts $^k$ and $^{k+1}$ indicate the position of activations $a$ and relevances $R$ in the model.  

On the forward pass, $a^k$ is the input activation into the $k$-th layer 
and $a^{k+1}$ the output of the layer.
On the LRP backward-pass, $R^{k+1}$ is the "input" relevance into the $k$-th layer 
and $R^k$ the "output" relevance. 
For any $k$, $a^k$ and $R^k$ have the same shape. 

###  Generic LRP rule implementation using automatic differentiation
The computation of the generic LRP rule can be decomposed into four steps:
```math
\begin{array}{lr}
\forall_{k}: z_{i}=\epsilon + \sum_{l} \rho(w_{il}) \; a_l^k + b_i & \text { (forward pass) } \\
\forall_{k}: s_{i}= R_{i}^{k+1} / z_{i}             & \text {(element-wise division)} \\
\forall_{j}: c_{j}= \sum_i \rho(w_{ij}) \; s_{i}    & \text {(backward pass)} \\
\forall_{j}: R_{j}^{k} = a_{j}^{k} c_{j}            & \text {(element-wise product)}
\end{array}
```

For "deep rectifier networks". 
the third step can be implemented via automatic differentiation (AD).

This equation is implemented in ExplainableAI as the default method
for all layer types that don't have a specialized implementation.
We will refer to it as the "AD fallback".

[^1]: G. Montavon et al., [Layer-Wise Relevance Propagation: An Overview](https://link.springer.com/chapter/10.1007/978-3-030-28954-6_10)
[^2]: W. Samek et al., [Explaining Deep Neural Networks and Beyond: A Review of Methods and Applications](https://ieeexplore.ieee.org/document/9369420)

## LRP rules in ExplainableAI.jl
The best point of entry into the source code is
[`/src/lrp/rules.jl`](https://github.com/adrhill/ExplainableAI.jl/blob/master/src/lrp/rules.jl).

Calling `analyze` on a LRP-analyzer pre-allocates modified layers by dispatching
`modify_layer` on rule and layer types. It then applies a forward-pass of the model,
keeping track of the activations `aᵏ` for each layer `k`.
The relevance `Rᵏ⁺¹` is then set to the output neuron activation and the rules are applied
in a backward-pass over the model layers and previous activations.

This is done by calling low level functions
```julia
lrp!(Rᵏ, rule, layer, modified_layer, aᵏ, Rᵏ⁺¹)
    Rᵏ .= ...
end
```



## AD fallback
The default LRP fallback for unknown layers uses AD via [Zygote](https://github.com/FluxML/Zygote.jl).
For `lrp!`, we implement the previous four step computation using `Zygote.pullback` to
compute ``c`` from the previous equation as a VJP, pulling back ``s=R/z``:
```julia
function lrp!(Rᵏ, rule, layer, modified_layer, aᵏ, Rᵏ⁺¹)
   # Use modified_layer if available
   layer = isnothing(modified_layer) ? layer : modified_layer

   ãₖ = modify_input(rule, aᵏ)
   z, back = Zygote.pullback(modified_layer, ãₖ)
   s = Rᵏ⁺¹ ./ modify_denominator(rule, z)
   Rᵏ .= ãₖ .* only(back(s))
end
```

You can see how `modify_input` and `modify_denominator` dispatch on rule and layer types.
Unknown layers that are registered in the `LRP_CONFIG` use this exact function.

These functions in-place modify a pre-allocated array of the input relevance `Rᵏ`.
(The `!` is a [naming convention](https://docs.julialang.org/en/v1/manual/style-guide/#bang-convention)
in Julia to denote functions that modify their arguments.)

The correct rule is applied via [multiple dispatch](https://www.youtube.com/watch?v=kc9HwsxE1OY)
on the types of the arguments `rule` and `modified_layer`.
The relevance `Rᵏ` is then computed based on the input activation `aᵏ`
and the output relevance `Rᵏ⁺¹`.
Multiple dispatch is also used to dispatch `modify_parameters` and `modify_denominator`
on the rule and layer type.

## Specialized implementations
We can also implement specialized versions of `lrp!` based on the type of `layer`,
e.g. reshaping layers.

Reshaping layers don't affect attributions. We can therefore avoid the computational
overhead of AD by writing a specialized implementation that simply reshapes back:
```julia
function lrp!(Rᵏ, rule, _layer::ReshapingLayer, _modified_layer, aᵏ, Rᵏ⁺¹)
    Rᵏ .= reshape(Rᵏ⁺¹, size(aᵏ))
end
```

Since the rule type didn't matter in this case, we didn't specify it.

We can even implement the generic rule as a specialized implementation for `Dense` layers, since

```math
R_j^k = \sum_i \frac{w_{ij} a_j^k}{\sum_{l} w_{il} a_l^k + b_i} R_i^{k+1}
```

```julia
function lrp!(Rᵏ, rule, layer::Dense, modified_layer, aᵏ, Rᵏ⁺¹)
   # Use modified_layer if available
   layer = isnothing(modified_layer) ? layer : modified_layer

   ãₖ = modify_input(rule, aᵏ)
   z = modify_denominator(rule, layer(ãₖ))

   # Implement LRP using Einsum notation, where `b` is the batch index
   @tullio Rᵏ[j, b] = layer.weight[i, j] * ãₖ[j, b] / z[i, b] * Rᵏ⁺¹[i, b]
end
```


For maximum low-level control beyond `modify_input` and `modify_denominator`,
you can also implement your own `lrp!` function and dispatch
on individual rule types `MyRule` and layer types `MyLayer`:
```julia
function lrp!(Rᵏ, rule::MyRule, layer::MyLayer, _modified_layer, aᵏ, Rᵏ⁺¹)
    Rᵏ .= ...
end
```