using BenchmarkTools
using LoopVectorization
using Flux
using ExplainableAI
using ExplainableAI: lrp!, modify_layer

on_CI = haskey(ENV, "GITHUB_ACTIONS")

input_size = (32, 32, 3, 1)

model = Chain(
    Chain(
        Conv((3, 3), 3 => 8, relu; pad=1),
        Conv((3, 3), 8 => 8, relu; pad=1),
        MaxPool((2, 2)),
        Conv((3, 3), 8 => 16, relu; pad=1),
        Conv((3, 3), 16 => 16, relu; pad=1),
        MaxPool((2, 2)),
    ),
    Chain(
        Flux.flatten,
        Dense(1024 => 512, relu),         # 102_764_544 parameters
        Dropout(0.5),
        Dense(512 => 100, relu),
    ),
)
Flux.testmode!(model, true)

T = Float32
input = rand(MersenneTwister(123), T, input_size)

# Use one representative algorithm of each type
algs = Dict(
    "Gradient"            => Gradient,
    "InputTimesGradient"  => InputTimesGradient,
    "LRP"                 => LRP,
    "LREpsilonPlusFlat"   => model -> LRP(model, EpsilonPlusFlat()),
    "SmoothGrad"          => model -> SmoothGrad(model, 5),
    "IntegratedGradients" => model -> IntegratedGradients(model, 5),
)

# Define benchmark
_alg(alg, model) = alg(model) # for use with @benchmarkable macro

SUITE = BenchmarkGroup()
SUITE["VGG11"] = BenchmarkGroup([k for k in keys(algs)])
for (name, alg) in algs
    analyzer = alg(model)
    SUITE["VGG11"][name] = BenchmarkGroup(["construct analyzer", "analyze"])
    SUITE["VGG11"][name]["construct analyzer"] = @benchmarkable _alg($(alg), $(model))
    SUITE["VGG11"][name]["analyze"] = @benchmarkable analyze($(input), $(analyzer))
end

# generate input for conv layers
insize = (64, 64, 3, 1)
in_dense = 500
out_dense = 100
aₖ = randn(T, insize)

#! format: off
layers = Dict(
    "Conv"  => (Conv((3, 3), 3 => 2), aₖ),
    "Dense" => (Dense(in_dense, out_dense, relu), randn(T, in_dense, 1)),
)
rules = Dict(
    "ZeroRule"      => ZeroRule(),
    "EpsilonRule"   => EpsilonRule(),
    "GammaRule"     => GammaRule(),
    "WSquareRule"   => WSquareRule(),
    "FlatRule"      => FlatRule(),
    "AlphaBetaRule" => AlphaBetaRule(),
    "ZPlusRule"     => ZPlusRule(),
    "ZBoxRule"      => ZBoxRule(zero(T), oneunit(T)),
)
layernames = String.(keys(layers))
rulenames  = String.(keys(rules))
#! format: on

SUITE["modify layer"] = BenchmarkGroup(rulenames)
SUITE["apply rule"]   = BenchmarkGroup(rulenames)
for rname in rulenames
    SUITE["modify layer"][rname] = BenchmarkGroup(layernames)
    SUITE["apply rule"][rname] = BenchmarkGroup(layernames)
end

for (lname, (layer, aₖ)) in layers
    Rₖ = similar(aₖ)
    Rₖ₊₁ = layer(aₖ)
    for (rname, rule) in rules
        modified_layer = modify_layer(rule, layer)
        SUITE["modify layer"][rname][lname] = @benchmarkable modify_layer($(rule), $(layer))
        SUITE["apply rule"][rname][lname] = @benchmarkable lrp!(
            $(Rₖ), $(rule), $(layer), $(modified_layer), $(aₖ), $(Rₖ₊₁)
        )
    end
end
