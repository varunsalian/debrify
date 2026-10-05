"""Exact syntax-adapter input reuse confined to Debrify TV mutation fixtures.

The production CLI check remains uncached. Every guard comparison still runs;
only unchanged syntax-adapter units can be reused, with independent batched /
per-unit equality proofs in both adapter modes and defensive result copies.
"""
from contextlib import contextmanager
import copy
import hashlib
import json


@contextmanager
def exact_parse_cache(package):
    import check_verbatim_moves as verifier
    real_parse = verifier.parse
    cache = {}
    proof = None

    def key(path, source, parser, binding):
        return (str(parser), binding, path, source)

    def parsed(sources, parser=None, *, occurrence_bindings=False):
        nonlocal proof
        parser = parser or package
        # Syntax units have no shared resolution state. Prove that property on
        # the first real multi-unit fixture, including every emitted AST/binder
        # field, before reusing its unchanged units in subsequent mutations.
        if proof is None and len(set(sources.values())) > 1:
            digests = {}
            for binding in (False, True):
                batch = real_parse(sources, parser, occurrence_bindings=binding)
                separate = {}
                for path, source in sources.items():
                    unit = real_parse({path: source}, parser,
                                      occurrence_bindings=binding)[path]
                    separate[path] = unit
                canonical = lambda value: json.dumps(value, sort_keys=True)
                assert canonical(batch) == canonical(separate), (
                    'Batched/per-unit adapter output differs', binding)
                digests[str(binding)] = hashlib.sha256(
                    canonical(batch).encode()).hexdigest()
                for path, source in sources.items():
                    cache[key(path, source, parser, binding)] = copy.deepcopy(batch[path])
            proof = {'units': len(sources), 'adapter_modes': digests}
            print('TV fixture parser batched/per-unit equality: ' +
                  json.dumps(proof, sort_keys=True))
        missing = {path: source for path, source in sources.items()
                   if key(path, source, parser, occurrence_bindings) not in cache}
        if missing:
            fresh = real_parse(missing, parser,
                               occurrence_bindings=occurrence_bindings)
            for path, source in missing.items():
                cache[key(path, source, parser, occurrence_bindings)] = copy.deepcopy(fresh[path])
        return {path: copy.deepcopy(cache[key(path, source, parser, occurrence_bindings)])
                for path, source in sources.items()}

    verifier.parse = parsed
    try:
        yield
        assert proof is not None, 'TV adapter equality proof did not run'
    finally:
        verifier.parse = real_parse
