
Presprover reasons about formulas of Presburger arithmetic over natural numbers.

Some example queries and their results:

```
?- valid(forall(x, exists(y, y > x))).
true.


?- valid(not(exists(x,
               exists(y,
                 exists(z, x > y /\ y > z /\ z > x))))). 
true.


?- valid(x < y ==> 10*x < 20*y).
true.


?- solution(X > 1_000_000_000 /\ Y > 10*X).
X = 1536870912,
Y = 16106127360 ;
X = 1536870912,
Y = 16106128384 ;
X = 1536870912,
Y = 16106127872 .
```

