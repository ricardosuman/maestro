## Karpathy guidelines — applies to every change

- **Think before coding.** State your assumptions. If the spec allows several interpretations, name them and take the simplest, saying which you took — never choose silently. If something is unclear, stop and report it as a GAP instead of guessing.
- **Simplicity first.** The minimum code that solves the task: no features beyond what was asked, no abstractions for single-use code, no configurability nobody requested, no error handling for impossible cases. If it could be a third of the size, rewrite it.
- **Surgical changes.** Touch only what the task requires. Don't improve adjacent code, comments or formatting; don't refactor what isn't broken; match the existing style even if you'd do it differently. Remove only the imports/variables/functions YOUR change made unused; mention pre-existing dead code, don't delete it. Every changed line must trace to the spec.
- **Goal-driven execution.** Turn the task into a verifiable goal — a test that fails before and passes after, or a command whose output proves it — loop until it's verified, and paste that output in the report.
