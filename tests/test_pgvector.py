"""pgvector dense-retrieval tests.

The embedding test needs no database. The round-trip test runs only when
RITUVA_DB points at Postgres (CI brings up a pgvector service; locally,
`docker compose up -d` then export RITUVA_DB) and is skipped otherwise.
"""
import math
import os

import pytest

from rituva.pgvector_index import _DIM, embed

_PG = os.environ.get("RITUVA_DB", "").startswith(("postgresql://", "postgres://"))


def test_embed_is_deterministic_and_l2_normalised():
    a = embed("dal palak with a squeeze of lemon")
    b = embed("dal palak with a squeeze of lemon")
    assert a == b                                   # stable across calls/processes
    assert len(a) == _DIM
    assert abs(math.sqrt(sum(x * x for x in a)) - 1.0) < 1e-6
    assert embed("rice") != embed("roti")           # different text → different vector


def test_empty_text_embeds_to_zero_vector():
    v = embed("")
    assert len(v) == _DIM
    assert all(x == 0.0 for x in v)


@pytest.mark.skipif(not _PG, reason="RITUVA_DB is not Postgres")
def test_pgvector_round_trip_ranks_relevant_docs():
    from rituva import store
    from rituva.pgvector_index import PgVectorDense
    from rituva.retrieval import _build_corpus

    conn = store.connect(os.environ["RITUVA_DB"])
    try:
        docs = _build_corpus()
        index = PgVectorDense(conn, docs)
        # every corpus doc was embedded into the vector table
        n = conn.execute("SELECT count(*) AS n FROM doc_vectors")[0]["n"]
        assert n == len(docs)
        scores = index.score("south indian dosa breakfast")
        assert scores, "pgvector returned no matches"
        assert all(0 <= i < len(docs) for i in scores)
        # a dosa recipe should rank among the top matches
        top = sorted(scores, key=lambda i: -scores[i])[:5]
        assert any("dosa" in docs[i].display.lower() for i in top)
    finally:
        conn.close()


@pytest.mark.skipif(not _PG, reason="RITUVA_DB is not Postgres")
def test_postgres_store_member_crud():
    """The store runs identically on Postgres (PRD §12.3), delete included."""
    from rituva import store
    from rituva.knowledge import SEED_MEMBERS

    conn = store.connect(os.environ["RITUVA_DB"])
    try:
        store.save_member(conn, SEED_MEMBERS["aarav"])
        store.save_member(conn, SEED_MEMBERS["diya"])
        assert store.get_member(conn, "aarav").name == "Aarav"
        assert {"aarav", "diya"} <= {m.id for m in store.list_members(conn)}
        store.delete_member(conn, "diya")
        assert store.get_member(conn, "diya") is None
    finally:
        conn.close()


@pytest.mark.skipif(not _PG, reason="RITUVA_DB is not Postgres")
def test_retrieval_uses_pgvector_when_postgres():
    # Imported fresh so the module-level index builds against the configured DB.
    import importlib

    from rituva import retrieval
    importlib.reload(retrieval)
    assert type(retrieval._INDEX.dense).__name__ == "PgVectorDense"
    rules = retrieval.rules_for("keep blood sugar low for diabetes", top=3)
    assert rules and all(r.kind == "rule" for r in rules)
