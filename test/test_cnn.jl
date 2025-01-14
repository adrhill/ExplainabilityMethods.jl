using ExplainableAI
using Zygote
using Test
using ReferenceTests

using Flux
using Random
using StableRNGs: StableRNG
using JLD2

const GRADIENT_ANALYZERS = Dict(
    "InputTimesGradient"  => InputTimesGradient,
    "SmoothGrad"          => m -> SmoothGrad(m, 5, 0.1, StableRNG(123)),
    "IntegratedGradients" => m -> IntegratedGradients(m, 5),
    "GradCAM"             => m -> GradCAM(m[1], m[2]),
)

pseudorand(dims...) = rand(StableRNG(123), Float32, dims...)

input_size = (32, 32, 3, 1)
input = pseudorand(input_size)

init(dims...) = Flux.glorot_uniform(StableRNG(123), dims...)

model = Chain(
    Chain(
        Conv((3, 3), 3 => 8, relu; pad=1, init=init),
        Conv((3, 3), 8 => 8, relu; pad=1, init=init),
        MaxPool((2, 2)),
        Conv((3, 3), 8 => 16, relu; pad=1, init=init),
        Conv((3, 3), 16 => 16, relu; pad=1, init=init),
        MaxPool((2, 2)),
    ),
    Chain(
        Flux.flatten,
        Dense(1024 => 512, relu; init=init),
        Dropout(0.5),
        Dense(512 => 100, relu; init=init),
    ),
)
Flux.testmode!(model, true)

@testset "Test API" begin
    analyzer = Gradient(model)
    println("Timing Gradient...")
    print("cold:")
    @time expl = analyze(input, analyzer)

    # Test direct call of analyzer
    print("warm:")
    @time expl2 = analyzer(input)
    @test expl.val ≈ expl2.val

    @test_reference "references/cnn/Gradient_max.jld2" Dict("expl" => expl.val) by =
        (r, a) -> isapprox(r["expl"], a["expl"]; rtol=0.05)

    # Test neuron selection
    expl = analyze(input, analyzer, 1)
    expl2 = analyzer(input, 1)
    @test expl.val ≈ expl2.val
    @test_reference "references/cnn/Gradient_ns1.jld2" Dict("expl" => expl.val) by =
        (r, a) -> isapprox(r["expl"], a["expl"]; rtol=0.05)
end

function test_cnn(name, method)
    @testset "$name" begin
        @testset "Max activation" begin
            # Reference test explanation
            analyzer = method(model)
            println("Timing $name...")
            print("cold:")
            @time expl = analyze(input, analyzer)
            @test_reference "references/cnn/$(name)_max.jld2" Dict("expl" => expl.val) by =
                (r, a) -> isapprox(r["expl"], a["expl"]; rtol=0.05)
        end
        @testset "Neuron selection" begin
            analyzer = method(model)
            print("warm:")
            @time expl = analyze(input, analyzer, 1)
            @test_reference "references/cnn/$(name)_ns1.jld2" Dict("expl" => expl.val) by =
                (r, a) -> isapprox(r["expl"], a["expl"]; rtol=0.05)
        end
    end
end

# Run analyzers
@testset "Gradient analyzers" begin
    for (name, method) in GRADIENT_ANALYZERS
        test_cnn(name, method)
    end
end
