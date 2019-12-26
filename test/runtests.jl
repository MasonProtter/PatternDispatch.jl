using Test, PatternDispatch


@pattern fib(x) = fib(x-1) + fib(x-2)
@pattern fib(1) = 1
@pattern fib(0) = 0

fib2(n::Int) = n < 2 ? n : fib2(n-1) + fib2(n-2)

@testset "fib               " begin
    @test fib(30) == fib2(30)

    @pattern fiblocal(x) = fiblocal(x-1) + fiblocal(x-2)
    @pattern fiblocal(1) = 1
    @pattern fiblocal(0) = 0

    @test_broken fiblocal(30) == fiblocal(30)
end

closer(x) = y -> x + y
@testset "closures          " begin
    @pattern foo(x) = y -> y + x
    @pattern bar(x) = closer(x)
    @test_broken foo(1)(2) == 3
    @test        bar(1)(2) == 3
end

@testset "destructure       " begin
    @pattern foo(x) = x
    @pattern foo([x]) = x
    @pattern foo((x,) where x < 1) = 1
    @pattern foo((x,) where (x isa String || x > 1)) = -1
    
    @test foo(1) == 1
    @test foo([2]) == 2
    @test foo((0.5,)) == 1
    @test foo((1.5,)) == -1
    @test foo(("hi",)) == -1
end

using PatternDispatch: Pattern, Concrete, Struct, Where, Cond, Isa, Wild
@testset "Signature Sorting " begin
    sigs = [:x,
            1,
            :(x, y where y > x),
            :([1 2; 3 4], y where all(y .> x)),
            :(z::Int),
            :(_::Int || (y where -1 < y < 2)::Float64)]

    @test Pattern.(sigs) == [Wild(),                                                                                                                                                   
                             Concrete(),                                                                                                                                               
                             Struct((Wild(), Where(Wild(), Struct((Wild(), Wild()))))),
                             Struct((Where(Wild(), Wild()),)),                                                                         
                             Isa(),                                                                                                                                                    
                             Cond(Isa(), Isa())]

    @test sort(sigs, by=Pattern) == [1,                                          
                                     :(([1 2; 3 4], y where all(y .> x))),     
                                     :((x, y where y > x)),                     
                                     :(_::Int || (y where -1 < y < 2)::Float64),
                                     :(z::Int),                                 
                                     :x]
end


module M1
using PatternDispatch
@pattern foo(x) = x + 1
end

module M2
using PatternDispatch
@pattern foo(x) = x - 1
end

using .M1, .M2


module M3
using PatternDispatch
using Main.M1: foo
@pattern Main.M1.foo(2) = "hi"
end

using .M3

@testset "Module namespacing" begin
    @test M1.foo(1) != M2.foo(1)
    @test M3.foo(2) == "hi"
    @test M3.foo(1) == 2
end

let
    @pattern bar(1) = 2
end
@testset "Lexical scoping   " begin
    @pattern bar(x) = x
    @test bar(1) == 1
end


@pattern Base.sin(x)               = sin(x)
@pattern Base.sin(x where x == 2π) = 0.0

@testset "Avoiding piracy   " begin
    @test sin(2π)          != 0.0
    @test sin(Pattern, 2π) == 0.0
    @test sin(52.3)        == sin(Pattern, 52.3)
end
