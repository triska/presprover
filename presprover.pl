/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  Presprover -- Prove formulas of Presburger arithmetic
  Copyright (C) 2005, 2014 Markus Triska triska@gmx.at

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

  http://www.logic.at/prolog/presprover/presprover.html

  Cf.: Constraint Solving on Terms, H. Comon and C. Kirchner
  published in: "Constraints in Computational Logics", Springer 2001
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

   Presprover reasons about Presburger arithmetic over natural numbers.

   Arithmetic expressions are:

        integer : given number
       variable : a variable in Presburger arithmetic
         atom   : likewise, a variable in Presburger arithmetic
         -E     : unary minus
        E + E   : addition
        E * E   : multiplication (not admissible with variables in both
                  arguments)
        E - E   : subtraction

   where E again denotes an arithmetic expression.

   Relations between arithmetic expressions E1 and E2 are:

       E1  = E2 : E1 is equal to E2
       E1  > E2 : E1 is greater than E2
       E1  < E2 : E1 is less than E2
       E1 =< E2 : E1 is less than or equal to E2
       E1 >= E2 : E1 is greater than or equal to E2

   Formulas are, in addition to the relations above:

        not(F)   : True iff F is not true.
    exists(V, F) : V must be a Prolog atom or variable. True if there exists
                   a natural number N such that F with N substituted for V
                   is true.
    forall(V, F) : Equivalent to not(exists(V, not(F))).
        A /\ B   : Conjunction. True iff both A and B are true.
        A \/ B   : Disjunction. True iff either A or B, or both, are true.
        A ==> B  : Implication. Equivalent to not(A) \/ B.

   Use valid/1 and satisfiable/1 to check given formulas.

   Some example queries and their results:

      ?- valid(x > 0).
      false.

      ?- satisfiable(x > 0).
      true .

      ?- valid(x >= 0).
      true.

      ?- valid(exists(x, x > 0)).
      true.

      ?- valid(forall(x, exists(y, 3*x + y > 2))).
      true.

      ?- valid(2*y + 3*x = 30 /\ x = 0 ==> y = 15).
      true.

      ?- valid(x = 3 \/ not(x=3)).
      true.

      ?- valid(x = 5 ==> 2*x = 10).
      true.

      ?- valid(y > 1 /\ x = 3 /\ x + y < 19 ==> x + 19 > y).
      true.

   You can use solution/1 to print solutions of satisfiable formulas:

      ?- solution(x > 100_000 /\ y = 20).
      x=116384.
      y=20.
      true .

   For logical variables, solutions are reported as variable bindings:

      ?- solution(X > 1_000_000_000 /\ Y > 10*X).
      X = 1536870912,
      Y = 16442450944 ;
      X = 1536870912,
      Y = 16442449920 ;
      X = 1536870912,
      Y = 16442450432 ;
      etc.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

:- module(presprover, [
                       op(750, yfx, /\),
                       op(751, yfx, \/),
                       op(760, xfy, ==>),
                       valid/1,
                       satisfiable/1,
                       solution/1
                      ]).

:- use_module(library(clpfd)).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   An automaton is represented as:

      aut(Qs,QFs,Q0,Delta) where
         Qs: list of all states
         QFs: list of accepting (= final) states
         Q0: initial state
         Delta: a list of transitions of the form delta(Q0,Symbol,Q)

   The automaton can either be deterministic or not. The symbol
   'epsilon' is used to denote transitions that can be taken without
   consuming anything.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

empty_automaton(aut(_,QFs,Q0,Delta)) :-
        delta_to_assoc(Delta, DA),
        states_closure([Q0], DA, States),
        \+ ( member(S, States), member(S, QFs) ).

states_closure(States0, DA, States) :-
        states_nexts(States0, DA, Nexts),
        append_sort(States0, Nexts, States1),
        (   States0 == States1 -> States = States0
        ;   states_closure(States1, DA, States)
        ).

states_nexts(States, DA, Nexts) :-
        phrase(states_nexts_(States,DA), Nexts0),
        sort(Nexts0, Nexts).

states_nexts_([], _) --> [].
states_nexts_([Q|Qs], DA) -->
        { state_nexts(Q, DA, Nexts),
          pairs_values(Nexts, States) },
        list(States),
        states_nexts_(Qs, DA).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Convert a list of transitions to an association table where each
   state is a key, associated to a list of pairs Symbol-NextState.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

delta_to_assoc(Delta, DA) :-
        maplist(delta_pair, Delta, Ps0),
        keysort(Ps0, Ps),
        group_pairs_by_key(Ps, Groups),
        empty_assoc(DA0),
        foldl(register_delta, Groups, DA0, DA).

delta_pair(delta(Q0,S,Q), Q0-(S-Q)).

register_delta(State-Pairs, DA0, DA) :-
        put_assoc(State, DA0, Pairs, DA).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                               Equality
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */


eq_automaton(Coeffs, Sum, Aut) :-
        Q0 = q(Sum),
        list_to_assoc([Q0-true], AQ0),
        saturate_eq([Q0], Coeffs, AQ0, AQ, [], Delta),
        assoc_to_list(AQ, PQs),
        pairs_keys(PQs, Qs),
        sort(Delta, Delta1),
        (   get_assoc(q(0), AQ, true) ->
            QFs = [q(0)]
        ;   QFs = []
        ),
        Aut = aut(Qs, QFs, Q0, Delta1).


saturate_eq([], _, AQ, AQ, D, D).
saturate_eq([q(C)|QIterRest], Coeffs, AQ0, AQ, Delta0, Delta) :-
        eq_mod2(Coeffs, C, Tuples),
        maplist(eq_tuple_newstate(Coeffs,C), Tuples, NewStates),
        maplist(state_tuple_delta(q(C)), NewStates, Tuples, NewDeltas),
        append(Delta0, NewDeltas, Delta1),
        append_without(QIterRest, NewStates, AQ0, QIters),
        foldl(register_state, NewStates, AQ0, AQ1),
        saturate_eq(QIters, Coeffs, AQ1, AQ, Delta1, Delta).

