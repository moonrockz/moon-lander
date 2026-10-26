## 1. Make mediator error reports valid and immutable

Bead: lander-4us.23

- [x] 1.1 Restrict error and failure construction; derive publish errors from handler outcomes and expose safe failure accessors.
- [x] 1.2 Use core TimeLimit in timeout errors and retain supported rejection and derived construction paths.
- [x] 1.3 Migrate core consumers and compiled documentation; test outcome boundaries, positions, copy isolation and messages on all four core targets.

## 2. Use typed async limits and handler alternatives

Bead: lander-4us.24

Depends on group 1. Develop and land together; close beads only after merge.

- [x] 2.1 Accept TimeLimit in timeout middleware and report the same valid limit; migrate async consumers and compiled examples.
- [x] 2.2 Replace wraps_core with typed alternatives and derive sequential and concurrent publish errors through the core API; test wrapping, add and middleware.
- [x] 2.3 Verify the existing supported-target explanation from #78 as finding 3 already satisfied.
- [x] 2.4 Update generated interfaces, run format and check, complete checklist review, archive this change and validate all specifications strictly.
