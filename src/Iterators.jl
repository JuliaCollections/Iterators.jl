module Iterators
using Base

import Base: start, next, done, count, take, eltype, length

export
    count,
    take,
    drop,
    cycle,
    repeated,
    chain,
    product,
    distinct,
    partition,
    groupby,
    imap,
    subsets,
    iterate

# convenience functions

haslength(x) = applicable(length,x)
all_have_length(xss) = all([haslength(xs) for xs in xss])

# Infinite counting

immutable Count{S<:Number}
    start::S
    step::S
end

eltype{S}(it::Count{S}) = S

count(start::Number, step::Number) = Count(promote(start, step)...)
count(start::Number)               = Count(start, one(start))
count()                            = Count(0, 1)

start(it::Count) = it.start
next(it::Count, state) = (state, state + it.step)
done(it::Count, state) = false


# Iterate through the first n elements

# L ∈ {true,false} indicates whether or not the wrapped iterator
# has a defined length

immutable Take{L,I}
    xs::I
    n::Int
end

eltype(it::Take) = eltype(it.xs)
length(it::Take{true}) = min(it.n, length(xs))

take(xs, n::Int) = Take{haslength(xs),typeof(xs)}(xs, n)

start(it::Take) = (it.n, start(it.xs))

function next(it::Take, state)
    n, xs_state = state
    v, xs_state = next(it.xs, xs_state)
    return v, (n - 1, xs_state)
end

function done(it::Take, state)
    n, xs_state = state
    return n <= 0 || done(it.xs, xs_state)
end


# Iterator through all but the first n elements

# L ∈ {true,false} indicates whether or not the wrapped iterator
# has a defined length

immutable Drop{L,I}
    xs::I
    n::Int
end

eltype(it::Drop) = eltype(it.xs)
length(it::Drop{true}) = max(length(it.xs)-it.n, 0)

drop(xs, n::Int) = Drop{haslength(xs),typeof(xs)}(xs, n)

function start(it::Drop)
    xs_state = start(it.xs)
    for i in 1:it.n
        if done(it.xs, xs_state)
            break
        end

        _, xs_state = next(it.xs, xs_state)
    end
    xs_state
end

next(it::Drop, state) = next(it.xs, state)
done(it::Drop, state) = done(it.xs, state)


# Cycle an iterator forever

immutable Cycle{I}
    xs::I
end

eltype(it::Cycle) = eltype(it.xs)

cycle(xs) = Cycle(xs)

function start(it::Cycle)
    s = start(it.xs)
    return s, done(it.xs, s)
end

function next(it::Cycle, state)
    s, d = state
    if done(it.xs, s)
        s = start(it.xs)
    end
    v, s = next(it.xs, s)
    return v, (s, false)
end

done(it::Cycle, state) = state[2]

# Repeat an object n (or infinitely many) times.

immutable Repeat{O}
    x::O
    n::Int
end

eltype{O}(it::Repeat{O}) = O
length(it::Repeat) = it.n

repeated(x, n) = Repeat(x, n)

@deprecate repeat(x, n) repeated(x, n)

start(it::Repeat) = it.n
next(it::Repeat, state) = (it.x, state - 1)
done(it::Repeat, state) = state <= 0


immutable RepeatForever{O}
    x::O
end

eltype{O}(r::RepeatForever{O}) = O

repeated(x) = RepeatForever(x)

@deprecate repeat(x) repeated(x)

start(it::RepeatForever) = nothing
next(it::RepeatForever, state) = (it.x, nothing)
done(it::RepeatForever, state) = false



# Concatenate the output of n iterators

# L ∈ {true,false} indicates whether or not the wrapped iterator
# has a defined length

immutable Chain{L}
    xss::Vector{Any}
    function Chain(xss...)
        new({xss...})
    end
end

function eltype(it::Chain)
    try
        typejoin([eltype(xs) for xs in it.xss]...)
    catch
        Any
    end
end
length(it::Chain{true}) = sum([length(x) for x in it.xss])

chain(xss...) = Chain{all_have_length(xss)}(xss...)

