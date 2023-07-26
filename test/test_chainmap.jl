using ExplainableAI: ChainTuple, ParallelTuple
using ExplainableAI: head_tail, chainmap, collect_activations
using ExplainableAI: activation_fn
using Flux

x = rand(Float32, 2, 5)
d1 = Dense(2, 2, relu)
d2 = Dense(2, 2, selu)
d3 = Dense(2, 2, gelu)
d4 = Dense(2, 2, celu)

c1 = Chain(d1)
c2 = Chain(d1, d2)
c3 = Chain(Chain(d1, d1), d2)
c4 = Chain(d1, Chain(d2, d2))
c5 = Chain(d1, Chain(d2, d2), d3)
c6 = Chain(Parallel(+, d1, d1))
c7 = Chain(d1, Parallel(+, d2, d2, Chain(d3, d3)), d4)

# pre-compute occuring hidden activations, where hXYZ = dX(dY(dZ(x))) = dX(hYZ)
h1 = d1(x)
h11 = d1(h1)
h21 = d2(h1)
h31 = d3(h1)
h211 = d2(h11)
h221 = d2(h21)
h3221 = d3(h221)
h331 = d3(d3(h1))
h4p1 = d4(2 * h21 + h331) # output of Chain c6

# Test head_tail
@test head_tail(1, 2, 3, 4) == (1, (2, 3, 4))
@test head_tail((1, 2, 3, 4)) == (1, (2, 3, 4))
@test head_tail([1, 2, 3, 4]) == (1, (2, 3, 4))
@test head_tail(1, (2, 3), 4) == (1, ((2, 3), 4))
@test head_tail(1) == (1, ())
@test head_tail() == ()
@test head_tail(c1) == (d1, ())
@test head_tail(c2) == (d1, (d2))
@test head_tail(c3) == (Chain(d1, d1), (d2))
@test head_tail(c4) == (d1, (Chain(d2, d2)))
@test head_tail(c5) == (d1, (Chain(d2, d2), d3))
@test head_tail(c6) == (Parallel(+, d1, d1), ())
@test head_tail(c7) == (d1, (Parallel(+, d2, d2, Chain(d3, d3)), d4))

# Test chainmap
@test chainmap(activation_fn, c1) == ChainTuple(relu)
@test chainmap(activation_fn, c2) == ChainTuple(relu, selu)
@test chainmap(activation_fn, c3) == ChainTuple(ChainTuple(relu, relu), selu)
@test chainmap(activation_fn, c4) == ChainTuple(relu, ChainTuple(selu, selu))
@test chainmap(activation_fn, c5) == ChainTuple(relu, ChainTuple(selu, selu), gelu)
@test chainmap(activation_fn, c6) == ChainTuple(ParallelTuple(relu, relu))
@test chainmap(activation_fn, c7) ==
    ChainTuple(relu, ParallelTuple(selu, selu, ChainTuple(gelu, gelu)), celu)

# Test collect_activations
coll(model) = collect_activations(model, x; collect_input=false)
@test coll(c1) == ChainTuple(h1)
@test coll(c2) == ChainTuple(h1, h21)
@test coll(c3) == ChainTuple(ChainTuple(h1, h11), h211)
@test coll(c4) == ChainTuple(h1, ChainTuple(h21, h221))
@test coll(c5) == ChainTuple(h1, ChainTuple(h21, h221), h3221)
@test coll(c6) == ChainTuple(ParallelTuple(h1, h1))
@test coll(c7) == ChainTuple(h1, ParallelTuple(h21, h21, ChainTuple(h31, h331)), h4p1)
