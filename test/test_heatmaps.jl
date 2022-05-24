using ExplainableAI

# NOTE: Heatmapping assumes Flux's WHCN convention (width, height, color channels, batch size).
shape = (2, 2, 3, 1)
A = reshape(collect(Float32, 1:prod(shape)), shape)

shape = (2, 2, 3, 2)
batch = reshape(collect(Float32, 1:prod(shape)), shape)

reducers = [:sum, :maxabs, :norm]
rangescales = [:extrema, :centered]
for r in reducers
    for n in rangescales
        h = heatmap(A; reduce=r, rangescale=n)
        @test_reference "references/heatmaps/reduce_$(r)_rangescale_$(n).txt" h
        @test h ≈ heatmap(A; reduce=r, rangescale=n, unpack_singleton=false)[1]

        h = heatmap(batch; reduce=r, rangescale=n)
        @test_reference "references/heatmaps/reduce_$(r)_rangescale_$(n).txt" h[1]
        @test_reference "references/heatmaps/reduce_$(r)_rangescale_$(n)2.txt" h[2]
    end
end

@test_throws ArgumentError heatmap(A, reduce=:foo)
@test_throws ErrorException heatmap(A, rangescale=:bar)

B = reshape(A, 2, 2, 3, 1, 1)
@test_throws DomainError heatmap(B)
B = reshape(A, 2, 2, 3)
@test_throws DomainError heatmap(B)

A1 = rand(3, 3, 1)
A2 = ExplainableAI._reduce(A1, :sum)
@test A1 == A2