function start(it::Chain)
    i = 1
    xs_state = nothing
    while i <= length(it.xss)
        xs_state = start(it.xss[i])
        if !done(it.xss[i], xs_state)
            break
        end
        i += 1
    end
    return i, xs_state
end

function next(it::Chain, state)
    i, xs_state = state
    v, xs_state = next(it.xss[i], xs_state)
    while done(it.xss[i], xs_state)
        i += 1
        if i > length(it.xss)
            break
        end
        xs_state = start(it.xss[i])
    end
    return v, (i, xs_state)
end

done(it::Chain, state) = state[1] > length(it.xss)


# Cartesian product as a sequence of tuples

# L ∈ {true,false} indicates whether or not the wrapped iterator
# has a defined length

immutable Product{L}
    xss::Vector{Any}
    function Product(xss...)
        new({xss...})
    end
end

eltype(p::Product) = tuple(map(eltype, p.xss)...)
length(p::Product{true}) = prod(map(length, p.xss))

product(xss...) = Product{all_have_length(xss)}(xss...)

function start(it::Product)
    n = length(it.xss)
    js = {start(xs) for xs in it.xss}
    if n == 0
        return js, nothing
    end
    for i = 1:n
        if done(it.xss[i], js[i])
            return js, nothing
        end
    end
    vs = Array(Any, n)
    for i = 1:n
        vs[i], js[i] = next(it.xss[i], js[i])
    end
    return js, vs
end

function next(it::Product, state)
    js = copy(state[1])
    vs = copy(state[2])
    ans = tuple(vs...)

    n = length(it.xss)
    for i in 1:n
        if !done(it.xss[i], js[i])
            vs[i], js[i] = next(it.xss[i], js[i])
            break
        elseif i == n
            vs = nothing
            break
        end

        js[i] = start(it.xss[i])
        vs[i], js[i] = next(it.xss[i], js[i])
    end
    return ans, (js, vs)
end

done(it::Product, state) = state[2] === nothing


# Filter out reccuring elements.

immutable Distinct{I}
    xs::I

    # Map elements to the index at which it was first seen, so given an iterator
    # state (index) we can test if an element has previously been observed.
    seen::Dict{Any, Int}

    Distinct(xs) = new(xs, Dict{Any, Int}())
end

eltype(it::Distinct) = eltype(it.xs)

distinct{I}(xs::I) = Distinct{I}(xs)

function start(it::Distinct)
    start(it.xs), 1
end

function next(it::Distinct, state)
    s, i = state
    x, s = next(it.xs, s)
    it.seen[x] = i
    i += 1

    while !done(it.xs, s)
        y, t = next(it.xs, s)
        if !haskey(it.seen, y) || it.seen[y] >= i
            break
        end
        s = t
        i += 1
    end

    x, (s, i)
end

done(it::Distinct, state) = done(it.xs, state[1])


# Group output from at iterator into tuples.
# E.g.,
#   partition(count(1), 2) = (1,2), (3,4), (5,6) ...
#   partition(count(1), 2, 1) = (1,2), (2,3), (3,4) ...
#   partition(count(1), 2, 3) = (1,2), (4,5), (7,8) ...

# L ∈ {true,false} indicates whether or not the wrapped iterator
# has a defined length

immutable Partition{L,I}
    xs::I
    n::Int
    step::Int
end

eltype(it::Partition) = tuple(fill(eltype(it.xs),it.n)...)
length(it::Partition{true}) = iceil((length(it.xs)-(it.n-1))/it.step)

partition(xs, n::Int) = Partition{haslength(xs),typeof(xs)}(xs, n, n)

function partition(xs, n::Int, step::Int)
    if step < 1
        error("Partition step must be at least 1.")
    end

    Partition{haslength(xs),typeof(xs)}(xs, n, step)
end

function start(it::Partition)
    p = Array(eltype(it.xs), it.n)
    s = start(it.xs)
    for i in 1:(it.n - 1)
        if done(it.xs, s)
            break
        end
        (p[i], s) = next(it.xs, s)
    end
    (s, p)
end

