module PatternDispatch

export @pattern, Pattern

using Rematch: @match
using MacroTools: splitdef, striplines, postwalk


"""
Dictionary for storing all the function bodies. We'll need to modify them each time a new `@pattern` is declared. 
"""
const fdefs = Dict{Function, Expr}() 

macro pattern(fdef)
    d = splitdef(fdef)      # Produce a dictionary with the various components of the function: name, args, kwargs, where clause, body.
    m = Symbol(__module__)
    if d[:name] isa Symbol
        f = d[:name]        # Name of the function 
        mf = :($m.$f)       # ModuleName.FunctionName
    elseif d[:name] isa Expr && d[:name].head == :(.) #Check if function name is already of the form ModuleName.FunctionName
        f = d[:name].args[2].value
        m = d[:name].args[1]
        mf = d[:name]
    else
        error("Malformed function name")
    end
    body = d[:body]                 # Get function body.
    pat = Expr(:tuple, d[:args]...) # Get the function arguments as a tuple. This will be the pattern given to Rematch.jl
    
    matcher = :($pat => $body)      # Make a rule for rematch saying pat gets rewritten to body.
    qmatcher = Meta.quot(matcher)
    
    ef  = esc(f)
    em  = esc(m)
    emf = d[:name] == f ? esc(f) : esc(mf)

    qf = Meta.quot(f)
    eargs = esc(:args)

    startingfdef = Meta.quot(:(PatternDispatch.@match args begin
                                   $matcher
                               end) |> striplines)
    gname = gensym()
    quote
        if !(@isdefined($f)) && $(d[:name] == f)
            $ef($eargs...) = $ef(Pattern, $eargs...)
        end
        if !haskey(fdefs, $ef)
            fdefs[$ef] = $startingfdef
        elseif !(striplines($qmatcher) in striplines.(fdefs[$ef].args[4].args))
            pushfirst!(fdefs[$ef].args[4].args, $qmatcher)
        end
        sort!(fdefs[$ef].args[4].args, by=(x->(Pattern(x.args[2]))))
        @generated $(emf)(::Type{Pattern}, $(eargs)...) = fdefs[$ef]
        $ef
    end 
end

abstract type Pattern end 

struct Concrete <: Pattern  end

struct Struct <: Pattern  
    args::Tuple 
end 

struct Cond <: Pattern
    a
    b
end
struct Where <: Pattern  
    a
    c
end 

struct Isa  <: Pattern  end
struct Wild <: Pattern  end

# Concrete < Struct <  Where < Cond < Isa < Wild 

Base.isless(x::Pattern, y::Pattern) = begin
    @match (x, y) begin
    (Concrete(), _) => true
    (_, Concrete()) => false
    
    (Wild(), _) => false
    (_, Wild()) => true

    (Struct(t1), Struct(t2)) => length(t1) < length(t2) ? true : sum(isless.(t1, t2)) > sum((!isless).(t1,t2))
    (Struct(_), _) => true
    (_, Struct(_)) => false

    (Where(a1, c1), Where(a2, c2)) => isless(a1, a2) * isless(c1, c2)
    (Where(_,_), _) => true
    (_, Where(_,_)) => false

    (Cond(a1, b1), Cond(a2, b2)) => isless(a1, a2) * isless(b1, b2)
    (Cond(_,_), _) => true
    (_, Cond(_,_)) => false
    end
end

Pattern(x) = Concrete()
Pattern(::Symbol) = Wild()
function Pattern(ex::Expr)
    ex = striplines(ex)
    if ex.head == :where
        Where(Pattern(ex.args[1]), Pattern(ex.args[2]))
    elseif ex.head == :(::)
        Isa()
    elseif ex.head == :(&&) || ex.head == :(||)
        Cond(Pattern(ex.args[1]), Pattern(ex.args[2]))
    elseif string(ex.args[1])[1] == uppercase(string(ex.args[1])[1]) && length(ex.args) > 1
        Struct(Tuple(Pattern.(ex.args[2:end])))
    elseif ex.head == :tuple
        Struct(Tuple(Pattern.(ex.args)))
    else
        Wild()
    end
end


end # module
