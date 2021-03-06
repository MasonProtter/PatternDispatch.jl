[![Build Status](https://travis-ci.com/MasonProtter/PatternDispatch.jl.svg?branch=master)](https://travis-ci.com/MasonProtter/PatternDispatch.jl)

# PatternDispatch.jl

To install, simply type
```
] add https://github.com/MasonProtter/PatternDispatch.jl.git
```
at the julia REPL.

__________


PatternDispatch.jl offers pattern matching through [Rematch.jl](https://github.com/RelationalAI-oss/Rematch.jl) but with
extensible, multiple-dispatch like semantics.
```julia
using PatternDispatch
@pattern fib(x) = fib(x-1) + fib(x-2)
@pattern fib(1) = 1
@pattern fib(0) = 0
```
```julia
julia> fib(10)
55
```
Now suppose I later decide I don't want a stack overflow every time I accidentally call `fib(-1)`, then I can just define
```julia
@pattern fib(x where x < 0) = error("Fib only takes positive inputs.")

```
```julia
julia> fib(-1)
ERROR: Fib only takes positive inputs.
```


Any valid Rematch.jl pattern can be used in a `@pattern` function signature, so you can write powerful destructuring code like
```julia
@pattern foo(x) = x
@pattern foo([x]) = x
@pattern foo((x,) where x < 1) = 1
@pattern foo((x,) where (x isa String || x > 1)) = x*x
@pattern foo(Expr(:call, [:+, a, b])) = a * b
```
```julia
julia> foo(1)
1

julia> foo([2])
2

julia> foo((0.5,))
1

julia> foo((1.5,))
2.25

julia> foo(("hi",))
"hihi"

julia> foo(:(3 + 2))
6
```
Pattern 'methods' are dispatched on in order of their specificity, so completely unconstrained patterns like
`@pattern f(x)` have the lowest precedence whereas exact value patterns like `@pattern f(1)` have highest precedence.
Constrained patterns like `@pattern f(x, y where y > x)` have intermediate precedence. For instance, the above function
`foo` has a function body like
```julia
foo(args...) = foo(Pattern, args...)

foo(::Type{Pattern}, args...) = @match args begin
    (Expr(:call, [:+, a, b]),)          => a * b
    ((x,) where x isa String || x > 1,) => x * x
    ((x,) where x isa String || x > 1,) => -1
    ((x,) where x < 1,)                 => 1
    ([x],)                              => x
    (x,)                                => x
end
```
where `@match` is from the Rematch.jl package.


### Adding pattern methods to functions you don't own

Suppose we want to add pattern matching methods to functions from other modules, e.g. we are annoyed that `sin(2π) != 0.0` and want to change it.
If we naively write
```julia
julia> @pattern Base.sin(x where x == 2π) = 0.0
sin (generic function with 13 methods)

julia> sin(2π)
-2.4492935982947064e-16
```
we don't get the result we might have expected. This is because overwriting the regular `sin(x)` method would be type piracy.
To avoid type piracy, PatternDispatch.jl created a method `sin(::Type{Pattern}, args...) = @match ...` but not an accompanying method
`sin(args...) = sin(Pattern, args...)`, so to access our new method we need to do
```julia
julia> sin(Pattern, 2π)
0.0
```
directly. 

## Known Gotcha's
- Due to an unfortunate implementation detail, pattern functions are all `@generated` functions, meaning that they
cannot return closures (there are workarounds to this, see the 'closures' testset in `tests/runteses.jl`).
- If you define a `@pattern` function in a local scope, you may get errors if you reference variables defined
in that scope, even the pattern function itself [ref](https://github.com/JuliaLang/julia/issues/34162).