function next(it::Partition, state)
    (s, p0) = state
    (x, s) = next(it.xs, s)
    ans = p0; ans[end] = x

    p = similar(p0)
    overlap = max(0, it.n - it.step)
    for i in 1:overlap
        p[i] = ans[it.step + i]
    end

    # when step > n, skip over some elements
    for i in 1:max(0, it.step - it.n)
        if done(it.xs, s)
            break
        end
        (x, s) = next(it.xs, s)
    end

    for i in (overlap + 1):(it.n - 1)
        if done(it.xs, s)
            break
        end

        (x, s) = next(it.xs, s)
        p[i] = x
    end

    (tuple(ans...), (s, p))
end

done(it::Partition, state) = done(it.xs, state[1])

# Group output from an iterator based on a key function.
# Consecutive entries from the iterator with the same 
# key value will be returned in a single array.
# Inspired by itertools.groupby in python.
# E.g.,
#   x = ["face", "foo", "bar", "book", "baz", "zzz"]
#   groupby(x, z -> z[1]) =
#       ["face", "foo"]
#       ["bar", "book", "baz"]
#       ["zzz"]
immutable GroupBy{I}
    xs::I
    keyfunc::Function
end

eltype{I}(it::GroupBy{I}) = I

function groupby(xs, keyfunc)
    GroupBy(xs, keyfunc)
end

function start(it::GroupBy)
    s = start(it.xs)
    prev_value = nothing
    prev_key = nothing
    return (s, (prev_key, prev_value))
end

function next(it::GroupBy, state)
    (s, (prev_key, prev_value)) = state
    values = Array(eltype(it.xs), 0)
    # We had a left over value from the last time the key changed.
    if prev_value != nothing || prev_key != nothing
        push!(values, prev_value)
    end
    prev_value = nothing
    while !done(it.xs, s)
        (x, s) = next(it.xs, s) 
        key = it.keyfunc(x)
        # Did the key change?
        if prev_key != nothing && key != prev_key
            prev_key = key
            prev_value = x
            break
        else
            push!(values, x) 
        end
        prev_key = key
    end
    # We either reached the end of the input or the key changed,
    # either way emit what we have so far.
    return (values, (s, (prev_key, prev_value)))
end

function done(it::GroupBy, state)
    return state[2][2] == nothing && done(it.xs, state[1])
end

# Like map, except returns the output as an iterator.  The iterator
# is done when any of the input iterators have been exhausted.
# E.g.,
#   imap(+, count(), [1, 2, 3]) = 1, 3, 5 ...
immutable IMap
    mapfunc::Base.Callable
    xs::Vector{Any}
end

function imap(mapfunc, it1, its...)
    IMap(mapfunc, {it1, its...})    
end 

function start(it::IMap)
    map(start, it.xs)
end

function next(it::IMap, state)
    next_result = map(next, it.xs, state)
    return (
        it.mapfunc(map(x -> x[1], next_result)...),
        map(x -> x[2], next_result)
    )
end

function done(it::IMap, state)
    any(map(done, it.xs, state))
end


# Iterate over all subsets of a collection

immutable Subsets
    xs
end

eltype(it::Subsets) = Array{eltype(it.xs),1}
length(it::Subsets) = 1 << length(it.xs)

subsets(xs) = Subsets(xs)

function start(it::Subsets)
    # one extra bit to indicated that we are at the end
    BitVector(length(it.xs) + 1)
end

function next(it::Subsets, state)
    ss = Array(eltype(it.xs), 0)
    for i = 1:length(it.xs)
        if state[i]
            push!(ss, it.xs[i])
        end
    end

    state = copy(state)
    state[1] = !state[1]
    for i in 2:length(state)
        if !state[i-1]
            state[i] = !state[i]
        else
            break
        end
    end

    (ss, state)
end

function done(it::Subsets, state)
    state[end]
end

# Unfolding (anamorphism)
# Outputs the stream: seed, f(seed), f(f(seed)), ...

immutable Iterate{T}
    f::Function
    seed::T
end

iterate(f, seed) = Iterate(f, seed)
start(it::Iterate) = it.seed
next(it::Iterate, state) = (state, it.f(state))
done(it::Iterate, state) = (state==None)

end # module Iterators