state_tuple_delta(Q, S, T, delta(Q,T,S)).

register_state(State, AQ0, AQ) :- put_assoc(State, AQ0, true, AQ).

factor_mod2(C0, C) :- C #= abs(C0 mod 2).

eq_mod2(Coeffs0, C0, Tuples) :-
        C #= abs(C0 mod 2),
        maplist(factor_mod2, Coeffs0, Coeffs),
        same_length(Coeffs, Vs),
        Vs ins 0..1,
        scalar_product(Coeffs, Vs, #=, S),
        findall(Vs, (S mod 2 #= C, label(Vs)), Tuples).


eq_tuple_newstate(Coeffs, C, Tuple, q(D)) :-
        scalar_product(Coeffs, Tuple, #=, Sum),
        D #= (C - Sum) // 2.

append_without(As, Bs0, Without, Cs) :-
        exclude(in_assoc(Without), Bs0, Bs),
        append(As, Bs, Cs).

in_assoc(Assoc, X) :- get_assoc(X, Assoc, _).

:- initialization((list_to_assoc([7-true], A), append_without([1,2,3], [7,8], A, [1,2,3,8]))).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                              Inequality
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

ineq_automaton(Coeffs, Sum, A) :-
        Q0 = q(Sum),
        same_length(Coeffs, Thetas),
        Thetas ins 0..1,
        findall(Thetas, label(Thetas), Tuples),
        list_to_assoc([Q0-true], AQ0),
        saturate_ineq([Q0], Coeffs, Tuples, AQ0, AQ, [], Delta0),
        assoc_to_list(AQ, PQs),
        pairs_keys(PQs, Qs),
        sort(Delta0, Delta),
        include(state_geq_zero, Qs, QFs),
        A = aut(Qs, QFs, Q0, Delta).

state_geq_zero(q(N)) :- N #>= 0.

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   compute D as floor((C-Sum)/2), without resorting to floating point
   numbers to avoid overflow and precision problems.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

ineq_tuple_newstate(Coeffs, C, Tuple, q(D)) :-
        scalar_product(Coeffs, Tuple, #=, Sum),
        D0 #= (C-Sum) // 2,
        (   (C-Sum) < 0 -> D #= D0 + (C-Sum) rem 2
        ;   D = D0
        ).

saturate_ineq([], _, _, AQ, AQ, Delta, Delta).
saturate_ineq([q(C)|QIterRest], Coeffs, Tuples, AQ0, AQ, Delta0, Delta) :-
        maplist(ineq_tuple_newstate(Coeffs,C), Tuples, NewStates),
        maplist(state_tuple_delta(q(C)), NewStates, Tuples, NewDeltas),
        append(NewDeltas, Delta0, Delta1),
        append_without(QIterRest, NewStates, AQ0, QIters),
        foldl(register_state, NewStates, AQ0, AQ1),
        saturate_ineq(QIters, Coeffs, Tuples, AQ1, AQ, Delta1, Delta).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                     Intersection of two automata
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

aut_intersection(NA1, NA2, I) :-
        ndfa_dfa(NA1, aut(Qs1,QFs1,S1,Delta1)),
        ndfa_dfa(NA2, aut(Qs2,QFs2,S2,Delta2)),
        phrase(lists_pairs(Qs1, Qs2), Qs),
        delta_to_assoc(Delta1, AD1),
        delta_to_assoc(Delta2, AD2),
        intersec_delta(Qs, AD1, AD2, Delta),
        include(intersec_ishalting(QFs1,QFs2), Qs, QFs),
        I0 = aut(Qs,QFs,S1-S2,Delta),
        aut_minimal(I0, I).

lists_pairs([], _) --> [].
lists_pairs([A|As], Bs) --> list_pairs_(Bs, A), lists_pairs(As, Bs).

list_pairs_([], _)     --> [].
list_pairs_([B|Bs], A) --> [A-B], list_pairs_(Bs, A).


intersec_ishalting(QFs1, QFs2, A-B) :-
        memberchk(A, QFs1),
        memberchk(B, QFs2).

:- initialization(intersec_ishalting([q(0),q(1)],[q(0)], q(1)-q(0))).

intersec_delta([], _, _, []).
intersec_delta([Q|Qs], AD1, AD2, Ds) :-
        Q = Q1-Q2,
        state_nexts(Q1, AD1, Nexts1),
        state_nexts(Q2, AD2, Nexts2),
        findall(delta(Q,S,E1-E2),
                (   member(S-E1, Nexts1),
                    member(S-E2, Nexts2)),
                Ds, RestDeltas),
        intersec_delta(Qs, AD1, AD2, RestDeltas).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                        Union of two automata
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

aut_union(A1, A2, U) :-
        aut_rename(1, A1, A11),
        aut_rename(2, A2, A22),
        A11 = aut(Q1,QFs1,S1,Delta1),
        A22 = aut(Q2,QFs2,S2,Delta2),
        append(Q1, Q2, Allstates),
        length(Allstates, N),
        Q0 = start(N),
        Trans1 = [delta(Q0,epsilon,S1),delta(Q0,epsilon,S2)|Delta2],
        append_sort(Delta1, Trans1, Trans2),
        append_sort([start(N)|Q1], Q2, Qs),
        append_sort(QFs1, QFs2, QFs),
        U = aut(Qs,QFs,Q0,Trans2).

state_rename(N, P, n(N,P)).

delta_rename(N, delta(A0,Trans,B0), delta(A,Trans,B)) :-
        state_rename(N, A0, A),
        state_rename(N, B0, B).


aut_rename(Num, Aut0, Aut) :-
        Aut0 = aut(Qs0, QFs0, Q00, Delta0),
        maplist(state_rename(Num), Qs0, Qs),
        maplist(state_rename(Num), QFs0, QFs),
        maplist(delta_rename(Num), Delta0, Delta),
        state_rename(Num, Q00, Q0),
        Aut = aut(Qs, QFs, Q0, Delta).

append_sort(As, Bs, Cs) :-
        append(As, Bs, Cs0),
        sort(Cs0, Cs).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                        NDFA -> DFA conversion
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

is_deterministic(aut(_Qs,_QFs,_Q0,Delta)) :-
        \+ memberchk(delta(_,epsilon,_), Delta),
        \+ exists_choicepath(Delta).

exists_choicepath(Delta) :-
        delta_to_assoc(Delta, DA),
        member(delta(Q0,Seq,Q1), Delta),
        state_nexts(Q0, DA, Nexts),
        member(Seq-Q2, Nexts),
        Q1 \== Q2.

state_table(Alphabet, DA, Q, Table) :-
        maplist(state_reachables(Q,DA), Alphabet, Rss),
        maplist(transform_table(Q), Alphabet, Rss, Table).

transform_table(Q, A, Rs, t(Q,A,Rs)).

ndfa_alphabet_table(aut(Qs,_QFs,_Q0,Delta), Alphabet, Table) :-
        delta_alphabet(Delta, Alphabet),
        delta_to_assoc(Delta, DA),
        maplist(state_table(Alphabet,DA), Qs, Tables),
        append(Tables, Table).

symbol_union(Table, Qs, A, u(Qs,A,Us)) :-
        phrase(symbol_union_(Qs,Table,A), Us0),
        sort(Us0, Us).

symbol_union_([], _, _) --> [].
symbol_union_([Q|Qs], Table, A) -->
        { memberchk(t(Q,A,Rs), Table) },
        list(Rs),
        symbol_union_(Qs, Table, A).

test_table(1, [t(q0, 0, [q0, q1, q2]), t(q0, 1, [q1, q2]), t(q0, 2, [q2]), t(q1, 0, []),t(q1, 1, [q1, q2]), t(q1, 2, [q2]), t(q2, 0, []), t(q2, 1, []), t(q2, 2, [q2])]).

list([]) --> [].
list([E|Es]) --> [E], list(Es).

:- initialization((test_table(1, T), symbol_union(T,[q1,q2],1,u([q1,q2],1,[q1,q2])))).

% final state in DFA: if one of its "sub"-states is final in NDFA
is_dfafinal(Fs, d(Qs)) :-
        member(Q, Qs),
        memberchk(Q, Fs).

dfa_transform_table(u(Qs,A,Rs), delta(d(Qs),A,d(Rs))).

can_reach_final_from_start(Q0, QFs, Delta) :-
        delta_to_assoc(Delta, DA),
        states_epsilon_closure([Q0], DA, Cs),
        member(State, Cs),
        memberchk(State, QFs).

ndfa_dfa(NDFA, DFA) :-
        (   is_deterministic(NDFA) -> DFA0 = NDFA
        ;   NDFA = aut(_,QFs,Q0,Delta),
            ndfa_alphabet_table(NDFA, Alphabet, Table),
            maplist(symbol_union(Table,[Q0]), Alphabet, Us0),
            empty_assoc(Lookup0),
            register_firsts(Us0, Lookup0, Lookup),
            saturate_det_table(Alphabet, Table, Lookup, Us0, Us),
            maplist(dfa_transform_table, Us, DFADelta),
            delta_states(DFADelta, DFAStates0),
            sort([d([Q0])|DFAStates0], DFAStates),
            include(is_dfafinal(QFs), DFAStates, DFAFinals0),
            (   can_reach_final_from_start(Q0, QFs, Delta) ->
                DFAFinals1 = [d([Q0])|DFAFinals0]
            ;   DFAFinals1 = DFAFinals0
            ),
            sort(DFAFinals1, DFAFinals),
            DFA0 = aut(DFAStates,DFAFinals,d([Q0]),DFADelta)
        ),
        aut_minimal(DFA0, DFA).

u_first(u(Q,_,_), Q).

register_firsts(Us, Lookup0, Lookup) :-
        maplist(u_first, Us, Firsts),
        foldl(register_state, Firsts, Lookup0, Lookup).

dettable_notcovered(Lookup, Us, Q) :-
        member(u(_,_,Q), Us),
        \+ in_assoc(Lookup, Q).

saturate_det_table(Alphabet, Table, Lookup0, Us0, Us) :-
        (   dettable_notcovered(Lookup0, Us0, Qs) ->
            maplist(symbol_union(Table,Qs), Alphabet, Us1),
            register_firsts(Us1, Lookup0, Lookup),
            append(Us0, Us1, Us2),
            saturate_det_table(Alphabet, Table, Lookup, Us2, Us)
        ;   Us0 = Us
        ).




test_ndfa(1, aut([q0,q1,q2],[q2],q0,[delta(q0,0,q0),delta(q0,epsilon,q1),delta(q1,1,q1),delta(q1,epsilon,q2),delta(q2,2,q2)])).

%?- test_ndfa(1, aut(_,_,_,Delta)), delta_to_assoc(Delta, DA), states_epsilon_closure([q0],DA,Cs).

%?- test_ndfa(1, Aut), ndfa_dfa(Aut, DFA).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   All states that can be reached solely through epsilon transitions
   from a given set of states States0.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

states_epsilon_closure(States0, DA, States) :-
        symbol_step(States0, DA, epsilon, States1),
        append_sort(States0, States1, States2),
        (   States0 == States2 -> States = States0
        ;   states_epsilon_closure(States2, DA, States)
        ).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   All states that are reachable via symbol A and epsilon transitions.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

state_reachables(State0, DA, A, States) :-
        states_epsilon_closure([State0], DA, States0),
        symbol_step(States0, DA, A, States1),
        states_epsilon_closure(States1, DA, States).

symbol_step(States0, DA, A, States) :-
        phrase(symbol_step_(States0, DA, A), States).

symbol_step_([], _, _) --> [].
symbol_step_([Q|Qs], DA, A) -->
        { state_nexts(Q, DA, Nexts0),
          include(first_is(A), Nexts0, Nexts),
          pairs_values(Nexts, States) },
        list(States),
        symbol_step_(Qs, DA, A).

state_nexts(Q, DA, Nexts) :-
        (   get_assoc(Q, DA, Nexts) -> true
        ;   Nexts = []
        ).

first_is(X, X-_).


delta_alphabet(Delta, As) :-
        findall(A, (member(delta(_,A,_),Delta), A \= epsilon), As1),
        sort(As1, As).

delta_states(Delta, Qs) :-
        findall(Q, member(delta(Q,_,_),Delta), Qs1),
        findall(R, member(delta(_,_,R),Delta), Qs2),
        append_sort(Qs1, Qs2, Qs).


:- initialization(delta_alphabet([delta(a,1,b),delta(c,2,d),delta(f,2,g),delta(2,epsilon,5)],[1,2])).

:- initialization(delta_states([delta(a,1,b),delta(c,2,d),delta(f,2,g),delta(2,epsilon,5)],[2,5,a,b,c,d,f,g])).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                       Complement of automaton
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

aut_complement(Aut, Complement) :-
        ndfa_dfa(Aut, DFA),
        DFA = aut(DQs,DQFs,DQ0,Delta),
        (   Delta == [] ->
            (   memberchk(DQ0, DQFs) ->
                Complement = aut(DQs,[],DQ0,[])
            ;   Complement = aut(DQs,[DQ0|DQFs],DQ0,[])
            )
        ;   Delta = [delta(_,Seq,_)|_],
            same_length(Seq, Bits),
            Bits ins 0..1,
            findall(Bits, label(Bits), Binaries),
            aut_complete(Binaries, DFA, aut(Qs,QFs,Q0,CompleteDelta)),
            list_delete(QFs, Qs, CFinals0),
            exclude(pseudo_final_state(QFs,CompleteDelta), CFinals0, CFinals1),
            (   exists_path(Q0, Delta) -> CFinals = CFinals1
            ;   delete(CFinals1, Q0, CFinals)
            ),
            Complement = aut(Qs,CFinals,Q0,CompleteDelta)
        ).

complete_states([], _Alphabet, _Trap, _Delta) --> [].
complete_states([Q|Qs], Alphabet, Trap, Delta) -->
        complete_state(Alphabet, Q, Trap, Delta),
        complete_states(Qs, Alphabet, Trap, Delta).

complete_state([], _Q, _Trap, _Delta) --> [].
complete_state([A|As], Q, Trap, Delta) -->
        (   { member(delta(Q,A,_), Delta) } -> []
        ;   [delta(Q,A,Trap)]
        ),
        complete_state(As, Q, Trap, Delta).

:- initialization((phrase(complete_state([1,2],a,trap,[delta(a,1,b)]), Cs), Cs = [delta(a, 2, trap)])).

trapdelta(Trap, A, delta(Trap,A,Trap)).

% complete an automaton with respect to a given alphabet
aut_complete(Alphabet, aut(Qs0,QFs,Q0,Delta0), aut(Qs,QFs,Q0,Delta)) :-
        length(Qs0, LQs),
        Trap = trap(LQs),
        phrase(complete_states(Qs0,Alphabet,Trap,Delta0), Delta1, Delta0),
        sort(Delta1, Delta2), % remove duplicates
        maplist(trapdelta(Trap), Alphabet, TrapDeltas),
        append_sort(Delta2, TrapDeltas, Delta),
        delta_states(Delta, Qs).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   There is a slight subtlety involved when building the complement,
   resulting from the ambiguity of number representation: an arbitrary
   amount of zeros can be appended - therefore, we can not turn a
   state into a final state if an *actual* final state can be reached
   via zeros. I call this a "pseudo"-final state. Also, the initial
   state can only turn into a halting state if there exists a proper
   path to it (that makes sense in terms of the accepted number), or
   the problem is already reduced to reachability.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

pseudo_final_state(QFs, Delta, Q) :-
        can_reach_final_through_0(Q, QFs, Delta).

can_reach_final_through_0(Q, QFs, Delta) :-
        can_reach_final_through_0(Q, QFs, Delta, []).

can_reach_final_through_0(Q, QFs, _Delta, _Visited) :-
        memberchk(Q, QFs).
can_reach_final_through_0(Q, QFs, Delta, Visited) :-
        member(delta(Q,Seq,R), Delta),
        \+ memberchk(R, Visited),
        maplist(=(0), Seq),
        can_reach_final_through_0(R, QFs, Delta, [R|Visited]).


exists_path(Q, Delta) :-
        delta_to_assoc(Delta, DA),
        states_nexts([Q], DA, States0),
        states_closure(States0, DA, States),
        memberchk(Q, States).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                         Minimize automaton
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

% For now, all we do is focusing on the states that can actually be reached.
% Comment out the first clause for full minimization.

aut_minimal(Aut0, Aut) :- !, aut_only_reachables(Aut0, Aut).

aut_minimal(Aut0, Aut) :-
        aut_only_reachables(Aut0, Aut1),
        Aut1 = aut(Qs0,QFs0,Q00,Delta0),
        phrase(list_pairs(Qs0), Pairs),
        empty_assoc(Same0),
        foldl(register_state, Pairs, Same0, Same1),
        foldl(distinct_halting(QFs0), Pairs, Same1, Same2),
        delta_to_assoc(Delta0, DA),
        saturate_distincts(Pairs, DA, Same2, Same),
        assoc_to_list(Same, Sames0),
        include(second_is(true), Sames0, Sames1),
        pairs_keys(Sames1, Sames),
        group_pairs_by_key(Sames, Groups),
        maplist(delta_to_representative(Groups), Delta0, Delta),
        synonym_or_same(Groups, Q00, Q0),
        states_representatives(Groups, QFs0, QFs),
        states_representatives(Groups, Qs0, Qs),
        Aut2 = aut(Qs,QFs,Q0,Delta),
        aut_only_reachables(Aut2, Aut).

states_representatives(Groups, Qs0, Qs) :-
        maplist(synonym_or_same(Groups), Qs0, Qs1),
        sort(Qs1, Qs). % remove duplicates

delta_to_representative(Gs, delta(Q0,S,P0), delta(Q,S,P)) :-
        synonym_or_same(Gs, Q0, Q),
        synonym_or_same(Gs, P0, P).


% take the representative of the first fitting group we find, and
% leave the state unchanged if there is no fitting group.
synonym_or_same(Gs, Q0, Q) :-
        (   member(Q-Qs, Gs), memberchk(Q0, Qs) -> true
        ;   Q = Q0
        ).

saturate_distincts(Pairs, DA, Same0, Same) :-
        foldl(mark_distinct(DA), Pairs, Same0, Same1),
        (   Same0 == Same1 -> Same = Same0
        ;   saturate_distincts(Pairs, DA, Same1, Same)
        ).

mark_distinct(DA, A-B, Same0, Same) :-
        (   distinct_states(A, B, DA, Same0) ->
            put_assoc(A-B, Same0, false, Same)
        ;   Same0 = Same
        ).


distinct_states(A, B, DA, Same0) :-
        (   distinct_states_(A, B, DA, Same0)
        ;   distinct_states_(B, A, DA, Same0)
        ).

distinct_states_(A, B, DA, Same0) :-
        state_nexts(A, DA, NextsA),
        state_nexts(B, DA, NextsB),
        (   member(W-P, NextsA) *->
            (   member(W-Q, NextsB) ->
                P \== Q,
                (   get_assoc(P-Q, Same0, false)
                ;   get_assoc(Q-P, Same0, false)
                )
            ;   true
            )
        ;   NextsB = [_|_]
        ).

second_is(X, _-X).

distinct_halting(QFs, A-B, Same0, Same) :-
        state_halting_truth(QFs, A, TA),
        state_halting_truth(QFs, B, TB),
        (   TA == TB -> Same0 = Same
        ;   put_assoc(A-B, Same0, false, Same)
        ).

state_halting_truth(QFs, Q, T) :-
        (   memberchk(Q, QFs) -> T = true
        ;   T = false
        ).

list_pairs([]) --> [].
list_pairs([L|Ls]) --> pairs_(Ls, L), list_pairs(Ls).

pairs_([], _) --> [].
pairs_([L|Ls], X) --> [X-L], pairs_(Ls, X).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Reduce a deterministic automaton so that it only contains states
   that are actually reachable, and name its states q(0),...,q(N).
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

aut_only_reachables(aut(_,QFs0,Q00,Delta0), aut(Qs,QFs,Q0,Delta)) :-
        delta_to_assoc(Delta0, DA),
        states_closure([Q00], DA, Reachables),
        empty_assoc(Syn0),
        foldl(rename_state, Reachables, 0-Syn0, _-Syn),
        maplist(state_synonym(Syn), Reachables, Qs),
        include(in_assoc(Syn), QFs0, QFs1),
        maplist(state_synonym(Syn), QFs1, QFs),
        state_synonym(Syn, Q00, Q0),
        include(delta_reachable(Syn), Delta0, Delta1),
        maplist(delta_synonym(Syn), Delta1, Delta).

state_synonym(Syn, Q0, Q) :- get_assoc(Q0, Syn, Q).

rename_state(State, N0-Syn0, N-Syn) :-
        put_assoc(State, Syn0, q(N0), Syn),
        N #= N0 + 1.

delta_reachable(Syn, delta(P,_,Q)) :-
        in_assoc(Syn, P),
        in_assoc(Syn, Q).

delta_synonym(Syn, delta(P0,S,Q0), delta(P,S,Q)) :-
        state_synonym(Syn, P0, P),
        state_synonym(Syn, Q0, Q).


:- initialization((test_ndfa(1, NDFA), ndfa_dfa(NDFA, aut([q(0),q(1),q(2),q(3),q(4)],[q(1),q(2),q(3),q(4)],q(1),[delta(q(1),0,q(2)),delta(q(1),1,q(3)),delta(q(1),2,q(4)),delta(q(2),0,q(2)),delta(q(2),1,q(3)),delta(q(2),2,q(4)),delta(q(3),0,q(0)),delta(q(3),1,q(3)),delta(q(3),2,q(4)),delta(q(4),0,q(0)),delta(q(4),1,q(0)),delta(q(4),2,q(4)),delta(q(0),0,q(0)),delta(q(0),1,q(0)),delta(q(0),2,q(0))])))).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                     Delete a track of an automaton
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

aut_delete_track(aut(Qs,QFs,Q0,Delta0), Track, aut(Qs,QFs,Q0,Delta)) :-
        maplist(delta_remove_track(Track), Delta0, Delta).

delta_remove_track(Track, delta(Q0,Seq0,Q1), delta(Q0,Seq,Q1)) :-
        (   Track == 0, Seq0 = [_] ->
            Seq = epsilon
        ;   delete_nth(Seq0, Track, Seq)
        ).

delete_nth(Ls0, N, Ls) :-
        length(Prefix, N),
        append(Prefix, [_|Rest], Ls0),
        append(Prefix, Rest, Ls).

:- initialization(delete_nth([a,b,c,d], 2, [a,b,d])).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
                            Term rewriting

  Normalize input formula to:
    F =< const
    F = const
    A /\ B (and)
    A \/ B (or)
    not(F)
    exists(X, F)
  furthermore, simplify atomic formulas to
      a1*x1 +  a2*x2 + ... + a_n*x_n  (<)=   const
  and represent this using lists as [Var-Coeff] pairs on the left side.
  A = B could be reduced to A =< B /\ B =< A, but we don't.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

normal_form(A0 /\ B0, A /\ B)  :- normal_form(A0, A), normal_form(B0, B).
normal_form(A0 \/ B0, A \/ B)  :- normal_form(A0, A), normal_form(B0, B).
normal_form(A0 = B0, Ls = C)   :- exprs_linsum_c(A0, B0, Ls, C).
normal_form(A0 =< B0, Ls =< C) :- exprs_linsum_c(A0, B0, Ls, C).
normal_form(A0 >= B0, NF)      :- normal_form(B0 =< A0, NF).
normal_form(A0 < B0, NF)       :- normal_form(A0 + 1 =< B0, NF).
normal_form(A0 > B0, NF)       :- normal_form(B0 < A0, NF).
normal_form(forall(X,F), NF)   :- normal_form(not(exists(X,not(F))), NF).
normal_form(not(F), not(NF))   :- normal_form(F, NF).
normal_form(A ==> B, NF)       :- normal_form(not(A) \/ B, NF).
normal_form(exists(X,F), exists(X,NF)) :- normal_form(F, NF).

exprs_linsum_c(Left0, Right0, Lefts, C) :-
        expr_linsum_const(Left0, Lefts1, CL),
        expr_linsum_const(Right0, Rights1, CR),
        C #= CR - CL,
        maplist(coeff_negative, Rights1, Rights),
        append(Lefts1, Rights, Lefts2),
        sumup(Lefts2, Lefts).

coeff_negative(V-C0, V-C) :- C #= -C0.

sumup(Ls0, Ls) :-
        keysort(Ls0, Ls1),
        var_group_pairs_by_key(Ls1, Groups0),
        maplist(sumup_second, Groups0, Ls2),
        exclude(second_is(0), Ls2, Ls).

% like group_pairs_by_key/2, working around a (current) limitation in
% library(pairs) that prevents variables as keys. Can be removed as
% soon as group_pairs_by_key/2 becomes sufficiently general in SWI.

var_group_pairs_by_key([], []).
var_group_pairs_by_key([M-N|T0], [M-[N|TN]|T]) :-
	same_key(M, T0, TN, T1),
	var_group_pairs_by_key(T1, T).

same_key(M0, [M-N|T0], [N|TN], T) :-
	M0 == M, !,
	same_key(M, T0, TN, T).
same_key(_, L, [], L).


sumup_second(V-Cs, V-C) :- sumlist(Cs, C).

pvar(V) :- var(V), !.
pvar(V) :- atom(V).

% separate an expression into a polynomial, represented as a list of
% pairs V-Coeff, and a constant C.

expr_linsum_const(V, [V-1], 0) :- pvar(V), !.
expr_linsum_const(C, [], C)    :- integer(C), !.
expr_linsum_const(-A, Ls, C)   :-
        expr_linsum_const(A, ALs, AC),
        !,
        maplist(coeff_negative, ALs, Ls),
        C #= -AC.
expr_linsum_const(A+B, Ls, C)  :-
        expr_linsum_const(A, ALs, AC),
        expr_linsum_const(B, BLs, BC),
        !,
        append(ALs, BLs, Ls0),
        sumup(Ls0, Ls),
        C #= AC + BC.
expr_linsum_const(A*B, Ls, C) :-
        expr_linsum_const(A, ALs, AC),
        expr_linsum_const(B, BLs, BC),
        product(ALs, AC, BLs, BC, Ls0, C),
        !,
        sumup(Ls0, Ls).
expr_linsum_const(A-B, Ls, C) :-
        expr_linsum_const(A, ALs, AC),
        expr_linsum_const(B, BLs, BC),
        !,
        maplist(coeff_negative, BLs, BLs1),
        append(ALs, BLs1, Ls0),
        sumup(Ls0, Ls),
        C #= AC - BC.
expr_linsum_const(Expr, _, _) :- !,
        throw('illegal arithmetic expression'-Expr).

product([], AC, BLs, BC, Ls, C) :-
        maplist(coeff_times(AC), BLs, Ls),
        C #= AC*BC.
product(ALs, AC, [], BC, Ls, C) :-
        maplist(coeff_times(BC), ALs, Ls),
        C #= AC*BC.

coeff_times(Factor, V-C0, V-C) :- C #= C0*Factor.

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   (Existentially) quantified variables in the normal form.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

nf_quantified_variables(T, Vs) :-
        phrase(nf_quantified(T), Vs0),
        sort(Vs0, Vs). % remove duplicates

nf_quantified(exists(X, F)) --> [X], nf_quantified(F).
nf_quantified(not(Term))    --> nf_quantified(Term).
nf_quantified(A /\ B)       --> nf_quantified(A), nf_quantified(B).
nf_quantified(A \/ B)       --> nf_quantified(A), nf_quantified(B).
nf_quantified(_ = _)        --> [].
nf_quantified(_ =< _)       --> [].

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Variables that occur *somewhere* in NOT (existentially) quantified
   form. We cannot just subtract the quantified variables from the
   list of all variables, because a variable may be erroneously used
   as both. We want to detect this case and report it as an error.

   We establish the definitive order of variables occurring in the
   formula, and thus of the tracks in the automaton, by using
   list_to_set/2 on the list of all variables. This is more reliable
   than sort/2, since the relative (term-)order of logical variables
   may change (for example, due to garbage collection or stack
   shifting) during program execution in future SWI versions.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

nf_unquantified_variables(NF, Vs) :-
        phrase(nf_unquantified(NF), Vs0),
        list_to_set(Vs0, Vs).

nf_unquantified(exists(X, F)) -->
        { nf_unquantified_variables(F, Vs0),
          list_delete([X], Vs0, Vs) },
        list(Vs).
nf_unquantified(not(Term))    --> nf_unquantified(Term).
nf_unquantified(A /\ B)       --> nf_unquantified(A), nf_unquantified(B).
nf_unquantified(A \/ B)       --> nf_unquantified(A), nf_unquantified(B).
nf_unquantified(Ls = _)       --> firsts(Ls).
nf_unquantified(Ls =< _)      --> firsts(Ls).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Variables that occur anywhere in the normal form.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

nf_variables(NF, Vs) :-
        phrase(nf_vars(NF), Vs0),
        sort(Vs0, Vs).          % remove duplicates

nf_vars(exists(X,F)) --> [X], nf_vars(F).
nf_vars(not(F))      --> nf_vars(F).
nf_vars(A /\ B)      --> nf_vars(A), nf_vars(B).
nf_vars(A \/ B)      --> nf_vars(A), nf_vars(B).
nf_vars(A = _)       --> firsts(A).
nf_vars(A =< _)      --> firsts(A).

firsts(Pairs) --> { pairs_keys(Pairs, Keys) }, list(Keys).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Main entry point for normalization.  Takes a formula, makes sure
   each variable occurs in each (in)equality, (if necessary, enforce
   with coefficient 0), same order everywhere.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */


formula_normalized(F, NF) :-
        normal_form(F, NF0),
        well_formed(NF0),
        nf_variables(NF0, Vs0),
        nf_quantified_variables(NF0, QVs),
        nf_unquantified_variables(NF0, UVs),
        (   member(V, UVs), member(V1, QVs), V1 == V ->
            throw('variable occurs quantified and free'-V)
        ;   true
        ),
        list_delete(QVs, Vs0, Vs),
        merge_variables(Vs, NF0, NF).

well_formed(exists(X, F)) :-
        nf_quantified_variables(F, Vs),
        (   member(X0, Vs), X == X0 ->
            throw('variable twice-quantified'-X)
        ;   well_formed(F)
        ).
well_formed(not(Term)) :- well_formed(Term).
well_formed(A /\ B)    :- well_formed(A), well_formed(B).
well_formed(A \/ B)    :- well_formed(A), well_formed(B).
well_formed(_ = _).
well_formed(_ =< _).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   A DCG is used to implicitly pass the variables around as an
   argument. Existentially quantified variables are added (with
   coefficient 0, if necessary) to all expressions within their scope.
   The tracks corresponding to existentially quantified variables are
   later removed from the automaton.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

merge_variables(Vs, NF0, NF) :-
        phrase(merge_(NF0, NF), [Vs], _).

state(S), [S] --> [S].

merge_(not(Term0), not(Term)) --> merge_(Term0, Term).
merge_(exists(V,Term0), exists(V,Term)) -->
        state(Vs0),
        { merge_variables([V|Vs0], Term0, Term) }.
merge_(A0/\B0, A/\B)      --> merge_(A0, A), merge_(B0, B).
merge_(A0\/B0, A\/B)      --> merge_(A0, A), merge_(B0, B).
merge_(Ls0 =< C, Ls =< C) --> merge_linsum(Ls0, Ls).
merge_(Ls0 = C, Ls = C)   --> merge_linsum(Ls0, Ls).

merge_linsum(Ls0, Ls) -->
        state(Vs),
        { maplist(v_with_coeff(Ls0), Vs, Ls) }.

v_with_coeff(Ls0, V, V-Coeff) :-
        (   member(V0-Coeff, Ls0), V == V0 -> true
        ;   Coeff = 0
        ).

list_delete(Ds, Ls0, Ls) :- foldl(delete_, Ds, Ls0, Ls).

delete_(D, Ls0, Ls) :-
        (   select(D0, Ls0, Ls), D0 == D -> true
        ;   Ls0 = Ls
        ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% "x = 1":
test_aut(1, aut([q(0), q(1)], [q(0)], q(1), [delta(q(0), [0], q(0)), delta(q(1), [1], q(0))])).

% "x =< 4":
test_aut(2, aut([q(-1), q(0), q(1), q(2), q(4)], [q(0), q(1), q(2), q(4)], q(4), [delta(q(-1), [0], q(-1)), delta(q(-1), [1], q(-1)), delta(q(0), [0], q(0)), delta(q(0), [1], q(-1)), delta(q(1), [0], q(0)), delta(q(1), [1], q(0)), delta(q(2), [0], q(1)), delta(q(2), [1], q(0)), delta(q(4), [0], q(2)), delta(q(4), [1], q(1))])).

% "x >= 5"  (-x =< -5)
test_aut(3, aut([q(-5), q(-3), q(-2), q(-1), q(0)], [q(0)], q(-5), [delta(q(-5), [0], q(-3)), delta(q(-5), [1], q(-2)), delta(q(-3), [0], q(-2)), delta(q(-3), [1], q(-1)), delta(q(-2), [0], q(-1)), delta(q(-2), [1], q(-1)), delta(q(-1), [0], q(-1)), delta(q(-1), [1], q(0)), delta(q(0), [0], q(0)), delta(q(0), [1], q(0))])).


:- initialization((test_aut(1, A1), test_aut(2, A2), aut_intersection(A1,A2,Int), \+ empty_automaton(Int))).
:- initialization((test_aut(1, A1), test_aut(3, A3), aut_intersection(A1,A3,Int), empty_automaton(Int))).

eq_satisfiable(Cs, Sum) :-
        eq_automaton(Cs, Sum, A),
        \+ empty_automaton(A).


test_eq(1, [1, 2, -3], 1).  % x + 2*y - 3z = 1
test_eq(2, [1, 2],     3).
test_eq(3, [2, 5],    20).

test_ineq(1, [2,-1], -1).

:- initialization((\+ (member(T, [1,2,3]), test_eq(T, Cs, Sum), \+ eq_satisfiable(Cs, Sum)))).

ineq_satisfiable(Cs, Sum) :-
        ineq_automaton(Cs, Sum, Aut),
        \+ empty_automaton(Aut).


% syntax check

is_formula(Var)            :- var(Var), !, false.
is_formula(AF)             :- is_relation(AF).
is_formula(not(F))         :- is_formula(F).
is_formula(A /\ B)         :- is_formula(A), is_formula(B).
is_formula(A \/ B)         :- is_formula(A), is_formula(B).
is_formula(A ==> B)        :- is_formula(A), is_formula(B).
is_formula(forall(Var, F)) :- pvar(Var), is_formula(F).
is_formula(exists(Var, F)) :- pvar(Var), is_formula(F).


is_relation(AF) :-
        AF =.. [Op,A,B],
        memberchk(Op, [<,>,=,>=,=<]),
        is_expr(A),
        is_expr(B).

is_expr(Var)   :- pvar(Var), !.
is_expr(Num)   :- integer(Num).
is_expr(-Expr) :- is_expr(Expr).
is_expr(Expr)  :-
        Expr =.. [Op,A,B],
        memberchk(Op, [+,-,*]),
        is_expr(A),
        is_expr(B).

formula_automaton(F, Aut) :-
        formula_normalized(F, NF),
        nf_automaton(NF, Aut).

nf_automaton(Lefts = Y, A) :-
        pairs_values(Lefts, Cs),
        eq_automaton(Cs, Y, A).
nf_automaton(Lefts =< Y, A) :-
        pairs_values(Lefts, Cs),
        ineq_automaton(Cs, Y, A).
nf_automaton(not(F), A) :-
        nf_automaton(F, A1),
        aut_complement(A1, A).
nf_automaton(X /\ Y, A) :-
        nf_automaton(X, A1),
        nf_automaton(Y, A2),
        aut_intersection(A1, A2, A).
nf_automaton(X \/ Y, A) :-
        nf_automaton(X, A1),
        nf_automaton(Y, A2),
        aut_union(A1, A2, A).
nf_automaton(exists(Var, F), A) :-
        nf_automaton(F, A0),
        ndfa_dfa(A0, A1),
        nf_unquantified_variables(F, Vs),
        nth0(N, Vs, Var0),
        Var0 == Var,
        aut_delete_track(A1, N, A).

syntax_ok(Formula) :-
        (   is_formula(Formula) -> true
        ;   throw('invalid formula'-Formula)
        ).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Satisfiability and validity check.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

valid(Formula) :- \+ satisfiable(not(Formula)).

satisfiable(Formula) :-
        syntax_ok(Formula),
        satisfiable_(Formula).

satisfiable_(Formula) :-
        formula_automaton(Formula, Aut),
        \+ empty_automaton(Aut).

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Print a solution (if there is one) for a given formula and
   establish variable bindings. On backtracking, show alternatives.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

solution(Formula) :-
        syntax_ok(Formula),
        formula_normalized(Formula, NF),
        nf_automaton(NF, Aut),
        nf_variables(NF, Vars0),
        nf_quantified_variables(NF, QVs),
        list_delete(QVs, Vars0, Vars),
        ndfa_dfa(Aut, Aut1),
        \+ empty_automaton(Aut1),
        length(Path0, _),
        automaton_haltingpath(Aut1, Path0),
        transpose(Path0, Path),
        pairs_keys_values(Pairs, Vars, Path),
        maplist(show_track, Pairs).

show_track(Var-Digits) :-
        foldl(binary_num, Digits, 0-0, _-N),
        (   var(Var) -> Var = N
        ;   portray_clause(Var=N)
        ).

binary_num(D, Exp0-N0, Exp-N) :-
        N #= N0 + D*(2^Exp0),
        Exp #= Exp0 + 1.

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Strategy: We first run a breadth-first search to see whether there
   is a solution of the indicated length. Then, we use the layering
   information to construct a path in reverse.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

automaton_haltingpath(aut(_,QFs,Q0,Delta), Path) :-
        delta_to_assoc(Delta, DA),
        foldl(reachables(DA), Path, Rs0, [Q0], Lasts),
        reverse(Rs0, Rs),
        member(Final, Lasts),
        memberchk(Final, QFs),
        phrase(halting_path(Rs, Final, DA), Path0),
        reverse(Path0, Path).

reachables(DA, _, Qs0, Qs0, Qs) :- states_nexts(Qs0, DA, Qs).

halting_path([], _, _)  --> [].
halting_path([Rs|Rss], Next, DA) --> [Symbol],
        { member(Q, Rs),
          state_nexts(Q, DA, Nexts),
          member(Symbol-Next, Nexts) },
        halting_path(Rss, Q, DA).


/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Test cases.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */


test(1, valid(y > 1 /\ x = 3 /\ x + y < 19  ==>  x + 19 > y)).    % p. 102
test(2, valid(y > 1 /\ x = 3 /\ not(x + y < 19) ==>  y + y > y)). % p. 102
test(3, valid(x = 3 /\ y = 1 ==> 3*x + y = 10)).                  % p. 103
test(4, valid(2*y + 3*x = 30 /\ not(not(x=0)) ==> y = 15)).       % p. 78 (addendum)
test(5, valid(y = 15 /\ x = 0 ==> y = 15)).
test(6, \+ valid(x+y > 0)).
test(7, valid(forall(x,exists(y,x+y > 5)))).
test(8, valid(exists(y, x+y > 5))).
test(9, valid(forall(x,exists(y, y > 2)))).
test(10, valid(exists(y, x+y > 1))).
test(11, valid(x>0 \/ x = 0)).
test(12, \+ valid(x+y>1)).
test(a1, valid(forall(x, exists(y, y = x)))).
test(a2, satisfiable(exists(x, exists(y, x > 0 /\ y > x)))).
test(a3, satisfiable(exists(x, x > 0 /\ exists(y, y > x)))).
test(a4, \+ valid(exists(x, x > 3 /\ x < 3 \/ y = 5))).
test(a5, \+ valid(forall(y, exists(x, x > 3 /\ x < 3 \/ y = 5)))).
test(a6, \+ valid(x > 3 /\ x > 3 ==> x > 4)).

test(13, N, \+ valid(exists(x, x > N /\ x < N))).
test(14, N, valid(not(exists(x, x > N /\ x < N)))).
test(15, N, valid(exists(x, x > N /\ exists(y, y > x)))).
test(16, N, valid(exists(x, x = N) /\ exists(y, y > N))).

run_tests :-
        run(_),
        false.
run_tests.

run(ID) :-
        test(ID, Test),
        do_test(ID, none, Test).

run(ID, N) :-
        test(ID, N, Test),
        do_test(ID, N, Test).

run_tests(N) :-
        test(ID, N, Test),
        do_test(ID, N, Test),
        false.
run_tests(_).

do_test(ID, N, Test) :-
        format("~w (~w)... ", [ID,N]),
        (   call(Test) -> writeln(ok)
        ;   throw(test_failed(Test))
        ).

run :-
        run_tests,
        length(_, N),
        run_tests(N),
        false.


%:- presprover:run.

